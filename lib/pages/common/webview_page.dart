import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_preferences.dart';

/// WebView 页面 - 加载指定 URL
class WebViewPage extends StatefulWidget {
  final String title;
  final String url;
  final bool initialFullscreen;
  final bool hideUrl;

  const WebViewPage({
    super.key,
    required this.title,
    required this.url,
    this.initialFullscreen = false,
    this.hideUrl = false,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String _currentUrl = '';
  int _loadingProgress = 0;
  late bool _isFullscreen;

  // ---------- fullscreen state persistence ----------
  static const _fullscreenKey = 'webview_fullscreen';

  Map<String, bool> _readFullscreenMap() {
    final raw = AppPreferences.getString(_fullscreenKey);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return Map<String, bool>.from(decoded as Map);
    } catch (_) {
      return {};
    }
  }

  void _saveFullscreenState(bool value) {
    final map = _readFullscreenMap();
    map[widget.url] = value;
    AppPreferences.putString(_fullscreenKey, jsonEncode(map));
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;

    // Determine initial fullscreen from persisted state or constructor param
    final persisted = _readFullscreenMap();
    _isFullscreen = persisted[widget.url] ?? widget.initialFullscreen;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _loadingProgress = progress);
          },
          onPageStarted: (url) {
            debugPrint('[WebView] onPageStarted: $url');
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (url) {
            debugPrint('[WebView] onPageFinished: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
              });
            }
          },
          onWebResourceError: (error) {
            debugPrint('[WebView] onWebResourceError: '
                '${error.errorType} - ${error.description} '
                '(url: ${error.url}, isForMainFrame: ${error.isForMainFrame})');
            // Only show error for main-frame failures
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
                _errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (request) {
            debugPrint('[WebView] onNavigationRequest: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      );

    // Android 默认 useWideViewPort=false，会把布局视口锁死为设备宽度，
    // 桌面布局页面（如 DSM 主页）只能显示一部分；开启后与系统浏览器行为一致：
    // 按页面天然宽度排版并整页缩放适配屏幕（loadWithOverviewMode 默认已开启）。
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setUseWideViewPort(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resolvedUrl = DsmApi().resolveUrlWithAuth(widget.url);
      _controller.loadRequest(Uri.parse(resolvedUrl));
    });
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    _saveFullscreenState(_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    // Restore system UI when leaving
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------- build ----------

  /// Android 默认用纹理模式(TLHC)渲染 WebView，触摸事件是合成转发的，
  /// 缩放页面内滚动会出现「滑动不跟手、松手后回弹跳位」；改用 Hybrid
  /// Composition 让原生 WebView 直接接收触摸事件，滚动行为与浏览器一致。
  Widget _buildWebView() {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: platform,
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(controller: _controller);
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        // WebView – always SizedBox.expand so it fills the parent
        SizedBox.expand(
          child: _hasError ? _buildErrorWidget() : _buildWebView(),
        ),
        // progress bar
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _loadingProgress > 0 ? _loadingProgress / 100.0 : null,
              minHeight: 2,
            ),
          ),
        // fullscreen floating button (draggable)
        if (_isFullscreen) _buildFullscreenFab(),
      ],
    );

    if (_isFullscreen) {
      // Fullscreen: no AppBar, no bottom nav
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(body: body),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              setState(() {
                _hasError = false;
                _isLoading = true;
              });
              _controller.reload();
            },
          ),
          IconButton(
            icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            tooltip: _isFullscreen ? '退出全屏' : '全屏',
            onPressed: _toggleFullscreen,
          ),
          PopupMenuButton<String>(
            onSelected: _onMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'back', child: Text('后退')),
              const PopupMenuItem(value: 'forward', child: Text('前进')),
              if (!widget.hideUrl)
                const PopupMenuItem(value: 'copy_url', child: Text('复制链接')),
            ],
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? '加载失败',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _currentUrl,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isLoading = true;
                });
                _controller.loadRequest(Uri.parse(DsmApi().resolveUrlWithAuth(widget.url)));
              },
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// Draggable floating button shown in fullscreen mode.
  Widget _buildFullscreenFab() {
    return _DraggableFab(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: _showFullscreenControls,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.menu, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  void _showFullscreenControls() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                if (!widget.hideUrl)
                  Text(
                    _currentUrl,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlButton(
                      icon: Icons.arrow_back,
                      label: '后退',
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (await _controller.canGoBack()) _controller.goBack();
                      },
                    ),
                    _controlButton(
                      icon: Icons.arrow_forward,
                      label: '前进',
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (await _controller.canGoForward()) _controller.goForward();
                      },
                    ),
                    _controlButton(
                      icon: Icons.refresh,
                      label: '刷新',
                      onTap: () {
                        Navigator.pop(ctx);
                        _controller.reload();
                      },
                    ),
                    _controlButton(
                      icon: Icons.fullscreen_exit,
                      label: '退出全屏',
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleFullscreen();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _onMenuAction(String action) async {
    switch (action) {
      case 'back':
        if (await _controller.canGoBack()) _controller.goBack();
        break;
      case 'forward':
        if (await _controller.canGoForward()) _controller.goForward();
        break;
      case 'copy_url':
        await Clipboard.setData(ClipboardData(text: _currentUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('链接已复制'), duration: Duration(seconds: 1)),
          );
        }
        break;
    }
  }
}

/// A simple draggable floating widget for fullscreen controls.
class _DraggableFab extends StatefulWidget {
  const _DraggableFab({required this.child});
  final Widget child;

  @override
  State<_DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<_DraggableFab> {
  Offset _position = const Offset(20, 300);
  Offset _startPointer = Offset.zero;
  Offset _startPosition = Offset.zero;
  bool _isTap = true;

  static const _edgePadding = 10.0;
  static const _topPadding = 60.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Position on the right edge on first build
    if (_position == const Offset(20, 300)) {
      final size = MediaQuery.of(context).size;
      _position = Offset(size.width - 60, size.height * 0.55);
    }
  }

  void _onPanStart(DragStartDetails details) {
    _startPointer = details.globalPosition;
    _startPosition = _position;
    _isTap = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final delta = details.globalPosition - _startPointer;
    if (delta.distance > 3) _isTap = false;
    if (!_isTap) {
      setState(() => _position = _clamp(_startPosition + delta));
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isTap) return; // let InkWell handle tap
    // Snap to nearest edge
    final screenW = MediaQuery.of(context).size.width;
    final isLeft = _position.dx < screenW / 2;
    setState(() {
      _position = _clamp(Offset(
        isLeft ? _edgePadding : screenW - 60,
        _position.dy,
      ));
    });
  }

  Offset _clamp(Offset p) {
    final size = MediaQuery.of(context).size;
    return Offset(
      p.dx.clamp(_edgePadding, size.width - 60),
      p.dy.clamp(_topPadding, size.height - 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: widget.child,
      ),
    );
  }
}

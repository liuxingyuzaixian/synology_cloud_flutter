import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_preferences.dart';
import '../components/app_dialog.dart';

/// 更新 manifest 地址（按平台区分）
const kUpdateJsonUrlAndroid = 'http://zhanglei.nasfuns.fun:8083/artifactory/synology_cloud/app_update_android.json';
const kUpdateJsonUrlIos = 'http://zhanglei.nasfuns.fun:8083/artifactory/synology_cloud/app_update_ios.json';
const kUpdateLastCheckKey = 'update_last_check_date';
const kUpdateCachedManifestKey = 'update_cached_manifest';

class UpdateService {
  UpdateService._();

  /// 上次成功拉取的 manifest（本地缓存），解析失败返回 null
  static Map<String, dynamic>? _cachedManifest() {
    final s = AppPreferences.getString(kUpdateCachedManifestKey);
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 检查更新，force = true 表示手动检查（跳过频率限制并提示结果）
  static Future<void> checkForUpdate(BuildContext context, {bool force = false}) async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    // 每次都实时拉取 manifest（体积很小），保证服务端强更标记及时生效；
    // 「每天一次」限制只作用于普通更新的弹窗提醒（见下方），不影响强更判断
    Map<String, dynamic> data;
    try {
      final jsonUrl = Platform.isAndroid ? kUpdateJsonUrlAndroid : kUpdateJsonUrlIos;
      final res = await Dio().get<String>(jsonUrl);
      data = jsonDecode(res.data as String) as Map<String, dynamic>;
      // 缓存 manifest：断网时仍可依据它拦截强更
      AppPreferences.putString(kUpdateCachedManifestKey, res.data as String);
    } catch (e) {
      if (force) AppDialog.toast('检查更新失败: $e');
      debugPrint('[Update] 检查更新失败: $e');
      // 网络失败时回退本地缓存，仅用于强更兜底（普通更新提示不重复打扰）
      final cached = _cachedManifest();
      final cachedMin = ((cached?['minBuildNumber']) as num?)?.toInt() ?? 0;
      if (cached == null || currentBuild >= cachedMin) return;
      data = cached;
    }

    try {
      final latestVersion = data['version'] as String? ?? '';
      final latestBuild = (data['buildNumber'] as num?)?.toInt() ?? 0;
      final minBuild = (data['minBuildNumber'] as num?)?.toInt() ?? 0;
      final title = data['title'] as String? ?? '发现新版本';
      final content = data['content'] as String? ?? '';
      final androidUrl = data['androidUrl'] as String? ?? '';

      final forceUpdate = currentBuild < minBuild;

      if (latestBuild <= currentBuild && !forceUpdate) {
        if (force) AppDialog.toast('已是最新版本 $latestVersion');
        return;
      }

      // 普通更新的弹窗提醒频率：开关关（默认）= 每天最多提醒一次；强更/手动检查不受限
      if (!force && !forceUpdate) {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final alwaysCheck = AppPreferences.getBool('auto_check_update');
        if (!alwaysCheck && AppPreferences.getString(kUpdateLastCheckKey) == today) {
          debugPrint('[Update] 今天已提醒过更新，跳过');
          return;
        }
        AppPreferences.putString(kUpdateLastCheckKey, today);
      }

      // 强更弹窗无论被什么方式关闭（含被其它路由跳转顶掉）都重新弹出，直到更新完成
      while (true) {
        if (!context.mounted) break;
        await _showUpdateDialog(
          context,
          title: title,
          content: content,
          currentVersion: info.version,
          currentBuild: currentBuild,
          latestVersion: latestVersion,
          latestBuild: latestBuild,
          forceUpdate: forceUpdate,
          androidUrl: androidUrl,
        );
        if (!forceUpdate) break;
      }
    } catch (e) {
      if (force) AppDialog.toast('检查更新失败: $e');
      debugPrint('[Update] 检查更新失败: $e');
    }
  }

  static Future<void> _showUpdateDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String currentVersion,
    required int currentBuild,
    required String latestVersion,
    required int latestBuild,
    required bool forceUpdate,
    required String androidUrl,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !forceUpdate,
        child: _UpdateDialogContent(
          title: title,
          content: content,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          latestVersion: latestVersion,
          latestBuild: latestBuild,
          forceUpdate: forceUpdate,
          androidUrl: androidUrl,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Update Dialog Content (仿享脉风格，下载进度内嵌，不再开第二个弹窗)
// ---------------------------------------------------------------------------
class _UpdateDialogContent extends StatefulWidget {
  final String title;
  final String content;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final bool forceUpdate;
  final String androidUrl;

  const _UpdateDialogContent({
    required this.title,
    required this.content,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.forceUpdate,
    required this.androidUrl,
  });

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  bool _started = false;      // 是否已点过「立即更新」
  bool _downloading = false;
  bool _done = false;
  bool _hasError = false;
  double _progress = 0;
  File? _file;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (widget.androidUrl.isEmpty) {
      AppDialog.toast('下载地址为空');
      return;
    }
    File file;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) { AppDialog.toast('无法获取存储目录'); return; }
      file = File('${dir.path}/synology_cloud_update.apk');
    } catch (e) {
      AppDialog.toast('更新失败: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _started = true;
      _downloading = true;
      _done = false;
      _hasError = false;
      _progress = 0;
      _file = file;
    });
    _cancelToken = CancelToken();
    try {
      await Dio().download(
        widget.androidUrl,
        file.path,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _done = true;
        _progress = 1;
      });
      AppDialog.toast('下载完成，正在安装...');
      await _install();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      if (mounted) setState(() { _downloading = false; _hasError = true; });
    } catch (e) {
      if (mounted) setState(() { _downloading = false; _hasError = true; });
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null) return;
    await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
  }

  /// 按钮区：随下载状态切换；强更时任何状态都没有可关闭弹窗的按钮
  List<Widget> _buildActionButtons(ThemeData theme) {
    final outlinedStyle = OutlinedButton.styleFrom(
      foregroundColor: theme.colorScheme.onSurfaceVariant,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    );
    final filledStyle = FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    );

    if (_downloading) {
      // 下载中：强更无任何按钮；普通更新可停止下载（弹窗不关闭）
      if (widget.forceUpdate) return [];
      return [
        OutlinedButton(
          onPressed: () {
            _cancelToken?.cancel();
            setState(() { _started = false; _downloading = false; _progress = 0; });
          },
          style: outlinedStyle,
          child: const Text('取消下载', style: TextStyle(fontSize: 15)),
        ),
      ];
    }
    if (_hasError) {
      return [
        if (!widget.forceUpdate) ...[
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: outlinedStyle,
            child: const Text('稍后', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 12),
        ],
        FilledButton(
          onPressed: _startDownload,
          style: filledStyle,
          child: const Text('重新下载', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ];
    }
    if (_done) {
      // 下载完成：用户可能取消了系统安装页，提供重新安装入口
      return [
        FilledButton(
          onPressed: _install,
          style: filledStyle,
          child: const Text('安装', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ];
    }
    // 未开始下载
    return [
      if (!widget.forceUpdate) ...[
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: outlinedStyle,
          child: const Text('稍后', style: TextStyle(fontSize: 15)),
        ),
        const SizedBox(width: 12),
      ],
      FilledButton(
        onPressed: _startDownload,
        style: filledStyle,
        child: const Text('立即更新', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forceUpdate = widget.forceUpdate;
    final content = widget.content;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Version info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('当前版本', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('v${widget.currentVersion} (${widget.currentBuild})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward, size: 18, color: Colors.grey),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('最新版本', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('v${widget.latestVersion} (${widget.latestBuild})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (forceUpdate) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.red),
                  SizedBox(width: 6),
                  Text('当前版本过低，请立即更新', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
          if (content.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                content,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
          // 下载进度（内嵌在弹窗底部，不再单开弹窗）
          if (_started && !_hasError) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _done ? 1 : (_progress > 0 ? _progress : null),
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _done ? '下载完成' : '正在下载 ${(_progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
            ),
          ],
          if (_hasError) ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red),
                SizedBox(width: 6),
                Text('下载失败，请重试', style: TextStyle(fontSize: 13, color: Colors.red)),
              ],
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      actions: [
        // 包成单个 Column，固定「按钮行在上、更新失败链接在下」右对齐，
        // 避免 AlertDialog 的 OverflowBar 在按钮较窄时把两者挤到同一行
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildActionButtons(theme),
              ),
            ),
            // "更新失败点击这里" 放在按钮下方
            GestureDetector(
              onTap: () async {
                if (widget.androidUrl.isNotEmpty) {
                  final uri = Uri.tryParse(widget.androidUrl);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '更新失败点击这里',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


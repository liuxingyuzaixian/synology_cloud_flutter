import 'dart:async';
import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:gal/gal.dart';
import '../../components/app_video.dart';
import '../../network/video_cache.dart';
import '../../utils/media_cache.dart';
import '../../utils/fly_router.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class PreviewPhoto {
  const PreviewPhoto({
    required this.thumbnailUrl,
    required this.fullUrl,
    this.filename,
    this.headers,
    this.isVideo = false,
    this.videoUrl,
    this.videoFallbackUrl,
    this.isLivePhoto = false,
    this.photoId,
  });

  final String thumbnailUrl;
  final String fullUrl;
  final String? filename;
  final Map<String, String>? headers;
  final bool isVideo;
  final String? videoUrl;
  /// Original-file URL to play if [videoUrl] (a transcoded stream) is not
  /// available on the server yet (e.g. returns 404 while still transcoding).
  final String? videoFallbackUrl;
  final bool isLivePhoto;
  final String? photoId;

  bool get isAnimatedImage {
    if (isLivePhoto) return true;
    final name = filename?.toLowerCase() ?? '';
    if (!name.contains('.')) return false;
    final ext = name.split('.').last;
    return ext == 'gif' || ext == 'apng' || ext == 'webp';
  }
}

class ImagePreviewArgs {
  const ImagePreviewArgs({
    required this.photos,
    this.initialIndex = 0,
  });

  final List<PreviewPhoto> photos;
  final int initialIndex;
}

// ---------------------------------------------------------------------------
// AppImage helper
// ---------------------------------------------------------------------------

class AppImage {
  AppImage._();

  static Future<void> preview({
    required List<PreviewPhoto> photos,
    int initialIndex = 0,
  }) {
    // Use non-opaque route so drag-dismiss shows previous page (WeChat-style)
    final args = ImagePreviewArgs(photos: photos, initialIndex: initialIndex);
    final ctx = FlyRouter().getContext();
    if (ctx == null) {
      return FlyRouter().push<void>(
        ImagePreviewPage.routeName,
        arguments: args,
      );
    }
    return Navigator.of(ctx).push<void>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, _, __) => ImagePreviewPage(args: args),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route module
// ---------------------------------------------------------------------------

class ImagePreviewRouteModule extends FlyRouteModule {
  @override
  List<AppRoute> get routes => [
        AppRoute(
          name: ImagePreviewPage.routeName,
          builder: (_, settings) {
            final args = settings.arguments;
            return ImagePreviewPage(
              args: args is ImagePreviewArgs
                  ? args
                  : const ImagePreviewArgs(photos: []),
            );
          },
        ),
      ];
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({required this.args, super.key});

  static const routeName = '/image-preview';
  final ImagePreviewArgs args;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage>
    with SingleTickerProviderStateMixin {
  // ---- page ----
  late PageController _pageController;
  int _currentIndex = 0;

  // ---- drag-to-dismiss ----
  double _dragOffsetY = 0;
  Offset? _pointerStart;
  bool _isVerticalDismiss = false;
  bool _isHorizontalSwipe = false;
  late final AnimationController _snapBackController;
  Animation<double>? _snapBackY;

  // ---- zoom (check actual scale from PhotoViewController) ----
  final Map<int, PhotoViewController> _photoControllers = {};
  bool get _isCurrentZoomed {
    final scale = _photoControllers[_currentIndex]?.scale ?? 1.0;
    return scale > 1.01;
  }

  // ---- multi-finger ----
  int _pointerCount = 0;

  // ---- video (media_kit) ----
  Player? _player;
  VideoController? _mediaController;
  StreamSubscription<bool>? _completedSub;
  String? _recordingUrl; // url whose .part recording is still in progress
  bool _triedFallback = false; // whether we already fell back to the original
  bool _usingOriginal = false; // whether we're currently playing the original file
  bool _videoReady = false;
  bool _videoError = false;
  bool _videoRequested = false;

  // ---- download ----
  double? _downloadProgress;
  CancelToken? _downloadCancelToken;

  // ---- live photo long-press ----
  bool _livePhotoPlaying = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.args.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )
      ..addListener(() {
        if (_snapBackY != null) {
          setState(() => _dragOffsetY = _snapBackY!.value);
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _dragOffsetY = 0;
            _snapBackY = null;
          });
        }
      });
  }

  @override
  void dispose() {
    _downloadCancelToken?.cancel();
    for (final c in _photoControllers.values) {
      c.dispose();
    }
    _pageController.dispose();
    _snapBackController.dispose();
    _completedSub?.cancel();
    if (_recordingUrl != null) VideoCache.discardPart(_recordingUrl!);
    _player?.dispose();
    super.dispose();
  }

  // ---- page change ----

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _pointerCount = 0;
      _completedSub?.cancel();
      _completedSub = null;
      if (_recordingUrl != null) {
        VideoCache.discardPart(_recordingUrl!);
        _recordingUrl = null;
      }
      _player?.dispose();
      _player = null;
      _mediaController = null;
      _videoReady = false;
      _videoError = false;
      _videoRequested = false;
      _usingOriginal = false;
      _livePhotoPlaying = false;
    });
    // Auto-play video when navigating to a video page
    if (index < widget.args.photos.length) {
      final photo = widget.args.photos[index];
      if (photo.isVideo && mounted) {
        _startVideo(photo);
      }
    }
  }

  // ---- video ----

  Future<void> _startVideo(PreviewPhoto photo) async {
    if (_videoRequested) return;
    setState(() {
      _videoRequested = true;
      _videoReady = false;
      _videoError = false;
    });
    _triedFallback = false;
    _usingOriginal = false;

    // Prefer the low-bitrate transcoded stream (smoother on limited bandwidth,
    // easier to decode). If it is not available yet (still transcoding → 404),
    // fall back to the original file.
    final streamUrl = photo.videoUrl ?? photo.fullUrl;
    final canFallback =
        photo.videoFallbackUrl != null && photo.videoFallbackUrl != streamUrl;
    await _openVideo(photo, streamUrl, allowFallback: canFallback);
  }

  Future<void> _openVideo(
    PreviewPhoto photo,
    String url, {
    required bool allowFallback,
    Duration? seekTo,
  }) async {
    try {
      await _player?.dispose();

      final player = Player();
      final controller = VideoController(player);
      _player = player;
      _mediaController = controller;

      // On error: the transcoded stream may be missing (404) → retry with the
      // original file; otherwise surface the error in the UI.
      player.stream.error.listen((_) {
        if (!mounted) return;
        if (allowFallback) {
          _fallbackVideo(photo);
        } else {
          setState(() => _videoError = true);
        }
      });

      await MediaCache.configure(player);
      // No loop: mpv's stream-record cannot record a looping clip cleanly, and
      // we need a natural end-of-file to finalize the replay cache.
      await player.setPlaylistMode(PlaylistMode.none);

      // Replay fast path: if fully cached, play the local file directly
      // (instant, no network, no loading spinner). Otherwise stream and record
      // the streamed bytes to a local file for next time (zero extra
      // bandwidth), promoting it to the cache once the clip plays through.
      final cachedPath = await VideoCache.cachedPath(url);
      if (cachedPath == null) {
        await VideoCache.discardPart(url);
        final part = await VideoCache.partFile(url);
        await MediaCache.startRecording(player, part.path);
        _recordingUrl = url;
        _completedSub = player.stream.completed.listen((completed) async {
          if (completed && _recordingUrl == url) {
            _recordingUrl = null;
            await MediaCache.stopRecording(player);
            await VideoCache.finalize(url);
          }
        });
      }
      final media = cachedPath != null
          ? Media(cachedPath)
          : Media(url, httpHeaders: photo.headers);

      await player.open(media, play: true);
      if (!mounted) {
        await player.dispose();
        _player = null;
        _mediaController = null;
        return;
      }

      // Restore the playback position when switching source (stream <-> original).
      if (seekTo != null && seekTo > Duration.zero) {
        try {
          await player.seek(seekTo);
        } catch (_) {}
      }

      setState(() => _videoReady = true);
    } catch (_) {
      if (allowFallback) {
        _fallbackVideo(photo);
      } else if (mounted) {
        setState(() => _videoError = true);
      }
    }
  }

  void _fallbackVideo(PreviewPhoto photo) {
    if (_triedFallback) return; // avoid double-retry from repeated error events
    _triedFallback = true;
    _usingOriginal = true; // we're now playing the original file
    final fb = photo.videoFallbackUrl;
    if (fb == null) {
      if (mounted) setState(() => _videoError = true);
      return;
    }
    // Drop the in-progress transcoded-stream recording before retrying.
    _completedSub?.cancel();
    _completedSub = null;
    if (_recordingUrl != null) {
      VideoCache.discardPart(_recordingUrl!);
      _recordingUrl = null;
    }
    _openVideo(photo, fb, allowFallback: false);
  }

  /// Manually switch between the low-bitrate transcoded stream and the original
  /// file, keeping the current playback position. The original file is directly
  /// seekable (smooth scrubbing) and full quality; the stream is lighter on
  /// bandwidth. The user explicitly chose the source, so no auto-fallback.
  Future<void> _switchVideoQuality(PreviewPhoto photo) async {
    final streamUrl = photo.videoUrl ?? photo.fullUrl;
    final originalUrl = photo.videoFallbackUrl;
    if (originalUrl == null) return;
    final target = _usingOriginal ? streamUrl : originalUrl;
    final pos = _player?.state.position ?? Duration.zero;
    setState(() {
      _usingOriginal = !_usingOriginal;
      _videoReady = false;
      _videoError = false;
    });
    _triedFallback = true; // manual choice — don't auto-fallback
    await _openVideo(photo, target, allowFallback: false, seekTo: pos);
  }

  // ---- download with progress ----

  Future<void> _download(PreviewPhoto photo) async {
    if (_downloadProgress != null) return;
    _downloadCancelToken = CancelToken();
    setState(() => _downloadProgress = 0);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = photo.filename ?? 'download';
      final file = File('${dir.path}/$name');
      await Dio().download(
        photo.fullUrl,
        file.path,
        options: Options(headers: photo.headers),
        cancelToken: _downloadCancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );
      if (mounted) {
        // Save to device gallery
        await Gal.putImage(file.path);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('已保存到相册: $name')));
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // User cancelled — silent
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('下载失败')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('下载失败')));
      }
    }
    _downloadCancelToken = null;
    if (mounted) setState(() => _downloadProgress = null);
  }



  // ---- pointer gesture (Listener — no gesture arena conflict) ----

  void _onPointerDown(PointerDownEvent event) {
    // Ignore pointer down events that occur on the video/control area
    // (bottom ~140 px) so that control interactions (progress drag)
    // do not trigger page-swipe handling.
    final mq = MediaQuery.of(context);
    final height = mq.size.height;
    // Protect the whole lifted control cluster from the swipe/dismiss Listener,
    // otherwise a drag starting on the seek bar is stolen as a page-swipe and
    // the progress bar "won't drag". The seek bar sits at padding.bottom + 16 +
    // 56 (see AppVideo.extraBottom); add its touch height + slop on top.
    final controlsZone = mq.padding.bottom + 16 + 56 + 80;
    if (event.position.dy > height - controlsZone) return;

    _pointerCount++;
    if (_pointerCount == 1) {
      _pointerStart = event.position;
      _isVerticalDismiss = false;
      _isHorizontalSwipe = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerStart == null || _pointerCount > 1) return;
    if (_isCurrentZoomed) return;

    final dy = event.position.dy - _pointerStart!.dy;
    final dx = event.position.dx - _pointerStart!.dx;

    if (!_isVerticalDismiss && !_isHorizontalSwipe) {
      if (dy.abs() > 10 && dy.abs() > dx.abs() * 2) {
        _isVerticalDismiss = true;
      } else if (dx.abs() > 10 && dx.abs() > dy.abs() * 2) {
        _isHorizontalSwipe = true;
      }
    }

    if (_isVerticalDismiss) {
      setState(() => _dragOffsetY = dy);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerCount = (_pointerCount - 1).clamp(0, 99);
    if (_pointerCount > 0) return;

    final photos = widget.args.photos;

    if (_isVerticalDismiss) {
      if (_dragOffsetY.abs() > 200) {
        Navigator.of(context).pop();
      } else {
        _snapBackY =
            Tween<double>(begin: _dragOffsetY, end: 0).animate(
          CurvedAnimation(parent: _snapBackController, curve: Curves.easeOut),
        );
        _snapBackController.forward(from: 0);
      }
    } else if (_isHorizontalSwipe && _pointerStart != null) {
      final dx = event.position.dx - _pointerStart!.dx;
      if (dx.abs() > 50) {
        if (dx > 0 && _currentIndex > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else if (dx < 0 && _currentIndex < photos.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }

    _pointerStart = null;
    _isVerticalDismiss = false;
    _isHorizontalSwipe = false;
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final photos = widget.args.photos;
    if (photos.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final opacity = (1 - _dragOffsetY.abs() / 600).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          // PageView (swipe disabled — handled by Listener)
          Transform.translate(
            offset: Offset(0, _dragOffsetY),
            child: Transform.scale(
              scale: (1 - _dragOffsetY.abs() / 2000).clamp(0.8, 1.0),
              child: Opacity(
                opacity: opacity,
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: photos.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return photo.isVideo ? _buildVideoPage(photo) : _buildImagePage(photo, index);
                  },
                ),
              ),
            ),
          ),
          // Gesture overlay
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) {
              _pointerCount = 0;
              _isVerticalDismiss = false;
              _isHorizontalSwipe = false;
            },
            child: const SizedBox.expand(),
          ),
          // Bottom bar with page indicator + download button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Opacity(opacity: opacity, child: _buildBottomBar()),
          ),

        ],
      ),
    );
  }

  // ---- live photo long-press play ----

  Future<void> _startLivePhoto(PreviewPhoto photo) async {
    if (_livePhotoPlaying) return;
    final url = photo.videoUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _livePhotoPlaying = true);
    try {
      await _player?.dispose();
      final player = Player();
      final controller = VideoController(player);
      _player = player;
      _mediaController = controller;
      await player.setPlaylistMode(PlaylistMode.none);
      await player.open(Media(url, httpHeaders: photo.headers), play: true);
      if (!mounted) {
        await player.dispose();
        _player = null;
        _mediaController = null;
        return;
      }
      setState(() {}); // trigger rebuild to show video
    } catch (_) {
      _stopLivePhoto();
    }
  }

  void _stopLivePhoto() {
    if (!_livePhotoPlaying) return;
    _player?.dispose();
    _player = null;
    _mediaController = null;
    if (mounted) setState(() => _livePhotoPlaying = false);
  }

  // ---- image page ----

  Widget _buildImagePage(PreviewPhoto photo, int index) {
    final controller = _photoControllers.putIfAbsent(
      index,
      () => PhotoViewController(),
    );

    // Render images at screen width to avoid layout jump when high-res image loads.
    final screenWidth = MediaQuery.of(context).size.width;

    Widget buildCachedImage(PreviewPhoto photo, int index) {
      final hasThumb = (photo.thumbnailUrl.isNotEmpty);

      // Full image (fades in on top of thumbnail to avoid dark flash)
      final fullImage = CachedNetworkImage(
        imageUrl: photo.fullUrl,
        httpHeaders: photo.headers ?? {},
        width: screenWidth,
        fit: BoxFit.fitWidth,
        fadeInDuration: const Duration(milliseconds: 100),
        fadeOutDuration: Duration.zero,
        placeholderFadeInDuration: Duration.zero,
        placeholder: (context, _) => const SizedBox.shrink(),
        errorWidget: (context, _, __) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        ),
      );

      if (hasThumb) {
        // Stack: thumbnail always visible underneath, full image fades in on top
        return Center(
          child: SizedBox(
            width: screenWidth,
            child: Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: photo.thumbnailUrl,
                  httpHeaders: photo.headers ?? {},
                  fit: BoxFit.fitWidth,
                  width: screenWidth,
                ),
                fullImage,
              ],
            ),
          ),
        );
      }

      return Center(
        child: fullImage,
      );
    }

    // Use PhotoView for multi-level pinch-to-zoom + double-tap zoom
    final screenSize = MediaQuery.of(context).size;

    Widget imageWidget = PhotoView.customChild(
      controller: controller,
      child: buildCachedImage(photo, index),
      childSize: Size(screenWidth, screenSize.height),
      minScale: PhotoViewComputedScale.contained * 0.8,
      maxScale: PhotoViewComputedScale.covered * 5,
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      scaleStateCycle: null, // Use default: initial → covering → originalSize → initial
      disableGestures: false,
      enableRotation: false,
    );

    // Live Photo: show LIVE badge + long-press to play video overlay
    if (photo.isLivePhoto && photo.videoUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Long press to play live photo video
          GestureDetector(
            onLongPressStart: (_) => _startLivePhoto(photo),
            onLongPressEnd: (_) => _stopLivePhoto(),
            onLongPressCancel: () => _stopLivePhoto(),
            child: _livePhotoPlaying && _mediaController != null
                ? Video(controller: _mediaController!, fill: Colors.transparent)
                : imageWidget,
          ),
          // LIVE badge (top-left)
          if (!_livePhotoPlaying)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.motion_photos_on, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    )),
                  ],
                ),
              ),
            ),
          // Hint text
          if (!_livePhotoPlaying)
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('长按播放实况',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
            ),
        ],
      );
    }

    return imageWidget;
  }

  // ---- video page ----

  Widget _buildVideoPage(PreviewPhoto photo) {
    if (!_videoRequested) {
      // Auto-start video on first build (initial page, not from swipe)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_videoRequested) {
          _startVideo(photo);
        }
      });
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: photo.thumbnailUrl,
            httpHeaders: photo.headers ?? {},
            fit: BoxFit.contain,
          ),
          const Center(
              child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }

    if (_videoError) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text('视频加载失败',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    if (!_videoReady) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: photo.thumbnailUrl,
            httpHeaders: photo.headers ?? {},
            fit: BoxFit.contain,
          ),
          const Center(
              child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Poster thumbnail stays behind the video: AppVideo has a transparent
        // fill, so the thumbnail shows through until the first frame renders
        // (no black flash on entry).
        CachedNetworkImage(
          imageUrl: photo.thumbnailUrl,
          httpHeaders: photo.headers ?? {},
          fit: BoxFit.contain,
        ),
        AppVideo(
          controller: _mediaController!,
          // Clear the app's bottom download / page-indicator bar.
          extraBottom: 56,
        ),
      ],
    );
  }

  // ---- bottom bar (page indicator left, download right) ----

  Widget _buildBottomBar() {
    final photo = widget.args.photos[_currentIndex];
    final photos = widget.args.photos;
    final single = photos.length <= 1;
    final streamUrl = photo.videoUrl ?? photo.fullUrl;
    // Show the quality toggle only for videos that actually have a distinct
    // transcoded stream + original file to switch between.
    final canSwitchQuality = photo.isVideo &&
        photo.videoFallbackUrl != null &&
        photo.videoFallbackUrl != streamUrl;
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Page indicator
            if (!single)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  '${_currentIndex + 1} / ${photos.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            const Spacer(),
            // Quality toggle (bottom-right): switch between the smooth stream
            // and the original file (directly seekable + full quality).
            if (canSwitchQuality)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton(
                  onPressed: () => _switchVideoQuality(photo),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black26,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(_usingOriginal ? '当前:原画' : '当前:流畅'),
                ),
              ),
            // Download button (bottom-right) — shows progress while downloading
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 40,
                height: 40,
                child: _downloadProgress != null
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              value: _downloadProgress! > 0 ? _downloadProgress : null,
                              strokeWidth: 3,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          Text(
                            _downloadProgress! > 0
                                ? '${(_downloadProgress! * 100).toStringAsFixed(0)}%'
                                : '',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      )
                    : IconButton(
                        icon: const Icon(Icons.download, color: Colors.white),
                        onPressed: () => _download(photo),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black26,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../components/app_video.dart';
import '../../network/video_cache.dart';
import '../../utils/media_cache.dart';
import '../common/image_preview_page.dart';

class SlideshowPage extends StatefulWidget {
  const SlideshowPage({required this.photos, super.key});
  final List<PreviewPhoto> photos;

  @override
  State<SlideshowPage> createState() => _SlideshowPageState();
}

class _SlideshowPageState extends State<SlideshowPage> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _advanceTimer;
  bool _isPlaying = true;
  bool _showControls = true;

  Player? _player;
  VideoController? _mediaController;
  StreamSubscription<bool>? _completedSub;
  String? _recordingUrl; // url whose .part recording is still in progress
  bool _triedFallback = false; // whether we already fell back to the original
  bool _videoReady = false;
  bool _videoLoading = false;
  bool _isCurrentVideo = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    if (widget.photos.isNotEmpty && widget.photos[0].isVideo) {
      _isCurrentVideo = true;
      _playVideo(widget.photos[0]);
    } else {
      _startImageTimer();
    }
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _pageController.dispose();
    _disposeVideo();
    super.dispose();
  }

  void _startImageTimer() {
    _advanceTimer?.cancel();
    if (!_isPlaying) return;
    _advanceTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _advanceToNext();
    });
  }

  void _advanceToNext() {
    if (_currentIndex < widget.photos.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    } else {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        if (_isCurrentVideo && _player != null) _player!.play();
        else if (!_isCurrentVideo) _startImageTimer();
      } else {
        _advanceTimer?.cancel();
        _player?.pause();
      }
    });
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _disposeVideo();
      _videoReady = false;
      _videoLoading = false;
      _isCurrentVideo = false;
    });
    _advanceTimer?.cancel();
    if (index < widget.photos.length) {
      final photo = widget.photos[index];
      if (photo.isVideo) {
        _isCurrentVideo = true;
        _playVideo(photo);
      } else if (_isPlaying) _startImageTimer();
    }
  }

  void _disposeVideo() {
    _completedSub?.cancel();
    _completedSub = null;
    if (_recordingUrl != null) {
      VideoCache.discardPart(_recordingUrl!); // incomplete recording, drop it
      _recordingUrl = null;
    }
    _player?.dispose();
    _player = null;
    _mediaController = null;
  }

  Future<void> _playVideo(PreviewPhoto photo) async {
    if (_videoLoading) return;
    setState(() => _videoLoading = true);
    _triedFallback = false;

    // Prefer the low-bitrate transcoded stream; fall back to the original file
    // if it is not transcoded yet (404).
    final streamUrl = photo.videoUrl ?? photo.fullUrl;
    final canFallback =
        photo.videoFallbackUrl != null && photo.videoFallbackUrl != streamUrl;
    await _openClip(photo, streamUrl, allowFallback: canFallback);
  }

  Future<void> _openClip(
    PreviewPhoto photo,
    String url, {
    required bool allowFallback,
  }) async {
    try {
      _disposeVideo();
      final player = Player();
      final controller = VideoController(player);
      _player = player;
      _mediaController = controller;

      // On error: the transcoded stream may be missing (404) → retry with the
      // original file; otherwise don't get stuck — advance to the next item.
      player.stream.error.listen((_) {
        if (!mounted) return;
        if (allowFallback) {
          _fallbackClip(photo);
        } else if (_isPlaying) {
          _disposeVideo();
          _advanceToNext();
        }
      });

      // libmpv built-in on-disk cache + jitter-proof buffering.
      await MediaCache.configure(player);
      await player.setPlaylistMode(PlaylistMode.none);

      // Replay fast path: play the fully-cached local file if available.
      // Otherwise stream and record the streamed bytes to a local file for
      // next time (zero extra bandwidth — no parallel download to steal the
      // player's buffering bandwidth), finalized once the clip plays through.
      final cachedPath = await VideoCache.cachedPath(url);
      if (cachedPath == null) {
        await VideoCache.discardPart(url);
        final part = await VideoCache.partFile(url);
        await MediaCache.startRecording(player, part.path);
        _recordingUrl = url;
      }

      // On natural end: finalize the recording, then advance to the next item.
      _completedSub = player.stream.completed.listen((completed) async {
        if (!completed) return;
        if (_recordingUrl == url) {
          _recordingUrl = null;
          await MediaCache.stopRecording(player);
          await VideoCache.finalize(url);
        }
        if (_isPlaying && mounted) {
          _disposeVideo();
          _advanceToNext();
        }
      });

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
      if (mounted) setState(() { _videoReady = true; _videoLoading = false; });
    } catch (_) {
      if (allowFallback) {
        _fallbackClip(photo);
      } else if (mounted) {
        setState(() => _videoLoading = false);
      }
    }
  }

  void _fallbackClip(PreviewPhoto photo) {
    if (_triedFallback) return; // avoid double-retry from repeated error events
    _triedFallback = true;
    final fb = photo.videoFallbackUrl;
    if (fb == null) {
      if (mounted) setState(() => _videoLoading = false);
      return;
    }
    // _openClip() calls _disposeVideo() which drops the incomplete recording.
    _openClip(photo, fb, allowFallback: false);
  }


  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    if (photos.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _toggleControls,
            child: PageView.builder(
              controller: _pageController, onPageChanged: _onPageChanged,
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final photo = photos[index];
                return photo.isVideo ? _buildVideoPage(photo) : _buildImagePage(photo);
              },
            ),
          ),
          if (_showControls) ...[
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
                child: Row(children: [
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                  const Spacer(),
                  Text('${_currentIndex + 1} / ${photos.length}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const Spacer(),
                  IconButton(icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white), onPressed: _togglePlay),
                ]),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16, left: 16, right: 16,
              child: Row(children: List.generate(photos.length, (index) {
                return Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: index == _currentIndex ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(2))));
              })),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePage(PreviewPhoto photo) {
    final hasThumb = photo.thumbnailUrl.isNotEmpty;
    final fullImage = CachedNetworkImage(
      key: ValueKey('full_${photo.fullUrl}'), imageUrl: photo.fullUrl,
      httpHeaders: photo.headers ?? {}, fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, _) => const SizedBox.shrink(),
      errorWidget: (context, _, __) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)),
    );
    return InteractiveViewer(minScale: 0.5, maxScale: 5.0,
      child: Center(child: hasThumb ? Stack(children: [
        CachedNetworkImage(key: ValueKey('thumb_${photo.thumbnailUrl}'), imageUrl: photo.thumbnailUrl, httpHeaders: photo.headers ?? {}, fit: BoxFit.contain),
        fullImage,
      ]) : fullImage),
    );
  }

  Widget _buildVideoPage(PreviewPhoto photo) {
    if (!_videoLoading && !_videoReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_videoLoading && !_videoReady) _playVideo(photo);
      });
    }
    return Stack(fit: StackFit.expand, children: [
      CachedNetworkImage(imageUrl: photo.thumbnailUrl, httpHeaders: photo.headers ?? {}, fit: BoxFit.contain),
      if (_videoReady && _mediaController != null)
        SizedBox.expand(child: AppVideo(controller: _mediaController!, extraBottom: 24)),
    ]);
  }
}

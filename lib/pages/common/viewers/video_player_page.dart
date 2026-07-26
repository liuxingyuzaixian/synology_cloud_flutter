import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../components/app_video.dart';
import '../../../utils/media_cache.dart';
import '../../../network/dsm_api.dart';

class VideoPlayerPage extends StatefulWidget {
  final String fileName;
  final String filePath;

  const VideoPlayerPage({
    super.key,
    required this.fileName,
    required this.filePath,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  Player? _player;
  VideoController? _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startPlay();
  }

  Future<void> _startPlay() async {
    try {
      final url =
          '${DsmApi().baseUrl}/webapi/entry.cgi?api=SYNO.FileStation.Download'
          '&method=download&version=2'
          '&path=${Uri.encodeComponent(widget.filePath)}'
          '&mode=download'
          '&_sid=${DsmApi().sid}';

      final player = Player();
      final controller = VideoController(player);
      _player = player;
      _controller = controller;

      player.stream.error.listen((_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = '视频加载失败';
          });
        }
      });

      // libmpv built-in on-disk cache + jitter-proof buffering: stream
      // directly from the NAS instead of downloading the whole file first.
      await MediaCache.configure(player);
      await player.setPlaylistMode(PlaylistMode.single);

      await player.open(
        Media(url, httpHeaders: DsmApi().authHeaders),
        play: true,
      );

      if (!mounted) {
        await player.dispose();
        _player = null;
        _controller = null;
        return;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load video: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.fileName,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading || _controller == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return AppVideo(controller: _controller!);
  }
}

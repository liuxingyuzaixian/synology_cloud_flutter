import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../../../network/dsm_api.dart';

class MusicPlayerPage extends StatefulWidget {
  final String fileName;
  final String filePath;

  const MusicPlayerPage({
    super.key,
    required this.fileName,
    required this.filePath,
  });

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoading = true;
  String? _error;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final dir = await getTemporaryDirectory();
      final safeName = widget.fileName.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
      final localPath = '${dir.path}/$safeName';

      // Download if not already cached
      final file = File(localPath);
      if (!await file.exists()) {
        final dsm = DsmApi();
        final url =
            '${dsm.baseUrl}/webapi/entry.cgi?api=SYNO.FileStation.Download'
            '&method=download&version=2&path=${Uri.encodeComponent(widget.filePath)}'
            '&mode=download&_sid=${dsm.sid}';
        await Dio().download(
          url,
          localPath,
          options: Options(headers: dsm.authHeaders),
        );
      }

      await _player.setFilePath(localPath);

      _player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _duration = d);
      });
      _player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() {});
        }
      });

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  Future<void> _setSpeed(double speed) async {
    await _player.setSpeed(speed);
    if (mounted) setState(() => _speed = speed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.fileName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7B2FF7), Color(0xFF2D6BEF)],
          ),
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Downloading...', style: TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 64),
              const SizedBox(height: 16),
              Text(
                'Playback error',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Album art placeholder
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.music_note, size: 120, color: Colors.white70),
          ),
          const SizedBox(height: 32),

          // File name
          Text(
            widget.fileName,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 32),

          // Progress bar
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _duration.inMilliseconds > 0
                  ? _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble())
                  : 0,
              max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1,
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
            ),
          ),

          // Duration labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Play/Pause button
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              return IconButton(
                iconSize: 72,
                color: Colors.white,
                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                onPressed: () {
                  if (playing) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
              );
            },
          ),
          const SizedBox(height: 24),

          // Speed chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [1.0, 1.5, 2.0].map((s) {
              final selected = _speed == s;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ChoiceChip(
                  label: Text('${s}x'),
                  selected: selected,
                  onSelected: (_) => _setSpeed(s),
                  selectedColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: selected ? const Color(0xFF7B2FF7) : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

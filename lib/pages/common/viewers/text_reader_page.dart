import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../../network/dsm_api.dart';

class TextReaderPage extends StatefulWidget {
  final String fileName;
  final String filePath;

  const TextReaderPage({
    super.key,
    required this.fileName,
    required this.filePath,
  });

  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage> {
  String? _content;
  String? _error;
  bool _loading = true;
  double _fontSize = 16.0;
  static const double _minFontSize = 12.0;
  static const double _maxFontSize = 32.0;
  static const int _maxFileSize = 10 * 1024 * 1024; // 10MB

  static const _monospaceExtensions = {'json', 'xml', 'yaml', 'yml', 'ini', 'conf'};

  bool get _isMonospace {
    final ext = widget.fileName.split('.').last.toLowerCase();
    return _monospaceExtensions.contains(ext);
  }

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/${widget.fileName}';
      final dsmApi = DsmApi();
      final url =
          '${dsmApi.baseUrl}/webapi/entry.cgi?api=SYNO.FileStation.Download&method=download&version=2&path=${Uri.encodeComponent(widget.filePath)}&mode=download&_sid=${dsmApi.sid}';

      final dio = Dio();
      await dio.download(
        url,
        savePath,
        options: Options(headers: dsmApi.authHeaders),
      );

      final file = File(savePath);
      final length = await file.length();
      if (length > _maxFileSize) {
        setState(() {
          _loading = false;
          _error = 'File is too large (${(length / 1024 / 1024).toStringAsFixed(1)} MB). Maximum supported size is 10 MB.';
        });
        return;
      }

      final content = await file.readAsString();
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load file: $e';
      });
    }
  }

  void _decreaseFontSize() {
    setState(() {
      _fontSize = (_fontSize - 2).clamp(_minFontSize, _maxFontSize);
    });
  }

  void _increaseFontSize() {
    setState(() {
      _fontSize = (_fontSize + 2).clamp(_minFontSize, _maxFontSize);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: _fontSize > _minFontSize ? _decreaseFontSize : null,
            tooltip: 'Decrease font size',
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${_fontSize.toInt()}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _fontSize < _maxFontSize ? _increaseFontSize : null,
            tooltip: 'Increase font size',
          ),
        ],
      ),
      body: _buildBody(theme, isDark),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _content!,
        style: TextStyle(
          fontSize: _fontSize,
          fontFamily: _isMonospace ? 'monospace' : null,
          color: isDark ? Colors.white70 : Colors.black87,
          height: 1.5,
        ),
      ),
    );
  }
}

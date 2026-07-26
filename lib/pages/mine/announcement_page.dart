import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../network/license_api.dart';
import '../../utils/app_adaptive.dart';

/// 开发计划与公告页：展示运营后台配置的 markdown 文本。
class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  bool _loading = true;
  String? _error;
  String _content = '';
  String _updatedTime = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await LicenseApi().fetchAnnouncement();
      if (!mounted) return;
      setState(() {
        _content = (data['content'] ?? '').toString();
        _updatedTime = (data['updatedTime'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('开发计划与公告')),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildPlaceholder(
        theme,
        icon: Icons.cloud_off,
        text: '加载失败，请检查网络后重试\n$_error',
        showRetry: true,
      );
    }
    if (_content.trim().isEmpty) {
      return _buildPlaceholder(
        theme,
        icon: Icons.campaign_outlined,
        text: '暂无公告',
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        if (_updatedTime.isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 6.h),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(
              '更新于 ${_formatTime(_updatedTime)}',
              style: TextStyle(fontSize: 12.asp, color: theme.hintColor),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: MarkdownWidget(
              data: _content,
              padding: EdgeInsets.all(16.aw),
              config: isDark
                  ? MarkdownConfig.darkConfig
                  : MarkdownConfig.defaultConfig,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(
    ThemeData theme, {
    required IconData icon,
    required String text,
    bool showRetry = false,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48.aw, color: theme.hintColor),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.aw),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
            ),
          ),
          if (showRetry) ...[
            SizedBox(height: 16.h),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ],
      ),
    );
  }

  /// 后端返回 ISO 格式（2026-07-26T18:00:00），截断展示到分钟。
  String _formatTime(String raw) {
    final t = DateTime.tryParse(raw);
    if (t == null) return raw;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

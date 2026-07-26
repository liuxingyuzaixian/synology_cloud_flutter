import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../network/license_api.dart';
import '../../utils/app_adaptive.dart';
import 'feedback_submit_page.dart';

/// 我的意见反馈列表：展示历次反馈的内容、状态与管理员回复，可多次提交。
class FeedbackListPage extends StatefulWidget {
  const FeedbackListPage({super.key});

  @override
  State<FeedbackListPage> createState() => _FeedbackListPageState();
}

class _FeedbackListPageState extends State<FeedbackListPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

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
      final list = await LicenseApi().feedbackList();
      if (!mounted) return;
      setState(() {
        _items = list;
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

  Future<void> _openSubmit() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FeedbackSubmitPage()),
    );
    if (submitted == true) _load();
  }

  // ==================== 状态展示 ====================

  String _statusText(String? s) {
    switch (s) {
      case 'ACCEPTED':
        return '已采纳';
      case 'DECLINED':
        return '暂不考虑';
      default:
        return '待处理';
    }
  }

  Color _statusColor(ThemeData theme, String? s) {
    switch (s) {
      case 'ACCEPTED':
        return Colors.green;
      case 'DECLINED':
        return theme.hintColor;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('意见反馈')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSubmit,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('我要反馈'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 120.h),
          Icon(Icons.cloud_off, size: 48.aw, color: theme.hintColor),
          SizedBox(height: 12.h),
          Center(
            child: Text(
              '加载失败，下拉重试\n$_error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 120.h),
          Icon(Icons.feedback_outlined, size: 48.aw, color: theme.hintColor),
          SizedBox(height: 12.h),
          Center(
            child: Text(
              '还没有反馈记录\n点击右下角「我要反馈」提交你的建议',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.aw, 8.h, 16.aw, 88.h),
      itemCount: _items.length,
      itemBuilder: (_, index) => _buildItem(theme, _items[index]),
    );
  }

  Widget _buildItem(ThemeData theme, Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString();
    final content = (item['content'] ?? '').toString();
    final reply = (item['adminReply'] ?? '').toString();
    final createdTime = (item['createdTime'] ?? '').toString();
    final images = ((item['images'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final color = _statusColor(theme, status);

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(theme, item),
        child: Padding(
          padding: EdgeInsets.all(14.aw),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.aw, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      _statusText(status),
                      style: TextStyle(
                        fontSize: 12.asp,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    createdTime,
                    style:
                        TextStyle(fontSize: 12.asp, color: theme.hintColor),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.asp),
              ),
              if (images.isNotEmpty) ...[
                SizedBox(height: 6.h),
                Row(
                  children: [
                    Icon(Icons.image_outlined,
                        size: 14.aw, color: theme.hintColor),
                    SizedBox(width: 4.aw),
                    Text(
                      '${images.length} 张图片',
                      style:
                          TextStyle(fontSize: 12.asp, color: theme.hintColor),
                    ),
                  ],
                ),
              ],
              if (reply.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(10.aw),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '管理员回复：$reply',
                    style: TextStyle(fontSize: 13.asp),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 详情弹层 ====================

  void _showDetail(ThemeData theme, Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString();
    final content = (item['content'] ?? '').toString();
    final reply = (item['adminReply'] ?? '').toString();
    final createdTime = (item['createdTime'] ?? '').toString();
    final handledTime = (item['handledTime'] ?? '').toString();
    final images = ((item['images'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final color = _statusColor(theme, status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: EdgeInsets.all(16.aw),
          children: [
            Row(
              children: [
                Text(
                  '反馈详情',
                  style:
                      TextStyle(fontSize: 16.asp, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.aw, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    _statusText(status),
                    style: TextStyle(
                      fontSize: 12.asp,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Text(content, style: TextStyle(fontSize: 14.asp, height: 1.5)),
            if (images.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Wrap(
                spacing: 8.aw,
                runSpacing: 8.aw,
                children: [
                  for (final url in images)
                    GestureDetector(
                      onTap: () => _previewImage(url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          width: 90.aw,
                          height: 90.aw,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            width: 90.aw,
                            height: 90.aw,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          errorBuilder: (_, _, _) => Container(
                            width: 90.aw,
                            height: 90.aw,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.broken_image_outlined,
                                color: theme.hintColor),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            SizedBox(height: 16.h),
            _detailRow(theme, '提交时间', createdTime),
            if (handledTime.isNotEmpty) _detailRow(theme, '处理时间', handledTime),
            if (reply.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.aw),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '管理员回复',
                      style: TextStyle(
                          fontSize: 13.asp, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4.h),
                    Text(reply,
                        style: TextStyle(fontSize: 13.asp, height: 1.5)),
                  ],
                ),
              ),
            ],
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4.h),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontSize: 13.asp, color: theme.hintColor)),
          SizedBox(width: 12.aw),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13.asp))),
        ],
      ),
    );
  }

  void _previewImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('图片预览'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 420.h),
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Padding(
                    padding: EdgeInsets.all(24.aw),
                    child: const Text('图片加载失败'),
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

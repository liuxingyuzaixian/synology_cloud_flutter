import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _tasks = [];
  Map<String, dynamic>? _stats;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final info = await DsmApi().downloadStationInfo();
      final data = info['data'] ?? info;
      setState(() {
        _tasks = data['tasks'] ?? [];
        _stats = data['stats'];
        _loading = false;
      });
    } catch (e) {
      if (!silent) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'downloading': return Icons.download;
      case 'paused': return Icons.pause_circle;
      case 'finished': return Icons.check_circle;
      case 'error': case 'error_content': return Icons.error;
      default: return Icons.downloading;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'downloading': return Colors.blue;
      case 'paused': return Colors.orange;
      case 'finished': return Colors.green;
      case 'error': case 'error_content': return Colors.red;
      default: return Colors.grey;
    }
  }

  double _progress(Map task) {
    final size = (task['size'] ?? 0) as num;
    final downloaded = (task['downloaded_size'] ?? 0) as num;
    if (size <= 0) return 0;
    return (downloaded / size).clamp(0, 1).toDouble();
  }

  String _speed(Map task) {
    final speed = (task['additional']?['transfer']?['speed_download'] ?? 0) as num;
    if (speed <= 0) return '--';
    return '${DsmApi.formatSize(speed)}/s';
  }

  Future<void> _taskAction(String id, String action) async {
    try {
      await DsmApi().downloadTaskAction([id], action);
      AppDialog.toast('$action 成功');
      _refresh(silent: true);
    } catch (e) {
      AppDialog.toast('操作失败: $e');
    }
  }

  void _showAddDialog() {
    final ctrl = TextEditingController();
    String type = 'url';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('添加下载任务'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'url', label: Text('URL'), icon: Icon(Icons.link)),
              ButtonSegment(value: 'file', label: Text('种子文件'), icon: Icon(Icons.file_present)),
            ],
            selected: {type},
            onSelectionChanged: (s) => setS(() => type = s.first),
          ),
          10.hGap,
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: type == 'url' ? '下载链接' : '文件路径',
              border: const OutlineInputBorder(),
            ),
            maxLines: type == 'url' ? 3 : 1,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            Navigator.pop(ctx);
            final close = AppDialog.showLoading();
            try {
              final params = <String, dynamic>{'destination': ''};
              if (type == 'url') params['url'] = ctrl.text.trim();
              else params['file_path'] = ctrl.text.trim();
              await DsmApi().downloadTaskCreate('', type, url: ctrl.text.trim(), filePath: type == 'file' ? ctrl.text.trim() : null);
              AppDialog.toast('任务已添加');
              _refresh(silent: true);
            } catch (e) {
              AppDialog.toast('添加失败: $e');
            }
            close();
          }, child: const Text('添加')),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载任务'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
      ]),
      floatingActionButton: FloatingActionButton(
        heroTag: 'download_fab',
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48.r, color: Colors.red),
                  10.hGap,
                  Text(_error!, style: TextStyle(fontSize: 14.sp)),
                  10.hGap,
                  FilledButton(onPressed: _refresh, child: const Text('重试')),
                ]))
              : _tasks.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_download_outlined, size: 64.r, color: Colors.grey),
                      10.hGap,
                      Text('暂无下载任务', style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: () => _refresh(),
                      child: ListView.builder(
                        padding: EdgeInsets.all(12.r),
                        itemCount: _tasks.length,
                        itemBuilder: (ctx, i) {
                          final t = Map<String, dynamic>.from(_tasks[i]);
                          final status = t['status'] ?? '';
                          final title = t['title'] ?? t['id'] ?? '未知任务';
                          return Card(
                            margin: EdgeInsets.only(bottom: 8.h),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12.r),
                              onLongPress: () => _showTaskActions(t),
                              child: Padding(
                                padding: EdgeInsets.all(12.r),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Icon(_statusIcon(status), color: _statusColor(status), size: 20.r),
                                      8.wGap,
                                      Expanded(child: Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                    ]),
                                    8.hGap,
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4.r),
                                      child: LinearProgressIndicator(
                                        value: _progress(t),
                                        minHeight: 6.h,
                                      ),
                                    ),
                                    4.hGap,
                                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                      Text('${(_progress(t) * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                                      Text(_speed(t), style: TextStyle(fontSize: 12.sp, color: Colors.blue)),
                                      Text(status, style: TextStyle(fontSize: 12.sp, color: _statusColor(status))),
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  void _showTaskActions(Map task) {
    final id = task['id'] ?? '';
    final status = task['status'] ?? '';
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (status == 'downloading') ListTile(
          leading: const Icon(Icons.pause), title: const Text('暂停'),
          onTap: () { Navigator.pop(ctx); _taskAction(id, 'pause'); },
        ),
        if (status == 'paused') ListTile(
          leading: const Icon(Icons.play_arrow), title: const Text('继续'),
          onTap: () { Navigator.pop(ctx); _taskAction(id, 'resume'); },
        ),
        ListTile(
          leading: const Icon(Icons.delete, color: Colors.red), title: const Text('删除', style: TextStyle(color: Colors.red)),
          onTap: () { Navigator.pop(ctx); _taskAction(id, 'delete'); },
        ),
      ]),
    ));
  }
}

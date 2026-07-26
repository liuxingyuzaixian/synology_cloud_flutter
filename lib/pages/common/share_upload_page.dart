import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/fly_router.dart';

class ShareUploadFile {
  const ShareUploadFile({required this.path, required this.name});

  final String path;
  final String name;
}

List<ShareUploadFile> normalizeShareUploadFiles(List<dynamic> rawFiles) {
  final items = <ShareUploadFile>[];
  for (final raw in rawFiles) {
    if (raw is! Map) continue;

    final path = raw['path']?.toString().trim() ?? '';
    if (path.isEmpty) continue;

    final name = raw['name']?.toString().trim() ?? '';
    final fallback = path.split(Platform.pathSeparator).where((e) => e.isNotEmpty).last;
    items.add(ShareUploadFile(path: path, name: name.isEmpty ? fallback : name));
  }
  return items;
}

class ShareUploadRouteModule extends FlyRouteModule {
  @override
  List<AppRoute> get routes => [
        AppRoute(
          name: ShareUploadPage.routeName,
          builder: (_, settings) {
            final args = settings.arguments;
            if (args is List<ShareUploadFile>) {
              return ShareUploadPage(files: args);
            }
            if (args is List) {
              return ShareUploadPage(files: normalizeShareUploadFiles(args));
            }
            return const ShareUploadPage(files: []);
          },
        ),
      ];
}

class ShareUploadPage extends StatefulWidget {
  const ShareUploadPage({required this.files, super.key});

  static const routeName = '/share-upload';
  final List<ShareUploadFile> files;

  @override
  State<ShareUploadPage> createState() => _ShareUploadPageState();
}

class _ShareUploadPageState extends State<ShareUploadPage> {
  String _uploadPath = '/';
  bool _uploading = false;
  final List<_UploadJob> _jobs = [];

  @override
  void initState() {
    super.initState();
    _jobs.addAll(
      widget.files.map((file) => _UploadJob(file: file, status: '等待上传')),
    );
  }

  Future<void> _pickTargetFolder() async {
    final res = await DsmApi().shareList();
    final shares = (res['data']?['shares'] as List?) ?? [];
    if (shares.isEmpty) {
      AppDialog.toast('当前没有可用共享文件夹');
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('选择上传目录'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shares.length,
            itemBuilder: (_, index) {
              final share = shares[index] as Map<String, dynamic>;
              final path = (share['path'] ?? '').toString();
              final name = (share['name'] ?? '共享文件夹').toString();
              return ListTile(
                title: Text(name),
                subtitle: Text(path),
                onTap: () => Navigator.pop(context, path),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ],
      ),
    );

    if (!mounted) return;
    if (selected != null && selected.isNotEmpty) {
      setState(() => _uploadPath = selected);
    }
  }

  Future<void> _startUpload() async {
    if (_uploading) return;
    if (_uploadPath.isEmpty) {
      await _pickTargetFolder();
      if (_uploadPath.isEmpty) return;
    }

    setState(() => _uploading = true);
    var successCount = 0;
    var failureCount = 0;

    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (!mounted) break;
      setState(() {
        job.status = '上传中';
        job.progress = 0;
      });

      try {
        final token = CancelToken();
        await DsmApi().uploadFile(
          _uploadPath,
          job.file.path,
          token,
          (sent, total) {
            if (!mounted || total <= 0) return;
            setState(() {
              job.progress = ((sent / total) * 100).round();
            });
          },
        );
        if (!mounted) break;
        setState(() {
          job.status = '已上传';
          job.progress = 100;
        });
        successCount++;
      } catch (e) {
        if (!mounted) break;
        setState(() {
          job.status = '失败';
          job.progress = 0;
        });
        failureCount++;
      }
    }

    if (!mounted) return;
    setState(() => _uploading = false);
    if (failureCount == 0) {
      AppDialog.toast('已上传 $successCount 个文件');
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else {
      AppDialog.toast('上传完成：$successCount 成功，$failureCount 失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分享后上传'),
        actions: [
          IconButton(
            onPressed: _uploading ? null : _pickTargetFolder,
            icon: const Icon(Icons.folder_open),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将分享的文件上传到群晖文件站',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('目标目录：$_uploadPath'),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _jobs.length,
                  itemBuilder: (_, index) {
                    final job = _jobs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(job.file.name),
                        subtitle: Text(job.status),
                        trailing: job.progress > 0 && job.progress < 100
                            ? SizedBox(
                                width: 56,
                                child: Text('${job.progress}%'),
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _uploading ? null : _startUpload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(_uploading ? '上传中...' : '开始上传'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadJob {
  _UploadJob({required this.file, required this.status});

  final ShareUploadFile file;
  String status;
  int progress = 0;
}

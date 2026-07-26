import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/app_preferences.dart';
import 'backup_service.dart';

/// 相册备份页面 — 使用 photo_manager 直接访问系统相册
class AlbumBackupPage extends StatefulWidget {
  const AlbumBackupPage({super.key});

  @override
  State<AlbumBackupPage> createState() => _AlbumBackupPageState();
}

class _AlbumBackupPageState extends State<AlbumBackupPage> {
  List<AssetPathEntity> _albums = [];
  Set<String> _selectedAlbumIds = {};
  String _backupFolder = '';
  DateTime? _lastBackupTime;
  bool _continueBackup = true;
  bool _loading = true;
  bool _backingUp = false;

  // 上传状态
  int _currentIdx = 0;
  int _totalToBackup = 0;
  String _currentFileName = '';
  double _currentProgress = 0;
  int _successCount = 0;
  int _skipCount = 0;
  int _failCount = 0;
  bool _cancelRequested = false;

  // settings keys
  static const _kSelectedAlbums = 'backup_selected_albums';
  static const _kBackupFolder = 'backup_folder';
  static const _kLastBackupTime = 'last_backup_time';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _backupFolder = AppPreferences.getString(_kBackupFolder);
    final lastStr = AppPreferences.getString(_kLastBackupTime);
    if (lastStr.isNotEmpty) {
      _lastBackupTime = DateTime.fromMillisecondsSinceEpoch(int.parse(lastStr));
    }
    final selectedStr = AppPreferences.getString(_kSelectedAlbums);
    if (selectedStr.isNotEmpty) {
      try {
        _selectedAlbumIds = Set<String>.from(jsonDecode(selectedStr) as List);
      } catch (_) {}
    }

    // 请求权限并加载相册
    final ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth) {
      _albums = await PhotoManager.getAssetPathList(type: RequestType.common);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _selectTargetFolder() async {
    // 使用 DSM API 获取文件夹列表让用户选择
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _FolderPickerPage()),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _backupFolder = result);
      AppPreferences.putString(_kBackupFolder, result);
    }
  }

  void _toggleAlbum(String id) {
    setState(() {
      if (_selectedAlbumIds.contains(id)) {
        _selectedAlbumIds.remove(id);
      } else {
        _selectedAlbumIds.add(id);
      }
      AppPreferences.putString(_kSelectedAlbums, jsonEncode(_selectedAlbumIds.toList()));
    });
  }

  Future<void> _startBackup() async {
    if (_backupFolder.isEmpty) {
      AppDialog.toast('请选择备份目的地');
      return;
    }
    if (_selectedAlbumIds.isEmpty) {
      AppDialog.toast('请选择备份源');
      return;
    }

    setState(() => _backingUp = true);
    _cancelRequested = false;
    _successCount = 0;
    _skipCount = 0;
    _failCount = 0;
    _currentIdx = 0;
    _currentProgress = 0;

    // 收集待备份的文件
    final tasks = <AssetEntity>[];
    for (final albumId in _selectedAlbumIds) {
      final album = _albums.where((a) => a.id == albumId).firstOrNull;
      if (album == null) continue;
      final assets = await album.getAssetListRange(start: 0, end: 100000);
      for (final asset in assets) {
        if (_continueBackup && _lastBackupTime != null) {
          if (asset.modifiedDateTime.isBefore(_lastBackupTime!)) continue;
        }
        tasks.add(asset);
      }
    }

    // 按修改时间排序
    tasks.sort((a, b) => a.modifiedDateTime.compareTo(b.modifiedDateTime));
    _totalToBackup = tasks.length;

    if (tasks.isEmpty) {
      AppDialog.toast('没有需要备份的新文件');
      setState(() => _backingUp = false);
      return;
    }

    // 开始上传
    for (int i = 0; i < tasks.length; i++) {
      if (_cancelRequested) {
        AppDialog.toast('备份已暂停');
        break;
      }
      if (!mounted) break;

      _currentIdx = i;
      _currentProgress = 0;

      final asset = tasks[i];
      final file = await asset.originFile;
      if (file == null || !await file.exists()) {
        _failCount++;
        continue;
      }

      _currentFileName = file.path.split('/').last;
      if (mounted) setState(() {});

      final mtime = asset.modifiedDateTime.millisecondsSinceEpoch ~/ 1000;
      final fileName = _currentFileName;
      final targetFolder = [_backupFolder];

      try {
        final hash = await PhotoBackupService.fileHash(file.path);
        if (hash.isNotEmpty && PhotoBackupService.backedUpHashes.contains(hash)) {
          _skipCount++;
          continue;
        }

        // 检查服务器是否已有
        final checkRes = await DsmApi().fotoBackupCheck([
          {
            'hash_code': hash,
            'name': [fileName, fileName],
            'takentime': mtime,
          }
        ]);
        if (checkRes['success'] == true) {
          final list = checkRes['data']?['list'] as List? ?? [];
          if (list.isNotEmpty && list[0]['new'] == false) {
            PhotoBackupService.markBackedUp(hash);
            _skipCount++;
            continue;
          }
        }

        // 上传
        final status = await PhotoBackupService.backupFile(
          filePath: file.path,
          fileName: fileName,
          mtime: mtime,
          targetFolderPath: targetFolder,
          subfolder: PhotoBackupService.defaultSubfolder(mtime),
          onProgress: (p) {
            if (mounted) {
              setState(() => _currentProgress = p);
            }
          },
        );

        if (status == BackupStatus.done) {
          _successCount++;
          // iOS 上删除临时文件（originFile 是临时副本）
          if (Platform.isIOS) {
            try { await file.delete(); } catch (_) {}
          }
        } else if (status == BackupStatus.skipped) {
          _skipCount++;
        } else {
          _failCount++;
        }
      } catch (e) {
        _failCount++;
      }

      if (mounted) setState(() {});
    }

    // 更新备份时间
    if (!_cancelRequested && _failCount == 0) {
      _lastBackupTime = DateTime.now();
      AppPreferences.putString(_kLastBackupTime, _lastBackupTime!.millisecondsSinceEpoch.toString());
    }

    if (mounted) {
      setState(() => _backingUp = false);
      AppDialog.toast('备份完成: 成功$_successCount 跳过$_skipCount 失败$_failCount');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('相册备份')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _backingUp
              ? _buildBackupProgress()
              : _buildBackupSettings(theme),
    );
  }

  Widget _buildBackupSettings(ThemeData theme) {
    return ListView(
      padding: EdgeInsets.all(16.r),
      children: [
        // 备份目的地
        Card(
          child: ListTile(
            leading: Icon(Icons.cloud_upload, color: theme.colorScheme.primary),
            title: Text('备份目的地', style: TextStyle(fontSize: 14.sp)),
            subtitle: Text(
              _backupFolder.isEmpty ? '请选择目的地' : _backupFolder,
              style: TextStyle(fontSize: 13.sp, color: Colors.grey),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _selectTargetFolder,
          ),
        ),
        SizedBox(height: 12.h),

        // 备份源
        Text('备份源', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 8.h),
        if (_albums.isEmpty)
          Card(child: ListTile(
            leading: Icon(Icons.photo_album, color: Colors.grey),
            title: Text('未获取到相册', style: TextStyle(fontSize: 14.sp)),
            subtitle: Text('请检查相册权限', style: TextStyle(fontSize: 12.sp)),
          ))
        else
          ..._albums.map((album) => _buildAlbumItem(album)),

        SizedBox(height: 12.h),

        // 备份模式
        Card(
          child: Column(
            children: [
              RadioListTile<bool>(
                value: true,
                groupValue: _continueBackup,
                title: Text('继续备份', style: TextStyle(fontSize: 14.sp)),
                subtitle: Text(
                  _lastBackupTime != null
                      ? '上次备份: ${_formatDate(_lastBackupTime!)}'
                      : '从未备份过',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                ),
                onChanged: (v) => setState(() => _continueBackup = v ?? true),
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: _continueBackup,
                title: Text('全新备份', style: TextStyle(fontSize: 14.sp)),
                subtitle: Text('备份所有选中的照片', style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                onChanged: (v) => setState(() => _continueBackup = v ?? false),
              ),
            ],
          ),
        ),

        SizedBox(height: 20.h),

        // 开始备份按钮
        FilledButton.icon(
          onPressed: _startBackup,
          icon: const Icon(Icons.backup),
          label: Text('开始备份', style: TextStyle(fontSize: 16.sp)),
          style: FilledButton.styleFrom(
            minimumSize: Size(double.infinity, 48.h),
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumItem(AssetPathEntity album) {
    final selected = _selectedAlbumIds.contains(album.id);
    return Card(
      child: CheckboxListTile(
        value: selected,
        onChanged: (_) => _toggleAlbum(album.id),
        title: Text(album.name, style: TextStyle(fontSize: 14.sp)),
        subtitle: FutureBuilder<int>(
          future: album.assetCountAsync,
          builder: (_, snap) => Text(
            '${snap.data ?? 0} 项',
            style: TextStyle(fontSize: 12.sp, color: Colors.grey),
          ),
        ),
        secondary: Icon(selected ? Icons.check_circle : Icons.photo_album_outlined,
            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey),
      ),
    );
  }

  Widget _buildBackupProgress() {
    final completed = _successCount + _skipCount + _failCount;
    final progress = _totalToBackup > 0 ? completed / _totalToBackup : 0.0;
    return Padding(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('正在备份...', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 16.h),
          LinearProgressIndicator(value: progress, minHeight: 8.h),
          SizedBox(height: 8.h),
          Text(
            '$completed / $_totalToBackup  成功$_successCount  跳过$_skipCount  失败$_failCount',
            style: TextStyle(fontSize: 13.sp, color: Colors.grey),
          ),
          SizedBox(height: 16.h),
          if (_currentFileName.isNotEmpty) ...[
            Text('当前文件: $_currentFileName', style: TextStyle(fontSize: 13.sp), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: 4.h),
            LinearProgressIndicator(value: _currentProgress > 0 ? _currentProgress : null, minHeight: 4.h),
          ],
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _cancelRequested = true);
              },
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('暂停备份'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 文件夹选择页面
class _FolderPickerPage extends StatefulWidget {
  const _FolderPickerPage();

  @override
  State<_FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<_FolderPickerPage> {
  String _currentPath = '/';
  List<dynamic> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders('/');
  }

  Future<void> _loadFolders(String path) async {
    setState(() { _loading = true; _currentPath = path; });
    try {
      final res = await DsmApi().fileList(path);
      final items = res['data']?['files'] ?? [];
      final folders = items.where((f) => f['isdir'] == true || f['type'] == 'dir').toList();
      setState(() { _folders = folders; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('选择文件夹', style: TextStyle(fontSize: 16.sp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _currentPath),
            child: const Text('选择此处'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 面包屑
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                GestureDetector(
                  onTap: () => _loadFolders('/'),
                  child: Text('根目录', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13.sp)),
                ),
                ...parts.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final path = '/${parts.sublist(0, idx + 1).join('/')}';
                  return Row(children: [
                    Icon(Icons.chevron_right, size: 16.r, color: Colors.grey),
                    GestureDetector(
                      onTap: () => _loadFolders(path),
                      child: Text(entry.value, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13.sp)),
                    ),
                  ]);
                }),
              ]),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _folders.isEmpty
                    ? Center(child: Text('暂无子文件夹', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _folders.length,
                        itemBuilder: (_, i) {
                          final f = _folders[i];
                          final name = f['name'] ?? f['path'] ?? '';
                          final path = _currentPath == '/' ? '/$name' : '$_currentPath/$name';
                          return ListTile(
                            leading: Icon(Icons.folder, color: Colors.amber, size: 28.r),
                            title: Text(name, style: TextStyle(fontSize: 14.sp)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _loadFolders(path),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

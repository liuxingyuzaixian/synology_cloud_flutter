import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

/// 文件收藏夹页面
/// 展示已收藏的文件/文件夹列表，支持打开、重命名、取消收藏
class FavoritesPage extends StatefulWidget {
  final void Function(String path)? onPathSelected;
  const FavoritesPage({super.key, this.onPathSelected});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _loading = true;
  List<dynamic> _favorites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DsmApi().favoriteList();
      if (mounted) {
        setState(() {
          _favorites = res['data']?['favorites'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteFavorite(String path, String name) async {
    final confirm = await AppDialog.confirm(
      title: '取消收藏',
      message: '确定取消收藏「$name」吗？',
    );
    if (confirm != true) return;

    final close = AppDialog.showLoading(label: '正在删除...');
    try {
      final res = await DsmApi().favoriteDelete(path);
      if (res['success'] == true || res['data'] != null) {
        AppDialog.toast('已取消收藏');
        _load();
      } else {
        AppDialog.toast('操作失败');
      }
    } catch (e) {
      AppDialog.toast('操作失败');
    }
    close();
  }

  Future<void> _renameFavorite(String path, String currentName) async {
    final newName = await AppDialog.input(
      title: '重命名收藏',
      label: '名称',
      initialValue: currentName,
    );
    if (newName == null || newName.trim().isEmpty || newName == currentName) return;

    final close = AppDialog.showLoading(label: '正在保存...');
    try {
      final res = await DsmApi().favoriteRename(path, newName.trim());
      if (res['success'] == true || res['data'] != null) {
        AppDialog.toast('重命名成功');
        _load();
      } else {
        AppDialog.toast('重命名失败');
      }
    } catch (e) {
      AppDialog.toast('重命名失败');
    }
    close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏夹')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border, size: 64.r, color: Colors.grey),
                      SizedBox(height: 12.h),
                      Text('暂无收藏', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: EdgeInsets.all(12.r),
                    itemCount: _favorites.length,
                    itemBuilder: (ctx, i) {
                      final f = Map<String, dynamic>.from(_favorites[i]);
                      final name = f['name']?.toString() ?? '未知';
                      final path = f['path']?.toString() ?? '';
                      final status = f['status']?.toString() ?? 'valid';
                      final isBroken = status == 'broken';
                      return Card(
                        margin: EdgeInsets.only(bottom: 8.h),
                        child: ListTile(
                          leading: Icon(
                            isBroken ? Icons.broken_image_outlined : Icons.folder,
                            color: isBroken ? Colors.red : Colors.amber,
                            size: 32.r,
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                              color: isBroken ? Colors.grey : null,
                            ),
                          ),
                          subtitle: Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, size: 20.r),
                            onSelected: (v) {
                              if (v == 'rename') {
                                _renameFavorite(path, name);
                              } else if (v == 'delete') {
                                _deleteFavorite(path, name);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'rename', child: ListTile(
                                leading: Icon(Icons.edit, size: 20),
                                title: Text('重命名'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              )),
                              const PopupMenuItem(value: 'delete', child: ListTile(
                                leading: Icon(Icons.delete_outline, size: 20),
                                title: Text('取消收藏'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              )),
                            ],
                          ),
                          onTap: () {
                            if (isBroken) {
                              AppDialog.toast('文件或目录不存在');
                              return;
                            }
                            widget.onPathSelected?.call(path);
                            Navigator.of(context).pop();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

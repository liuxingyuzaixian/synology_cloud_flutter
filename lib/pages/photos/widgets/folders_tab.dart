import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../components/CustomScrollBar.dart';
import '../../../network/dsm_api.dart';
import '../../../utils/app_adaptive.dart';
import '../../common/image_preview_page.dart';
import '../models/foto_folder.dart';
import '../models/foto_photo.dart';
import 'photo_grid_item.dart';

class FoldersTab extends StatefulWidget {
  const FoldersTab({super.key, this.isSharedSpace = false});

  final bool isSharedSpace;

  @override
  State<FoldersTab> createState() => FoldersTabState();
}

class FoldersTabState extends State<FoldersTab> {
  final List<_FolderEntry> _stack = [];
  bool _loading = true;
  String? _error;

  List<PreviewPhoto>? get previewPhotos => null;

  List<PreviewPhoto> _toPreviewList(List<FotoPhoto> photos) {
    return photos.map((p) => PreviewPhoto(
      thumbnailUrl: p.thumbnailUrl(size: 1, useTeamApi: widget.isSharedSpace),
      fullUrl: p.thumbnailUrl(size: 3, useTeamApi: widget.isSharedSpace),
      filename: p.filename,
      headers: DsmApi().authHeaders,
      isVideo: p.isVideo,
      videoUrl: p.isVideo ? p.videoStreamUrl : p.livePhotoVideoUrl,
      videoFallbackUrl: p.isVideo ? p.downloadUrl : null,
      isLivePhoto: p.isLivePhoto,
    )).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    setState(() {
      _loading = true;
      _error = null;
      _stack.clear();
    });
    try {
      final res = widget.isSharedSpace
          ? await DsmApi().fotoTeamFolders(folder: '/')
          : await DsmApi().fotoFolders(folder: '/');
      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        final folders = list.map((e) => FotoFolder.fromJson(e)).toList();
        _stack.add(_FolderEntry(
          name: '全部',
          folders: folders,
          photos: [],
        ));
      } else {
        _error = '加载失败';
      }
    } catch (e) {
      _error = '网络错误: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openFolder(FotoFolder folder) async {
    setState(() => _loading = true);
    try {
      // Fetch sub-folders
      final folderRes = widget.isSharedSpace
          ? await DsmApi().fotoTeamFolders(folder: '/${folder.id}')
          : await DsmApi().fotoFolders(folder: '/${folder.id}');
      List<FotoFolder> subFolders = [];
      if (folderRes['success'] == true) {
        final list = (folderRes['data']?['list'] as List?) ?? [];
        subFolders = list.map((e) => FotoFolder.fromJson(e)).toList();
      }

      // Fetch photos in folder using timeline with folder_id
      List<FotoPhoto> photos = [];
      try {
        // Use SYNO.Foto.Browse.Item with folder_id
        final photoRes = await DsmApi().fotoTeamBrowseItem(
          folderId: folder.id,
          limit: 500,
        );
        if (photoRes['success'] == true) {
          final list = (photoRes['data']?['list'] as List?) ?? [];
          photos = list.map((e) => FotoPhoto.fromJson(e)).toList();
        }
      } catch (_) {}

      _stack.add(_FolderEntry(
        name: folder.displayName,
        folders: subFolders,
        photos: photos,
      ));
    } catch (e) {
      _error = '加载失败: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _goBack(int index) {
    setState(() {
      _stack.removeRange(index + 1, _stack.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _stack.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _stack.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(fontSize: 14.asp)),
            SizedBox(height: 12.h),
            FilledButton.tonal(
              onPressed: _loadRoot,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_stack.isEmpty) {
      return Center(
        child: Text('暂无文件夹', style: TextStyle(fontSize: 14.asp, color: Colors.grey)),
      );
    }

    final current = _stack.last;
    return Column(
      children: [
        // Breadcrumb path
        if (_stack.length > 1)
          Container(
            height: 36.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _stack.length,
              separatorBuilder: (_, __) => Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: Icon(Icons.chevron_right, size: 18.r, color: Colors.grey),
              ),
              itemBuilder: (context, index) {
                final isLast = index == _stack.length - 1;
                return GestureDetector(
                  onTap: isLast ? null : () => _goBack(index),
                  child: Center(
                    child: Text(
                      _stack[index].name,
                      style: TextStyle(
                        fontSize: 13.asp,
                        fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                        color: isLast ? Colors.black87 : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        // Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _stack.length == 1 ? _loadRoot : () async {},
                  child: CustomScrollBar(
                    child: ListView(
                      padding: EdgeInsets.all(12.r),
                      children: [
                        if (current.folders.isNotEmpty) ...[
                          Text(
                            '文件夹',
                            style: TextStyle(fontSize: 14.asp, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 8.h),
                          Wrap(
                            spacing: 12.w,
                            runSpacing: 12.h,
                            children: current.folders.map((folder) {
                              return _FolderCard(
                                folder: folder,
                                onTap: () => _openFolder(folder),
                              );
                            }).toList(),
                          ),
                          SizedBox(height: 16.h),
                        ],
                        if (current.photos.isNotEmpty) ...[
                          Text(
                            '照片',
                            style: TextStyle(fontSize: 14.asp, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 8.h),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 4.r,
                              mainAxisSpacing: 4.r,
                              childAspectRatio: 1,
                            ),
                            itemCount: current.photos.length,
                            itemBuilder: (context, index) {
                              final photo = current.photos[index];
                              return PhotoGridItem(
                                url: photo.thumbnailUrl(size: 1, useTeamApi: widget.isSharedSpace),
                                isVideo: photo.isVideo,
                                isLivePhoto: photo.isLivePhoto,
                                onTap: () => AppImage.preview(photos: _toPreviewList(current.photos), initialIndex: index),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _FolderEntry {
  final String name;
  final List<FotoFolder> folders;
  final List<FotoPhoto> photos;

  _FolderEntry({
    required this.name,
    required this.folders,
    required this.photos,
  });
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.folder, required this.onTap});

  final FotoFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Build thumbnail URL for folder cover
    String? thumbUrl;
    if (folder.thumbnailUnitIds.isNotEmpty) {
      final unitId = folder.thumbnailUnitIds.first;
      final cacheKey = folder.thumbnailCacheKeys.isNotEmpty
          ? folder.thumbnailCacheKeys.first
          : '';
      thumbUrl = DsmApi().fotoThumbnailUrl(unitId, size: 1, cacheKey: cacheKey);
    }

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: (MediaQuery.of(context).size.width - 48.w) / 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: thumbUrl != null
                    ? CachedNetworkImage(
                        imageUrl: thumbUrl,
                        httpHeaders: {'Cookie': DsmApi().cookie},
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (context, _) => Container(color: const Color(0xFFEEEEEE)),
                        errorWidget: (context, _, __) => Container(
                          color: const Color(0xFFEEEEEE),
                          child: Center(
                            child: Icon(Icons.folder_outlined, color: Colors.grey[400], size: 32.r),
                          ),
                        ),
                      )
                    : Container(
                        color: const Color(0xFFEEEEEE),
                        child: Center(
                          child: Icon(Icons.folder_outlined, color: Colors.grey[400], size: 32.r),
                        ),
                      ),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              folder.displayName,
              style: TextStyle(fontSize: 13.asp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

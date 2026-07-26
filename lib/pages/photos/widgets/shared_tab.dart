import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:convert';

import '../../../components/CustomScrollBar.dart';
import '../../../network/dsm_api.dart';
import '../../../utils/app_adaptive.dart';
import '../../../utils/app_preferences.dart';
import '../../common/image_preview_page.dart';
import '../models/foto_album.dart';
import '../models/foto_photo.dart';
import 'photo_grid_item.dart';

class SharedTab extends StatefulWidget {
  const SharedTab({super.key, this.isSharedSpace = false});

  final bool isSharedSpace;

  @override
  State<SharedTab> createState() => SharedTabState();
}

class SharedTabState extends State<SharedTab> {
  final List<FotoAlbum> _albums = [];
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
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    _error = null;
    // 1. Show cached data immediately if available
    final cached = AppPreferences.getString('cache_photos_shared');
    if (cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached) as List;
        _albums.clear();
        _albums.addAll(list.map((e) => FotoAlbum.fromJson(e)));
        _loading = false;
        if (mounted) setState(() {});
      } catch (_) {}
    }
    // 2. Fetch fresh data from API
    if (_loading) {
      setState(() { _loading = true; });
    }
    try {
      final res = widget.isSharedSpace
          ? await DsmApi().fotoTeamSharedAlbums(offset: 0, limit: 100)
          : await DsmApi().fotoSharedAlbums(offset: 0, limit: 100);
      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        _albums.clear();
        _albums.addAll(list.map((e) => FotoAlbum.fromJson(e)));
        // Save to cache
        AppPreferences.putString('cache_photos_shared', jsonEncode(list));
      } else {
        _error = '加载失败';
      }
    } catch (e) {
      _error = '网络错误: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(fontSize: 14.asp)),
            SizedBox(height: 12.h),
            FilledButton.tonal(
              onPressed: _loadAlbums,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_albums.isEmpty) {
      return Center(
        child: Text('暂无共享相册', style: TextStyle(fontSize: 14.asp, color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAlbums,
      child: CustomScrollBar(
        child: ListView.builder(
          padding: EdgeInsets.all(12.r),
        itemCount: _albums.length,
        itemBuilder: (context, index) {
          final album = _albums[index];
          return _SharedAlbumCard(
            album: album,
            onTap: () => _openAlbum(album),
            isSharedSpace: widget.isSharedSpace,
          );
        },
      ),
      ),
    );
  }

  void _openAlbum(FotoAlbum album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SharedAlbumDetailPage(album: album, isSharedSpace: widget.isSharedSpace),
      ),
    );
  }
}

class _SharedAlbumCard extends StatelessWidget {
  const _SharedAlbumCard({required this.album, required this.onTap, required this.isSharedSpace});

  final FotoAlbum album;
  final VoidCallback onTap;
  final bool isSharedSpace;

  @override
  Widget build(BuildContext context) {
    final thumbUrl = album.thumbnailUrl(size: 2, useTeamApi: isSharedSpace);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: thumbUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumbUrl,
                        httpHeaders: {'Cookie': DsmApi().cookie},
                        fit: BoxFit.cover,
                        memCacheWidth: 800,
                        placeholder: (context, _) => Container(color: const Color(0xFFEEEEEE)),
                        errorWidget: (context, _, __) => Container(
                          color: const Color(0xFFEEEEEE),
                          child: Center(
                            child: Icon(Icons.people_outline, color: Colors.grey[400], size: 40.r),
                          ),
                        ),
                      )
                    : Container(
                        color: const Color(0xFFEEEEEE),
                        child: Center(
                          child: Icon(Icons.people_outline, color: Colors.grey[400], size: 40.r),
                        ),
                      ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(12.w, 24.h, 12.w, 10.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              album.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.asp,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              '${album.itemCount} 张照片',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12.asp,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.people, color: Colors.white70, size: 20.r),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedAlbumDetailPage extends StatefulWidget {
  const _SharedAlbumDetailPage({required this.album, this.isSharedSpace = false});
  final FotoAlbum album;
  final bool isSharedSpace;

  @override
  State<_SharedAlbumDetailPage> createState() => _SharedAlbumDetailPageState();
}

class _SharedAlbumDetailPageState extends State<_SharedAlbumDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final List<FotoPhoto> _photos = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 100;

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
    _scrollController.addListener(_onScroll);
    _loadPhotos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    final pos = _scrollController.position;
    if (pos.pixels > pos.maxScrollExtent - 400) _loadMore();
  }

  Future<void> _loadPhotos() async {
    setState(() => _loading = true);
    try {
      final res = widget.isSharedSpace
          ? await DsmApi().fotoTeamBrowseItem(offset: 0, limit: _limit, albumId: widget.album.id)
          : await DsmApi().fotoBrowseItem(offset: 0, limit: _limit, albumId: widget.album.id);
      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        _photos.clear();
        _photos.addAll(list.map((e) => FotoPhoto.fromJson(e)));
        _offset = _photos.length;
        _hasMore = _photos.length >= _limit;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = widget.isSharedSpace
          ? await DsmApi().fotoTeamBrowseItem(offset: _offset, limit: _limit, albumId: widget.album.id)
          : await DsmApi().fotoBrowseItem(offset: _offset, limit: _limit, albumId: widget.album.id);
      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        final photos = list.map((e) => FotoPhoto.fromJson(e)).toList();
        _photos.addAll(photos);
        _offset += photos.length;
        _hasMore = photos.length >= _limit;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(child: Text('暂无照片', style: TextStyle(fontSize: 14.asp, color: Colors.grey)))
              : CustomScrollBar(
                  controller: _scrollController,
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(4.r),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4.r,
                      mainAxisSpacing: 4.r,
                      childAspectRatio: 1,
                    ),
                    itemCount: _photos.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _photos.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final photo = _photos[index];
                      return PhotoGridItem(
                        url: photo.thumbnailUrl(size: 1, useTeamApi: widget.isSharedSpace),
                        isVideo: photo.isVideo,
                        isLivePhoto: photo.isLivePhoto,
                        onTap: () => AppImage.preview(photos: _toPreviewList(_photos), initialIndex: index),
                      );
                    },
                  ),
                ),
    );
  }
}

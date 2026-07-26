import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:convert';

import '../../../components/CustomScrollBar.dart';
import '../../../network/dsm_api.dart';
import '../../../utils/app_adaptive.dart';
import '../../../utils/app_preferences.dart';
import '../../common/image_preview_page.dart';
import '../models/foto_photo.dart';
import 'photo_grid_item.dart';

class RecentTab extends StatefulWidget {
  const RecentTab({super.key, this.isSharedSpace = false});

  final bool isSharedSpace;

  @override
  State<RecentTab> createState() => RecentTabState();
}

class RecentTabState extends State<RecentTab> {
  final ScrollController _scrollController = ScrollController();
  final List<FotoPhoto> _photos = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
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

  List<PreviewPhoto>? get previewPhotos {
    if (_photos.isEmpty) return null;
    return _toPreviewList(_photos);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPhotos();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    final pos = _scrollController.position;
    if (pos.pixels > pos.maxScrollExtent - 400) {
      _loadMore();
    }

  }

  Future<void> _loadPhotos() async {
    _error = null;
    // 1. Show cached data immediately if available
    final cached = AppPreferences.getString('cache_photos_recent');
    if (cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached) as List;
        _photos.clear();
        _photos.addAll(list.map((e) => FotoPhoto.fromJson(e)));
        _loading = false;
        _offset = _photos.length;
        _hasMore = _photos.length >= _limit;
        if (mounted) setState(() {});
      } catch (_) {}
    }
    // 2. Fetch fresh data from API
    if (_loading) {
      setState(() { _loading = true; });
    }
    try {
      final res = await (widget.isSharedSpace ? DsmApi().fotoTeamRecentlyAdded(offset: 0, limit: _limit) : DsmApi().fotoRecentlyAdded(offset: 0, limit: _limit));
      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        final photos = list.map((e) => FotoPhoto.fromJson(e)).toList();
        _photos.clear();
        _photos.addAll(photos);
        _offset = photos.length;
        _hasMore = photos.length >= _limit;
        // Save to cache
        AppPreferences.putString('cache_photos_recent', jsonEncode(list));
      } else {
        _error = '加载失败';
      }
    } catch (e) {
      _error = '网络错误: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await (widget.isSharedSpace ? DsmApi().fotoTeamRecentlyAdded(offset: _offset, limit: _limit) : DsmApi().fotoRecentlyAdded(offset: _offset, limit: _limit));
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
              onPressed: _loadPhotos,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_photos.isEmpty) {
      return Center(
        child: Text('暂无最近添加的照片', style: TextStyle(fontSize: 14.asp, color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: CustomScrollBar(
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
              onTap: () => AppImage.preview(
                photos: _toPreviewList(_photos),
                initialIndex: index,
              ),
            );
          },
        ),
      ),
    );
  }
}

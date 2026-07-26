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

class VideoTab extends StatefulWidget {
  final bool isSharedSpace;

  const VideoTab({super.key, this.isSharedSpace = false});

  @override
  State<VideoTab> createState() => VideoTabState();
}

class VideoTabState extends State<VideoTab> {
  final ScrollController _scrollController = ScrollController();
  final List<FotoPhoto> _photos = [];
  final Map<String, List<FotoPhoto>> _grouped = {};
  final List<String> _dateKeys = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;
  static const int _limit = 100;

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
    final cached = AppPreferences.getString('cache_photos_video');
    if (cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached) as List;
        _photos.clear();
        _photos.addAll(list.map((e) => FotoPhoto.fromJson(e)));
        _rebuildGroups();
        _loading = false;
        _offset = list.length;
        _hasMore = list.length >= _limit;
        if (mounted) setState(() {});
      } catch (_) {}
    }
    // 2. Fetch fresh data from API
    if (_loading) {
      setState(() { _loading = true; });
    }
    try {
      final res = DsmApi().dsmVersion >= 7
          ? widget.isSharedSpace
              ? await DsmApi().fotoTeamBrowseItem(offset: 0, limit: _limit, type: 'video')
              : await DsmApi().fotoBrowseItem(offset: 0, limit: _limit, type: 'video')
          : await DsmApi().photoTimeline(offset: 0, limit: _limit);

      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        // fotoBrowseItem(type: 'video') 已过滤，无需再筛
        final photos = list
            .map((e) => FotoPhoto.fromJson(e))
            .toList();
        _photos.clear();
        _photos.addAll(photos);
        _rebuildGroups();
        _offset = list.length; // 用原始列表长度作为offset
        _hasMore = list.length >= _limit;
        // Save to cache
        AppPreferences.putString('cache_photos_video', jsonEncode(list));
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
      final res = DsmApi().dsmVersion >= 7
          ? widget.isSharedSpace
              ? await DsmApi().fotoTeamBrowseItem(offset: _offset, limit: _limit, type: 'video')
              : await DsmApi().fotoBrowseItem(offset: _offset, limit: _limit, type: 'video')
          : await DsmApi().photoTimeline(offset: _offset, limit: _limit);

      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        // fotoBrowseItem(type: 'video') 已过滤，无需再筛
        final videos = list
            .map((e) => FotoPhoto.fromJson(e))
            .toList();
        _photos.addAll(videos);
        _rebuildGroups();
        _offset += list.length;
        _hasMore = list.length >= _limit;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  void _rebuildGroups() {
    _grouped.clear();
    _dateKeys.clear();
    for (final p in _photos) {
      final key = p.dateGroupKey;
      if (key.isEmpty) continue;
      _grouped.putIfAbsent(key, () => []).add(p);
    }
    _dateKeys.addAll(_grouped.keys);
  }

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
    if (_dateKeys.isEmpty) {
      return Center(
        child: Text('暂无视频', style: TextStyle(fontSize: 14.asp, color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: CustomScrollBar(
        controller: _scrollController,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            for (final dateKey in _dateKeys) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, 8.h),
                  child: Text(
                    _formatDateHeader(dateKey),
                    style: TextStyle(
                      fontSize: 15.asp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4.r,
                    mainAxisSpacing: 4.r,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final photo = _grouped[dateKey]![index];
                      return PhotoGridItem(
                        url: photo.thumbnailUrl(size: 1, useTeamApi: widget.isSharedSpace),
                        isVideo: photo.isVideo,
                        onTap: () => AppImage.preview(
                          photos: _toPreviewList(_photos),
                          initialIndex: _photos.indexOf(photo),
                        ),
                      );
                    },
                    childCount: _grouped[dateKey]!.length,
                  ),
                ),
              ),
            ],
            if (_loadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.r),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateHeader(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length == 3) {
      return '${parts[0]}年${int.parse(parts[1])}月${int.parse(parts[2])}日';
    }
    return dateKey;
  }
}

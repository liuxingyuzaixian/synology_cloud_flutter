import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:convert';

import '../../../components/CustomScrollBar.dart';
import '../../../network/dsm_api.dart';
import '../../../utils/app_adaptive.dart';
import '../../../utils/app_preferences.dart';
import '../../common/image_preview_page.dart';
import '../models/foto_photo.dart';
import '../models/foto_tag.dart';
import 'photo_grid_item.dart';

class TagsTab extends StatefulWidget {
  const TagsTab({super.key, this.isSharedSpace = false});

  final bool isSharedSpace;

  @override
  State<TagsTab> createState() => TagsTabState();
}

class TagsTabState extends State<TagsTab> {
  final List<FotoTag> _tags = [];
  bool _loading = true;
  String? _error;

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

  List<PreviewPhoto>? get previewPhotos => null; // Tags tab needs a tag selection first

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    _error = null;
    // 1. Show cached data immediately if available
    final cached = AppPreferences.getString('cache_photos_tags');
    if (cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached) as List;
        _tags.clear();
        _tags.addAll(list.map((e) => FotoTag.fromJson(e)));
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
          ? await DsmApi().fotoTeamGeneralTag(offset: 0, limit: 100)
          : await DsmApi().fotoGeneralTag(offset: 0, limit: 100);
      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        _tags.clear();
        _tags.addAll(list.map((e) => FotoTag.fromJson(e)));
        // Save to cache
        AppPreferences.putString('cache_photos_tags', jsonEncode(list));
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
              onPressed: _loadTags,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_tags.isEmpty) {
      return Center(
        child: Text('暂无标签', style: TextStyle(fontSize: 14.asp, color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadTags,
      child: CustomScrollBar(
        child: GridView.builder(
          padding: EdgeInsets.all(12.r),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12.w,
          mainAxisSpacing: 12.h,
          childAspectRatio: 1.2,
        ),
        itemCount: _tags.length,
        itemBuilder: (context, index) {
          final tag = _tags[index];
          return _TagCard(
            tag: tag,
            onTap: () => _openTag(tag),
            isSharedSpace: widget.isSharedSpace,
          );
        },
      ),
      ),
    );
  }

  void _openTag(FotoTag tag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TagDetailPage(tag: tag, isSharedSpace: widget.isSharedSpace),
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  const _TagCard({required this.tag, required this.onTap, required this.isSharedSpace});

  final FotoTag tag;
  final VoidCallback onTap;
  final bool isSharedSpace;

  @override
  Widget build(BuildContext context) {
    final thumbUrl = tag.thumbnailUrl(size: 2, useTeamApi: isSharedSpace);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumbUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: thumbUrl,
                    httpHeaders: {'Cookie': DsmApi().cookie},
                    fit: BoxFit.cover,
                    memCacheWidth: 400,
                    placeholder: (context, _) => Container(color: const Color(0xFFEEEEEE)),
                    errorWidget: (context, _, __) => Container(
                      color: const Color(0xFFEEEEEE),
                      child: Center(
                        child: Icon(Icons.label_outline, color: Colors.grey[400], size: 36.r),
                      ),
                    ),
                  )
                : Container(
                    color: const Color(0xFFEEEEEE),
                    child: Center(
                      child: Icon(Icons.label_outline, color: Colors.grey[400], size: 36.r),
                    ),
                  ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(10.w, 20.h, 10.w, 8.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tag.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.asp,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${tag.itemCount} 张',
                      style: TextStyle(color: Colors.white70, fontSize: 12.asp),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagDetailPage extends StatefulWidget {
  const _TagDetailPage({required this.tag, this.isSharedSpace = false});
  final FotoTag tag;
  final bool isSharedSpace;

  @override
  State<_TagDetailPage> createState() => _TagDetailPageState();
}

class _TagDetailPageState extends State<_TagDetailPage> {
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
          ? await DsmApi().fotoTeamBrowseItem(
              offset: 0,
              limit: _limit,
              generalTagId: widget.tag.id,
            )
          : await DsmApi().fotoBrowseItem(
              offset: 0,
              limit: _limit,
              generalTagId: widget.tag.id,
            );
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
          ? await DsmApi().fotoTeamBrowseItem(
              offset: _offset,
              limit: _limit,
              generalTagId: widget.tag.id,
            )
          : await DsmApi().fotoBrowseItem(
              offset: _offset,
              limit: _limit,
              generalTagId: widget.tag.id,
            );
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
      appBar: AppBar(title: Text(widget.tag.name)),
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

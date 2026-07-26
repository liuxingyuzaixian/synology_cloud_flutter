import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../components/CustomScrollBar.dart';
import '../../../network/dsm_api.dart';
import '../../../utils/app_adaptive.dart';
import '../../common/image_preview_page.dart';
import '../models/foto_photo.dart';
import 'photo_grid_item.dart';

/// 地理位置条目
class _GeocodingEntry {
  _GeocodingEntry({
    required this.id,
    required this.name,
    this.country = '',
    this.firstLevel = '',
    this.secondLevel = '',
    this.itemCount = 0,
    this.thumbnailUnitId,
    this.thumbnailCacheKey,
  });

  final int id;
  final String name;
  final String country;
  final String firstLevel;
  final String secondLevel;
  final int itemCount;
  final int? thumbnailUnitId;
  final String? thumbnailCacheKey;

  factory _GeocodingEntry.fromJson(Map<String, dynamic> json) {
    int? uid;
    String? ck;
    final additional = json['additional'];
    if (additional is Map<String, dynamic>) {
      final thumbnail = additional['thumbnail'];
      if (thumbnail is Map<String, dynamic>) {
        // 兼容多种字段名
        final rawId = thumbnail['unit_id'] ?? thumbnail['photo_unit_id'] ?? thumbnail['id'];
        if (rawId != null) {
          uid = rawId is int ? rawId : int.tryParse(rawId.toString());
        }
        ck = thumbnail['cache_key']?.toString();
      }
    }
    return _GeocodingEntry(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      country: json['country'] ?? '',
      firstLevel: json['first_level'] ?? '',
      secondLevel: json['second_level'] ?? '',
      itemCount: json['item_count'] ?? 0,
      thumbnailUnitId: uid,
      thumbnailCacheKey: ck,
    );
  }

  String thumbnailUrl({int size = 2, bool useTeamApi = false}) {
    if (thumbnailUnitId != null) {
      if (useTeamApi) {
        return DsmApi().fotoTeamThumbnailUrl(thumbnailUnitId!, size: size, cacheKey: thumbnailCacheKey);
      }
      return DsmApi().fotoThumbnailUrl(thumbnailUnitId!, size: size, cacheKey: thumbnailCacheKey);
    }
    return '';
  }
}

/// 按国家分组
class _CountryGroup {
  _CountryGroup({required this.country, required this.entries});
  final String country;
  final List<_GeocodingEntry> entries;
}

class LocationTab extends StatefulWidget {
  const LocationTab({super.key, this.isSharedSpace = false});

  final bool isSharedSpace;

  @override
  State<LocationTab> createState() => LocationTabState();
}

class LocationTabState extends State<LocationTab> {
  final List<_CountryGroup> _groups = [];
  // 缓存每个 entry 的封面图 URL（从 Browse.Item 获取的第一张照片）
  final Map<int, String> _coverUrls = {};
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
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loading = true;
      _error = null;
      _coverUrls.clear();
    });
    try {
      final res = widget.isSharedSpace
          ? await DsmApi().fotoTeamGeocoding(offset: 0, limit: 500)
          : await DsmApi().fotoGeocoding(offset: 0, limit: 500);
      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        final entries = list
            .map((e) => _GeocodingEntry.fromJson(e as Map<String, dynamic>))
            .where((e) => e.itemCount > 0)
            .toList();

        // 按国家分组
        final map = <String, List<_GeocodingEntry>>{};
        for (final e in entries) {
          final key = e.country.isNotEmpty ? e.country : '未知地区';
          map.putIfAbsent(key, () => []).add(e);
        }
        _groups.clear();
        map.forEach((country, items) {
          _groups.add(_CountryGroup(country: country, entries: items));
        });

        // 对没有封面的条目，异步加载第一张照片作为封面
        _loadMissingCovers(entries);
      } else {
        _error = '加载失败';
      }
    } catch (e) {
      _error = '网络错误: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 对缺少封面的条目，用 Browse.Item 获取第一张照片的缩略图
  Future<void> _loadMissingCovers(List<_GeocodingEntry> entries) async {
    final missing = entries.where((e) => e.thumbnailUnitId == null).toList();
    if (missing.isEmpty) return;

    for (final entry in missing) {
      if (!mounted) return;
      try {
        final res = widget.isSharedSpace
            ? await DsmApi().fotoTeamBrowseItem(
                offset: 0,
                limit: 1,
                geocodingId: entry.id,
              )
            : await DsmApi().fotoBrowseItem(
                offset: 0,
                limit: 1,
                geocodingId: entry.id,
              );
        if (res['success'] == true) {
          final list = (res['data']?['list'] as List?) ?? [];
          if (list.isNotEmpty) {
            final photo = FotoPhoto.fromJson(list.first as Map<String, dynamic>);
            if (mounted) {
              setState(() => _coverUrls[entry.id] = photo.thumbnailUrl(size: 2, useTeamApi: widget.isSharedSpace));
            }
          }
        }
      } catch (_) {}
    }
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
              onPressed: _loadLocations,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Text('暂无位置信息', style: TextStyle(fontSize: 14.asp, color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLocations,
      child: CustomScrollBar(
        child: ListView.builder(
          padding: EdgeInsets.all(12.r),
          itemCount: _groups.length,
          itemBuilder: (context, index) {
            final group = _groups[index];
            return _CountrySection(
              group: group,
              coverUrls: _coverUrls,
              onEntryTap: _openEntryPhotos,
              isSharedSpace: widget.isSharedSpace,
            );
          },
        ),
      ),
    );
  }

  void _openEntryPhotos(_GeocodingEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _LocationDetailPage(entry: entry, isSharedSpace: widget.isSharedSpace),
      ),
    );
  }
}

/// 国家分组区块
class _CountrySection extends StatelessWidget {
  const _CountrySection({
    required this.group,
    required this.coverUrls,
    required this.onEntryTap,
    required this.isSharedSpace,
  });
  final _CountryGroup group;
  final Map<int, String> coverUrls;
  final void Function(_GeocodingEntry) onEntryTap;
  final bool isSharedSpace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.w, bottom: 8.h, top: 8.h),
          child: Text(
            group.country,
            style: TextStyle(fontSize: 18.asp, fontWeight: FontWeight.bold),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8.r,
            mainAxisSpacing: 8.r,
            childAspectRatio: 1,
          ),
          itemCount: group.entries.length,
          itemBuilder: (context, index) {
            final entry = group.entries[index];
            return _LocationCard(
              entry: entry,
              fallbackCoverUrl: coverUrls[entry.id] ?? '',
              onTap: () => onEntryTap(entry),
              isSharedSpace: isSharedSpace,
            );
          },
        ),
        SizedBox(height: 16.h),
      ],
    );
  }
}

/// 单个位置卡片 — 封面图风格
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.entry,
    required this.fallbackCoverUrl,
    required this.onTap,
    required this.isSharedSpace,
  });
  final _GeocodingEntry entry;
  final String fallbackCoverUrl;
  final VoidCallback onTap;
  final bool isSharedSpace;

  @override
  Widget build(BuildContext context) {
    final thumbUrl = entry.thumbnailUrl(size: 2, useTeamApi: isSharedSpace);
    // 优先用 API 返回的封面，其次用异步加载的 fallback
    final coverUrl = thumbUrl.isNotEmpty ? thumbUrl : fallbackCoverUrl;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: coverUrl,
                    httpHeaders: {'Cookie': DsmApi().cookie},
                    fit: BoxFit.cover,
                    memCacheWidth: 600,
                    placeholder: (_, __) => Container(color: const Color(0xFFEEEEEE)),
                    errorWidget: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),
            // 底部渐变 + 名称 + 项目数
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8.w, 16.h, 8.w, 6.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(color: Colors.white, fontSize: 13.asp, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${entry.itemCount}个项目',
                      style: TextStyle(color: Colors.white70, fontSize: 11.asp),
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

  /// 无封面时的渐变占位
  Widget _buildPlaceholder() {
    final hue = (entry.id * 47) % 360;
    final color1 = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.45, 0.72).toColor();
    final color2 = HSLColor.fromAHSL(1.0, (hue + 30) % 360, 0.50, 0.55).toColor();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color1, color2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.location_on_rounded, color: Colors.white.withOpacity(0.85), size: 36.r),
      ),
    );
  }
}

/// 位置详情页 — 该位置下的照片列表
class _LocationDetailPage extends StatefulWidget {
  const _LocationDetailPage({required this.entry, this.isSharedSpace = false});
  final _GeocodingEntry entry;
  final bool isSharedSpace;

  @override
  State<_LocationDetailPage> createState() => _LocationDetailPageState();
}

class _LocationDetailPageState extends State<_LocationDetailPage> {
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
              geocodingId: widget.entry.id,
            )
          : await DsmApi().fotoBrowseItem(
              offset: 0,
              limit: _limit,
              geocodingId: widget.entry.id,
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
              geocodingId: widget.entry.id,
            )
          : await DsmApi().fotoBrowseItem(
              offset: _offset,
              limit: _limit,
              geocodingId: widget.entry.id,
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
      appBar: AppBar(title: Text(widget.entry.name)),
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

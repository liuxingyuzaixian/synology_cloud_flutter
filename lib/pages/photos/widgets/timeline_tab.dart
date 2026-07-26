import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'dart:convert';

import '../../../components/CustomScrollBar.dart';
import '../../../components/app_dialog.dart';
import '../../../network/dsm_api.dart';
import '../../../utils/app_adaptive.dart';
import '../../../utils/app_preferences.dart';
import '../../common/image_preview_page.dart';
import '../models/foto_photo.dart';
import 'photo_grid_item.dart';

class TimelineTab extends StatefulWidget {
  final bool isSharedSpace;
  final void Function(bool inSelect, void Function()? exitFn)? onSelectModeChanged;

  const TimelineTab({super.key, this.isSharedSpace = false, this.onSelectModeChanged});

  @override
  State<TimelineTab> createState() => TimelineTabState();
}

class TimelineTabState extends State<TimelineTab> {
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
  int _targetColumns = 0;
  double _visualScale = 1.0;
  double _pinchAccum = 0;
  bool _pinchChanged = false;
  int _pointerCount = 0;

  // Multi-select state
  bool selectMode = false;
  final Set<int> _selectedIds = {};
  int get selectedCount => _selectedIds.length;

  void exitSelect() => setState(() { selectMode = false; _selectedIds.clear(); widget.onSelectModeChanged?.call(false, null); });

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          selectMode = false;
          widget.onSelectModeChanged?.call(false, null);
        }
      } else {
        _selectedIds.add(id);
        selectMode = true;
        widget.onSelectModeChanged?.call(true, exitSelect);
      }
    });
  }

  Future<void> deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await AppDialog.confirm(
      title: '删除照片',
      message: '确定要删除选中的 ${_selectedIds.length} 张照片吗？',
      confirmText: '删除',
    );
    if (confirm != true) return;
    final close = AppDialog.showLoading(label: '删除中...');
    try {
      await DsmApi().fotoDeleteItem(_selectedIds.toList());
      close();
      AppDialog.toast('已删除 ${_selectedIds.length} 张');
      exitSelect();
      _loadPhotos();
    } catch (e) {
      close();
      AppDialog.toast('删除失败: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Restore saved column count
    final saved = AppPreferences.getInt('photo_grid_columns');
    if (saved > 0) {
      _targetColumns = saved.clamp(3, 8);
    }
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
    final cached = AppPreferences.getString('cache_photos_timeline');
    if (cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached) as List;
        _photos.clear();
        _photos.addAll(list.map((e) => FotoPhoto.fromJson(e)));
        _rebuildGroups();
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
      final res = DsmApi().dsmVersion >= 7
          ? widget.isSharedSpace
              ? await DsmApi().fotoTeamBrowseItem(offset: 0, limit: _limit)
              : await DsmApi().fotoBrowseItem(offset: 0, limit: _limit)
          : await DsmApi().photoTimeline(offset: 0, limit: _limit);

      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        final photos = list.map((e) => FotoPhoto.fromJson(e)).toList();
        _photos.clear();
        _photos.addAll(photos);
        _rebuildGroups();
        _offset = photos.length;
        _hasMore = photos.length >= _limit;
        // Save to cache (serialize via toJson for consistency with loadMore)
        AppPreferences.putString('cache_photos_timeline', jsonEncode(_photos.map((e) => e.toJson()).toList()));
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
              ? await DsmApi().fotoTeamBrowseItem(offset: _offset, limit: _limit)
              : await DsmApi().fotoBrowseItem(offset: _offset, limit: _limit)
          : await DsmApi().photoTimeline(offset: _offset, limit: _limit);

      if (res['success'] == true) {
        final list = (res['data']?['list'] as List?) ?? [];
        final photos = list.map((e) => FotoPhoto.fromJson(e)).toList();
        _photos.addAll(photos);
        _rebuildGroups();
        _offset += photos.length;
        _hasMore = photos.length >= _limit;
        // Cache all accumulated data (not just first page)
        AppPreferences.putString('cache_photos_timeline', jsonEncode(_photos.map((e) => e.toJson()).toList()));
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

  bool _isTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide > 600;
  }

  int get _gridColumns {
    final width = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;
    // 平板设备初始化直接上最高档
    if (_isTablet(context) && _targetColumns <= 0) {
      return 8;
    }
    int base;
    if (orientation == Orientation.landscape) {
      if (width > 1200) base = 10;
      else if (width > 900) base = 8;
      else base = 6;
    } else {
      if (width > 900) base = 6;
      else if (width > 600) base = 4;
      else base = 3;
    }
    // When user has pinned a column count via pinch, use it
    if (_targetColumns > 0) return _targetColumns.clamp(3, 8);
    return base.clamp(3, 8);
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

  /// 首次加载骨架屏：模拟日期分组 + 方格照片墙
  Widget _buildSkeleton() {
    final columns = _gridColumns;
    return Skeletonizer(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          for (var group = 0; group < 3; group++) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.aw, 16.h, 12.aw, 8.h),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Bone.text(words: 2, fontSize: 15.asp),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 1.5.w),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 1.5.r,
                  mainAxisSpacing: 1.5.r,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const Bone(),
                  childCount: columns * 3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildSkeleton();
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
        child: Text('暂无照片', style: TextStyle(fontSize: 14.asp, color: Colors.grey)),
      );
    }
    return PopScope(
      canPop: !selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selectMode) exitSelect();
      },
      child: Stack(
        children: [
          RefreshIndicator(
      onRefresh: _loadPhotos,
      child: CustomScrollBar(
        controller: _scrollController,
        child: GestureDetector(
          onScaleStart: (_) {
            setState(() {
              _visualScale = 1.0;
              _pinchAccum = 0;
              _pinchChanged = false;
              if (_targetColumns <= 0) _targetColumns = _gridColumns;
            });
          },
          onScaleUpdate: (details) {
            // 每次捏合手势只变化一级
            if (_pinchChanged) return;
            setState(() {
              _visualScale = details.scale;
              _pinchAccum += details.scale - 1.0;
              if (_targetColumns <= 0) _targetColumns = _gridColumns;
              if (_pinchAccum > 0.15) {
                _targetColumns = (_targetColumns - 1).clamp(3, 8);
                _pinchAccum = 0;
                _pinchChanged = true;
              } else if (_pinchAccum < -0.15) {
                _targetColumns = (_targetColumns + 1).clamp(3, 8);
                _pinchAccum = 0;
                _pinchChanged = true;
              }
            });
          },
          onScaleEnd: (_) {
            setState(() {
              _visualScale = 1.0;
              _pinchAccum = 0;
              _pinchChanged = false;
            });
            // Persist zoom level
            AppPreferences.putInt('photo_grid_columns', _targetColumns);
          },
          child: Listener(
            onPointerDown: (e) {
              _pointerCount++;
              if (_pointerCount >= 2) setState(() {});
            },
            onPointerUp: (e) {
              _pointerCount = (_pointerCount - 1).clamp(0, 99);
              if (_pointerCount < 2) setState(() {});
            },
            onPointerCancel: (e) {
              _pointerCount = 0;
              setState(() {});
            },
            child: CustomScrollView(
            physics: _pointerCount >= 2 ? const NeverScrollableScrollPhysics() : null,
            controller: _scrollController,
          slivers: [
            for (final dateKey in _dateKeys) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.aw, 16.h, 12.aw, 8.h),
                  child: Text(
                    _formatDateHeader(dateKey),
                    style: TextStyle(
                      fontSize: 15.asp,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 1.5.w),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumns,
                    crossAxisSpacing: 1.5.r,
                    mainAxisSpacing: 1.5.r,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final photo = _grouped[dateKey]![index];
                      final id = photo.id;
                      final isSelected = _selectedIds.contains(id);
                      return InkWell(
                        onTap: selectMode ? () => _toggleSelect(id) : () => _openPreview(photo),
                        onLongPress: () => _toggleSelect(id),
                        child: Stack(
                          children: [
                            PhotoGridItem(
                              url: photo.thumbnailUrl(size: 1, useTeamApi: widget.isSharedSpace),
                              isVideo: photo.isVideo,
                              isLivePhoto: photo.isLivePhoto,
                              onTap: selectMode ? () => _toggleSelect(id) : () => _openPreview(photo),
                            ),
                            if (selectMode)
                              Positioned(
                                top: 2, right: 2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blue : Colors.black26,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    color: isSelected ? Colors.white : Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                            if (selectMode)
                              Positioned.fill(
                                child: Container(color: isSelected ? Colors.blue.withOpacity(0.15) : Colors.transparent),
                              ),
                          ],
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
        ), // CustomScrollView
        ), // Listener
        ), // GestureDetector
      ), // CustomScrollBar
    ), // RefreshIndicator
    if (selectMode)
      Positioned(
        top: 8, left: 8,
        child: SafeArea(
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: exitSelect,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black38,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ),
    if (selectMode && _selectedIds.isNotEmpty)
      Positioned(
        top: 8, right: 8,
        child: SafeArea(
          child: IconButton(
            onPressed: deleteSelected,
            icon: Icon(Icons.delete_outline, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.8),
            ),
          ),
        ),
      ),
  ], // Stack children
  ) // close Stack
); // close PopScope
  }

  String _formatDateHeader(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length == 3) {
      return '${parts[0]}年${int.parse(parts[1])}月${int.parse(parts[2])}日';
    }
    return dateKey;
  }

  void _openPreview(FotoPhoto photo) {
    AppImage.preview(
      photos: _toPreviewList(_photos),
      initialIndex: _photos.indexOf(photo),
    );
  }
}

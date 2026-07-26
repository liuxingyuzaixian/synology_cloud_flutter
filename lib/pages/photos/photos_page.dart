import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/fly_router.dart';
import '../common/image_preview_page.dart';
import 'slideshow_page.dart';
import 'widgets/albums_tab.dart';
import 'widgets/folders_tab.dart';
import 'widgets/location_tab.dart';
import 'widgets/recent_tab.dart';
import 'widgets/shared_tab.dart';
import 'widgets/tags_tab.dart';
import 'widgets/timeline_tab.dart';
import 'widgets/video_tab.dart';

class PhotosRouteModule extends FlyRouteModule {
  static const routeName = '/photos';

  @override
  List<AppRoute> get routes => [
        AppRoute(
          name: routeName,
          builder: (_, __) => const PhotosPage(),
        ),
      ];
}

class PhotosPage extends StatefulWidget {
  final void Function(bool inSelect, void Function()? exitFn)? onSelectModeChanged;
  const PhotosPage({super.key, this.onSelectModeChanged});

  @override
  State<PhotosPage> createState() => PhotosPageState();
}

class PhotosPageState extends State<PhotosPage> {
  int _currentIndex = 0;
  int _rebuildKey = 0;
  bool _isSharedSpace = false;

  // Global keys for each tab to access their state
  final _timelineKey = GlobalKey<TimelineTabState>();
  final _albumsKey = GlobalKey<AlbumsTabState>();
  final _recentKey = GlobalKey<RecentTabState>();
  final _videoKey = GlobalKey<VideoTabState>();
  final _foldersKey = GlobalKey<FoldersTabState>();
  final _locationKey = GlobalKey<LocationTabState>();
  final _tagsKey = GlobalKey<TagsTabState>();
  final _sharedKey = GlobalKey<SharedTabState>();

  static const _tabs = [
    _TabDef(text: '时间线', icon: Icons.timeline),
    _TabDef(text: '相册', icon: Icons.photo_album_outlined),
    _TabDef(text: '最近添加', icon: Icons.access_time),
    _TabDef(text: '视频', icon: Icons.videocam_outlined),
    _TabDef(text: '文件夹', icon: Icons.folder_outlined),
    _TabDef(text: '位置', icon: Icons.location_on_outlined),
    _TabDef(text: '标签', icon: Icons.label_outlined),
    _TabDef(text: '共享', icon: Icons.people_outline),
  ];

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return TimelineTab(key: _timelineKey, isSharedSpace: _isSharedSpace, onSelectModeChanged: widget.onSelectModeChanged);
      case 1:
        return AlbumsTab(key: _albumsKey, isSharedSpace: _isSharedSpace);
      case 2:
        return RecentTab(key: _recentKey, isSharedSpace: _isSharedSpace);
      case 3:
        return VideoTab(key: _videoKey, isSharedSpace: _isSharedSpace);
      case 4:
        return FoldersTab(key: _foldersKey, isSharedSpace: _isSharedSpace);
      case 5:
        return LocationTab(key: _locationKey, isSharedSpace: _isSharedSpace);
      case 6:
        return TagsTab(key: _tagsKey, isSharedSpace: _isSharedSpace);
      case 7:
        return SharedTab(key: _sharedKey, isSharedSpace: _isSharedSpace);
      default:
        return const SizedBox.shrink();
    }
  }

  void _startSlideshow() {
    List<PreviewPhoto>? photos;
    switch (_currentIndex) {
      case 0:
        photos = _timelineKey.currentState?.previewPhotos;
      case 1:
        photos = _albumsKey.currentState?.previewPhotos;
      case 2:
        photos = _recentKey.currentState?.previewPhotos;
      case 3:
        photos = _videoKey.currentState?.previewPhotos;
      case 4:
        photos = _foldersKey.currentState?.previewPhotos;
      case 5:
        photos = _locationKey.currentState?.previewPhotos;
      case 6:
        photos = _tagsKey.currentState?.previewPhotos;
      case 7:
        photos = _sharedKey.currentState?.previewPhotos;
    }
    if (photos == null || photos.isEmpty) {
      AppDialog.toast('当前没有可播放的内容');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SlideshowPage(photos: photos!)),
    );
  }

  void _showTabMenu() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with shared space toggle
              Row(
                children: [
                  Text('照片视图', style: TextStyle(fontSize: 18.asp, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _isSharedSpace = !_isSharedSpace);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isSharedSpace
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isSharedSpace ? Icons.people : Icons.person,
                            size: 16,
                            color: _isSharedSpace
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isSharedSpace ? '共享空间' : '个人空间',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _isSharedSpace
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              // Tab grid
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(_tabs.length, (index) {
                  final tab = _tabs[index];
                  final selected = index == _currentIndex;
                  return FilterChip(
                    avatar: Icon(
                      tab.icon,
                      size: 18,
                      color: selected ? theme.colorScheme.primary : Colors.grey.shade600,
                    ),
                    label: Text(tab.text),
                    selected: selected,
                    selectedColor: theme.colorScheme.primaryContainer,
                    onSelected: (_) {
                      Navigator.pop(ctx);
                      setState(() {
                        _currentIndex = index;
                        _rebuildKey = 0;
                      });
                    },
                  );
                }),
              ),
              SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Outline/halo so top-bar text & icons stay legible when the transparent
    // app bar overlaps non-white photo areas. Uses a color that contrasts the
    // element (light halo in light theme, dark halo in dark theme).
    final legibilityShadows = <Shadow>[
      Shadow(
        color: theme.brightness == Brightness.light
            ? Colors.white
            : Colors.black,
        blurRadius: 3,
      ),
    ];
    final timelineState = _timelineKey.currentState;
    final isSelecting = timelineState?.selectMode ?? false;
    final selectedCount = timelineState?.selectedCount ?? 0;

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isSelecting) {
          timelineState?.exitSelect();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            color: isSelecting
                ? Theme.of(context).scaffoldBackgroundColor
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SafeArea(
              child: isSelecting
                  ? Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => timelineState?.exitSelect(),
                  ),
                  const SizedBox(width: 8),
                  Text('已选 $selectedCount 项'),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                    onPressed: selectedCount > 0 ? () => timelineState?.deleteSelected() : null,
                  ),
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _showTabMenu,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_tabs[_currentIndex].icon, size: 14, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                _tabs[_currentIndex].text,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.expand_more, size: 16, color: theme.colorScheme.primary),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.play_circle_outline,
                            color: theme.colorScheme.primary,
                            shadows: legibilityShadows),
                        tooltip: '播放幻灯片',
                        onPressed: _startSlideshow,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40),
                      ),
                    ],
                  ),
                  Text(
                    _isSharedSpace ? '照片 · 共享空间' : '照片',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        shadows: legibilityShadows),
                  ),
                  const SizedBox(width: 120),
                ],
              ),
            ),
          ),
        ),
        body: _buildBody(),
        floatingActionButton: FloatingActionButton(
          heroTag: 'photos_fab',
          onPressed: _showTabMenu,
          child: const Icon(Icons.dashboard),
        ),
      ),
    );
  }
}

class _TabDef {
  const _TabDef({required this.text, required this.icon});
  final String text;
  final IconData icon;
}

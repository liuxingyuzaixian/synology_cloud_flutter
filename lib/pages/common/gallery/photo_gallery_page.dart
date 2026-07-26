import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../components/CustomScrollBar.dart';
import 'full_screen_gallery_page.dart';
import 'mock_data.dart';

class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key});

  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollBar(
      controller: _scrollController,
      thumbVisibility: true,
      interactive: true,
      thickness: 10,
      radius: const Radius.circular(4),
      minThumbLength: 48,
      crossAxisMargin: 10,
      thumbColor: Colors.black,
      child: GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(4.r),
        // 增加缓存范围，提前渲染可视区外更多的 item
        cacheExtent: 1000,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4.r,
          mainAxisSpacing: 4.r,
          childAspectRatio: 1,
        ),
        itemCount: mockGalleryData.length,
        itemBuilder: (context, index) {
          final url = mockGalleryData[index];
          return _PhotoGridItem(
            url: url,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FullScreenGalleryPage(
                    images: mockGalleryData,
                    initialIndex: index,
                    title: '相册',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// 将 StatelessWidget 改为 StatefulWidget 并保活
class _PhotoGridItem extends StatefulWidget {
  const _PhotoGridItem({
    required this.url,
    required this.onTap,
  });

  final String url;
  final VoidCallback onTap;

  @override
  State<_PhotoGridItem> createState() => _PhotoGridItemState();
}

class _PhotoGridItemState extends State<_PhotoGridItem> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 关键：不允许滑出屏幕后销毁

  @override
  Widget build(BuildContext context) {
    // 注意：使用 AutomaticKeepAliveClientMixin 时，必须在 build 开头调用 super.build
    super.build(context);
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: CachedNetworkImage(
          key: ValueKey(widget.url),
          imageUrl: widget.url,
          fit: BoxFit.cover,
          memCacheWidth: 400,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          placeholder: (context, _) => Container(
            color: const Color(0xFFEEEEEE),
          ),
          errorWidget: (context, _, error) => Container(
            color: const Color(0xFFEEEEEE),
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.grey[400],
                size: 28.r,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

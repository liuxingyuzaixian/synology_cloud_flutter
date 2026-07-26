import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../network/dsm_api.dart';

class PhotoGridItem extends StatelessWidget {
  const PhotoGridItem({
    super.key,
    required this.url,
    required this.onTap,
    this.isVideo = false,
    this.isLivePhoto = false,
  });

  final String url;
  final VoidCallback onTap;
  final bool isVideo;
  final bool isLivePhoto;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorImage =
        isDark ? 'assets/imgErrorDark.png' : 'assets/imgErrorLight.png';

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Scale icons relative to grid item size
          final itemSize = constraints.maxWidth;
          final iconScale = (itemSize / 120).clamp(0.4, 1.5);

          return Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: url,
                httpHeaders: {'Cookie': DsmApi().cookie},
                fit: BoxFit.cover,
                memCacheWidth: 400,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholderFadeInDuration: Duration.zero,
                placeholder: (context, _) => Container(
                  color: const Color(0xFFEEEEEE),
                ),
                errorWidget: (context, _, __) => Container(
                  color: const Color(0xFFEEEEEE),
                ),
              ),
              if (isVideo)
                Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 36 * iconScale,
                  ),
                ),
              if (isLivePhoto)
                Positioned(
                  top: 4 * iconScale,
                  left: 4 * iconScale,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6 * iconScale, vertical: 2 * iconScale),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(4 * iconScale),
                    ),
                    child: Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9 * iconScale,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

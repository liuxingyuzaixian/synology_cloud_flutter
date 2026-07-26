import '../../../network/dsm_api.dart';

class FotoTag {
  FotoTag({
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.thumbnailUnitId,
    this.thumbnailCacheKey,
  });

  final int id;
  final String name;
  final int itemCount;
  final int? thumbnailUnitId;
  final String? thumbnailCacheKey;

  factory FotoTag.fromJson(Map<String, dynamic> json) {
    int? unitId;
    String? cacheKey;
    final additional = json['additional'];
    if (additional != null) {
      final thumbnail = additional['thumbnail'];
      if (thumbnail != null) {
        unitId = thumbnail['unit_id'];
        cacheKey = thumbnail['cache_key'];
      }
    }
    return FotoTag(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      itemCount: json['item_count'] ?? 0,
      thumbnailUnitId: unitId,
      thumbnailCacheKey: cacheKey,
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

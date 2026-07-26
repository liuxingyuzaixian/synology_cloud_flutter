import '../../../network/dsm_api.dart';

class FotoAlbum {
  FotoAlbum({
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.createTime = 0,
    this.shared = false,
    this.thumbnailUnitId,
    this.thumbnailCacheKey,
  });

  final int id;
  final String name;
  final int itemCount;
  final int createTime;
  final bool shared;
  final int? thumbnailUnitId;
  final String? thumbnailCacheKey;

  factory FotoAlbum.fromJson(Map<String, dynamic> json) {
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
    return FotoAlbum(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      itemCount: json['item_count'] ?? 0,
      createTime: json['create_time'] ?? 0,
      shared: json['shared'] ?? false,
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

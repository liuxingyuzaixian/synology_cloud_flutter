class FotoFolder {
  FotoFolder({
    required this.id,
    required this.name,
    this.parent,
    this.itemCount = 0,
    this.thumbnailUnitIds = const [],
    this.thumbnailCacheKeys = const [],
    this.folderCoverSeqs = const [],
  });

  final int id;
  final String name;
  final int? parent;
  final int itemCount;
  final List<int> thumbnailUnitIds;
  final List<String> thumbnailCacheKeys;
  final List<int> folderCoverSeqs;

  factory FotoFolder.fromJson(Map<String, dynamic> json) {
    List<int> unitIds = [];
    List<String> cacheKeys = [];
    List<int> coverSeqs = [];
    final additional = json['additional'];
    if (additional != null) {
      final thumbnails = additional['thumbnail'];
      if (thumbnails is List) {
        for (final t in thumbnails) {
          if (t['unit_id'] != null) unitIds.add(t['unit_id']);
          if (t['cache_key'] != null) cacheKeys.add(t['cache_key']);
          if (t['folder_cover_seq'] != null) coverSeqs.add(t['folder_cover_seq']);
        }
      }
    }
    return FotoFolder(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      parent: json['parent'],
      itemCount: json['item_count'] ?? 0,
      thumbnailUnitIds: unitIds,
      thumbnailCacheKeys: cacheKeys,
      folderCoverSeqs: coverSeqs,
    );
  }

  String get displayName {
    if (name == '/') return '/';
    return name.split('/').last;
  }
}

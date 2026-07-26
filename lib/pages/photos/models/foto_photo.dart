import '../../../network/dsm_api.dart';

class FotoPhoto {
  FotoPhoto({
    required this.id,
    required this.filename,
    this.filesize = 0,
    this.time = 0,
    this.type = 'photo',
    this.folderId,
    this.unitId,
    this.cacheKey,
    this.livePhotoVideoId,
  });

  final int id;
  final String filename;
  final int filesize;
  final int time;
  final String type; // "photo" or "video"
  final int? folderId;
  final int? unitId;
  final String? cacheKey;
  final int? livePhotoVideoId;

  factory FotoPhoto.fromJson(Map<String, dynamic> json) {
    int? uid;
    String? ck;
    int? lpVideoId;
    final additional = json['additional'];
    if (additional is Map<String, dynamic>) {
      final thumbnail = additional['thumbnail'];
      if (thumbnail is Map<String, dynamic>) {
        uid = thumbnail['unit_id'];
        ck = thumbnail['cache_key']?.toString();
      }
      // Detect live photo companion video ID from various API fields
      final liveBalloon = additional['live_balloon'];
      if (liveBalloon is Map<String, dynamic>) {
        lpVideoId = liveBalloon['video_item_id'] ?? liveBalloon['id'];
      }
      lpVideoId ??= additional['video_item_id'];
      final motionPhoto = additional['motion_photo'];
      if (lpVideoId == null && motionPhoto is Map<String, dynamic>) {
        lpVideoId = motionPhoto['video_id'];
      }
    }

    return FotoPhoto(
      id: json['id'] ?? 0,
      filename: json['filename'] ?? '',
      filesize: json['filesize'] ?? 0,
      time: json['time'] ?? 0,
      type: json['type'] ?? 'photo',
      folderId: json['folder_id'],
      unitId: uid,
      cacheKey: ck,
      livePhotoVideoId: lpVideoId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'filename': filename,
    'filesize': filesize,
    'time': time,
    'type': type,
    'folderId': folderId,
    'livePhotoVideoId': livePhotoVideoId,
  };

  bool get isVideo => type == 'video';

  /// 实况照片检测 (HEIC/HEIF 格式通常包含实况照片)
  bool get isLivePhoto {
    if (livePhotoVideoId != null) return true;
    final ext = filename.split('.').last.toLowerCase();
    const liveExtensions = {'heic', 'heif'};
    const animatedExtensions = {'gif', 'apng', 'webp'};
    return liveExtensions.contains(ext) || animatedExtensions.contains(ext);
  }

  /// Download URL for the live photo companion video, if available
  String? get livePhotoVideoUrl =>
      livePhotoVideoId != null ? DsmApi().fotoDownloadUrl(livePhotoVideoId!) : null;

  String thumbnailUrl({int size = 1, bool useTeamApi = false}) {
    if (useTeamApi) {
      return DsmApi().fotoTeamThumbnailUrl(unitId ?? id, size: size, cacheKey: cacheKey);
    }
    return DsmApi().fotoThumbnailUrl(unitId ?? id, size: size, cacheKey: cacheKey);
  }

  String get downloadUrl => DsmApi().fotoDownloadUrl(id);

  /// 视频播放优先使用的转码流 URL（低码率、更流畅）。播放失败时应回退到
  /// [downloadUrl] 播放原始文件。
  String get videoStreamUrl => DsmApi().fotoStreamingUrl(id);

  /// Format taken time as date string
  String get dateString {
    if (time == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(time * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String get dateGroupKey {
    if (time == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(time * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

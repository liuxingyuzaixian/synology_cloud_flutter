import '../network/dsm_api.dart';

/// File/Folder model parsed from DSM FileStation API response
class FileModel {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int atime;
  final int mtime;
  final int ctime;
  final Map<String, dynamic>? perm;
  final String? realPath;
  final String? mountPointType;

  FileModel({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.atime = 0,
    this.mtime = 0,
    this.ctime = 0,
    this.perm,
    this.realPath,
    this.mountPointType,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) {
    final additional = json['additional'] as Map<String, dynamic>? ?? {};
    final time = additional['time'] as Map<String, dynamic>? ?? {};
    final perm = additional['perm'] as Map<String, dynamic>?;

    return FileModel(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      isDir: json['isdir'] == true,
      size: (additional['size'] as num?)?.toInt() ?? 0,
      atime: (time['atime'] as num?)?.toInt() ?? 0,
      mtime: (time['mtime'] as num?)?.toInt() ?? 0,
      ctime: (time['ctime'] as num?)?.toInt() ?? 0,
      perm: perm,
      realPath: additional['real_path'] as String?,
      mountPointType: additional['mount_point_type'] as String?,
    );
  }

  /// File type determined by extension
  FileTypeEnum get fileType =>
      isDir ? FileTypeEnum.folder : DsmApi.fileType(name);

  /// Formatted file size
  String get sizeText =>
      isDir ? '--' : DsmApi.formatSize(size);

  /// Formatted modification time
  String get modifiedTimeText {
    if (mtime == 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(mtime * 1000);
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Parent directory path
  String get parentPath {
    final parts = path.split('/');
    if (parts.length <= 2) return '/';
    parts.removeLast();
    return parts.join('/');
  }
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_preferences.dart';

/// Backup status for each file
class BackupFileState {
  final String filePath;
  final String fileName;
  final BackupStatus status;
  final double progress;

  BackupFileState({
    required this.filePath,
    required this.fileName,
    this.status = BackupStatus.pending,
    this.progress = 0,
  });

  BackupFileState copyWith({BackupStatus? status, double? progress}) =>
      BackupFileState(filePath: filePath, fileName: fileName, status: status ?? this.status, progress: progress ?? this.progress);
}

enum BackupStatus { pending, checking, uploading, done, skipped, failed }

/// Photo backup service — mirrors Synology Photos mobile backup flow.
class PhotoBackupService {
  PhotoBackupService._();

  // ---- settings keys ----
  static const kEnabledKey = 'photo_backup_enabled';
  static const kLastBackupKey = 'photo_backup_last_time';
  static const kTargetFolderKey = 'photo_backup_target_folder';
  static const kWifiOnlyKey = 'photo_backup_wifi_only';
  static const kBackedUpHashesKey = 'photo_backup_hashes';

  static bool get enabled => AppPreferences.getBool(kEnabledKey);
  static set enabled(bool v) => AppPreferences.putBool(kEnabledKey, v);

  static String get targetFolder => AppPreferences.getString(kTargetFolderKey, defaultValue: 'MobileBackup');
  static set targetFolder(String v) => AppPreferences.putString(kTargetFolderKey, v);

  static bool get wifiOnly => AppPreferences.getBool(kWifiOnlyKey);
  static set wifiOnly(bool v) => AppPreferences.putBool(kWifiOnlyKey, v);

  static String get _backedUpHashes => AppPreferences.getString(kBackedUpHashesKey);
  static set _backedUpHashes(String v) => AppPreferences.putString(kBackedUpHashesKey, v);

  static Set<String> get backedUpHashes => _backedUpHashes.split(',').where((e) => e.isNotEmpty).toSet();
  static void markBackedUp(String hash) {
    final s = backedUpHashes;
    s.add(hash);
    _backedUpHashes = s.join(',');
  }

  /// Compute MD5 hash of a file (same as Synology Photos uses)
  static Future<String> fileHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString().toUpperCase();
  }

  /// Get the subfolder path based on file date (e.g. ["DCIM","Camera","2026","07"])
  static List<String> defaultSubfolder(int mtime) {
    final dt = DateTime.fromMillisecondsSinceEpoch(mtime * 1000);
    return ['DCIM', 'Camera', dt.year.toString(), dt.month.toString().padLeft(2, '0')];
  }

  /// Backup a single file: check → upload → mark
  static Future<BackupStatus> backupFile({
    required String filePath,
    required String fileName,
    required int mtime,
    required List<String> targetFolderPath,
    required List<String> subfolder,
    required void Function(double) onProgress,
  }) async {
    // Compute hash
    final hash = await fileHash(filePath);
    if (hash.isEmpty) return BackupStatus.failed;

    // Check if already backed up (local record)
    if (backedUpHashes.contains(hash)) return BackupStatus.skipped;

    // Check with server
    final checkRes = await DsmApi().fotoBackupCheck([
      {'hash_code': hash, 'name': [fileName, fileName], 'takentime': mtime}
    ]);
    if (checkRes['success'] != true) return BackupStatus.failed;
    final list = checkRes['data']?['list'] as List? ?? [];
    if (list.isNotEmpty && list[0]['new'] == false) {
      markBackedUp(hash);
      return BackupStatus.skipped;
    }

    // Generate thumbnails
    final thumbSm = await _generateThumb(filePath, 120);
    final thumbXl = await _generateThumb(filePath, 800);

    onProgress(0.1); // thumbnails done

    // Upload
    await DsmApi().fotoBackupUpload(
      filePath: filePath,
      fileName: fileName,
      mtime: mtime,
      targetFolderPath: targetFolderPath,
      subfolder: subfolder,
      similarHash: hash,
      thumbSmPath: thumbSm,
      thumbXlPath: thumbXl,
    );

    markBackedUp(hash);
    onProgress(1.0);
    return BackupStatus.done;
  }

  /// Generate a small thumbnail copy using file copy (NAS will handle actual thumbnail gen)
  static Future<String?> _generateThumb(String srcPath, int maxSize) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = srcPath.hashCode.toString();
      final thumbFile = File('${dir.path}/thumb_${name}_$maxSize.jpg');
      // For images, just copy the original — NAS generates thumbnails server-side
      // The API expects placeholder files for thumb_sm/thumb_xl
      await File(srcPath).copy(thumbFile.path);
      return thumbFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Pick photos from gallery and backup
  static Future<void> pickAndBackup(BuildContext context) async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty) return;

    final targetFolder = [PhotoBackupService.targetFolder];

    // ignore: use_build_context_synchronously
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BackupProgressPage(files: files, targetFolder: targetFolder),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backup Progress Page
// ---------------------------------------------------------------------------
class _BackupProgressPage extends StatefulWidget {
  final List<XFile> files;
  final List<String> targetFolder;

  const _BackupProgressPage({required this.files, required this.targetFolder});

  @override
  State<_BackupProgressPage> createState() => _BackupProgressPageState();
}

class _BackupProgressPageState extends State<_BackupProgressPage> {
  late List<BackupFileState> _states;
  int _done = 0;
  int _failed = 0;

  @override
  void initState() {
    super.initState();
    _states = widget.files.map((f) => BackupFileState(
      filePath: f.path,
      fileName: f.name,
    )).toList();
    _startBackup();
  }

  Future<void> _startBackup() async {
    for (int i = 0; i < _states.length; i++) {
      if (!mounted) return;
      final state = _states[i];
      setState(() => _states[i] = state.copyWith(status: BackupStatus.checking));

      final file = File(state.filePath);
      final stat = await file.stat();
      final mtime = stat.modified.millisecondsSinceEpoch ~/ 1000;

      final status = await PhotoBackupService.backupFile(
        filePath: state.filePath,
        fileName: state.fileName,
        mtime: mtime,
        targetFolderPath: widget.targetFolder,
        subfolder: PhotoBackupService.defaultSubfolder(mtime),
        onProgress: (p) {
          if (mounted) setState(() => _states[i] = _states[i].copyWith(progress: p));
        },
      );

      if (!mounted) return;
      setState(() {
        _states[i] = _states[i].copyWith(status: status);
        if (status == BackupStatus.done) _done++;
        if (status == BackupStatus.failed) _failed++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _states.length;
    final completed = _done + _failed;
    return Scaffold(
      appBar: AppBar(title: const Text('照片备份')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(value: total > 0 ? completed / total : 0),
                const SizedBox(height: 8),
                Text('$completed / $total  成功$_done  失败$_failed'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: total,
              itemBuilder: (_, i) {
                final s = _states[i];
                final icon = switch (s.status) {
                  BackupStatus.pending => Icons.hourglass_empty,
                  BackupStatus.checking => Icons.sync,
                  BackupStatus.uploading => Icons.cloud_upload,
                  BackupStatus.done => Icons.check_circle,
                  BackupStatus.skipped => Icons.skip_next,
                  BackupStatus.failed => Icons.error,
                };
                final color = switch (s.status) {
                  BackupStatus.done => Colors.green,
                  BackupStatus.failed => Colors.red,
                  BackupStatus.skipped => Colors.grey,
                  _ => Colors.orange,
                };
                return ListTile(
                  leading: Icon(icon, color: color),
                  title: Text(s.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: s.status == BackupStatus.uploading
                      ? LinearProgressIndicator(value: s.progress > 0 ? s.progress : null)
                      : Text(s.status.name),
                  dense: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

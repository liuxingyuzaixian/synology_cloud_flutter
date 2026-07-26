import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_preferences.dart';
import '../components/app_dialog.dart';

/// 更新 manifest 地址（按平台区分）
const kUpdateJsonUrlAndroid = 'http://zhanglei.nasfuns.fun:8083/artifactory/synology_cloud/app_update_android.json';
const kUpdateJsonUrlIos = 'http://zhanglei.nasfuns.fun:8083/artifactory/synology_cloud/app_update_ios.json';
const kUpdateLastCheckKey = 'update_last_check_date';
const kUpdateCachedManifestKey = 'update_cached_manifest';

class UpdateService {
  UpdateService._();

  /// 上次成功拉取的 manifest（本地缓存），解析失败返回 null
  static Map<String, dynamic>? _cachedManifest() {
    final s = AppPreferences.getString(kUpdateCachedManifestKey);
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static int _cachedMinBuild() =>
      ((_cachedManifest()?['minBuildNumber']) as num?)?.toInt() ?? 0;

  /// 检查更新，force = true 跳过日检测限制
  static Future<void> checkForUpdate(BuildContext context, {bool force = false}) async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    // 非强制模式下，检查频率由 auto_check_update 开关控制；
    // 但缓存 manifest 表明当前版本需强更时不受频率限制，防止重启绕过强更
    if (!force && _cachedMinBuild() <= currentBuild) {
      final alwaysCheck = AppPreferences.getBool('auto_check_update');
      if (!alwaysCheck) {
        // 关闭开关 = 每天仅检查一次
        final lastCheck = AppPreferences.getString(kUpdateLastCheckKey);
        final today = DateTime.now().toIso8601String().substring(0, 10);
        if (lastCheck == today) {
          debugPrint('[Update] 今天已检查过更新，跳过');
          return;
        }
      }
      // 无论开关，记录本次检查日期
      AppPreferences.putString(kUpdateLastCheckKey, DateTime.now().toIso8601String().substring(0, 10));
    }

    Map<String, dynamic> data;
    try {
      final jsonUrl = Platform.isAndroid ? kUpdateJsonUrlAndroid : kUpdateJsonUrlIos;
      final res = await Dio().get<String>(jsonUrl);
      data = jsonDecode(res.data as String) as Map<String, dynamic>;
      // 缓存 manifest：下次启动即使断网/被限流，也能依据它拦截强更
      AppPreferences.putString(kUpdateCachedManifestKey, res.data as String);
    } catch (e) {
      if (force) AppDialog.toast('检查更新失败: $e');
      debugPrint('[Update] 检查更新失败: $e');
      // 网络失败时回退本地缓存，仅用于强更兜底（普通更新提示不重复打扰）
      final cached = _cachedManifest();
      final cachedMin = ((cached?['minBuildNumber']) as num?)?.toInt() ?? 0;
      if (cached == null || currentBuild >= cachedMin) return;
      data = cached;
    }

    try {
      final latestVersion = data['version'] as String? ?? '';
      final latestBuild = (data['buildNumber'] as num?)?.toInt() ?? 0;
      final minBuild = (data['minBuildNumber'] as num?)?.toInt() ?? 0;
      final title = data['title'] as String? ?? '发现新版本';
      final content = data['content'] as String? ?? '';
      final androidUrl = data['androidUrl'] as String? ?? '';

      final forceUpdate = currentBuild < minBuild;

      if (latestBuild <= currentBuild && !forceUpdate) {
        if (force) AppDialog.toast('已是最新版本 $latestVersion');
        return;
      }

      if (context.mounted) {
        await _showUpdateDialog(
          context,
          title: title,
          content: content,
          currentVersion: info.version,
          currentBuild: currentBuild,
          latestVersion: latestVersion,
          latestBuild: latestBuild,
          forceUpdate: forceUpdate,
          androidUrl: androidUrl,
        );
      }
    } catch (e) {
      if (force) AppDialog.toast('检查更新失败: $e');
      debugPrint('[Update] 检查更新失败: $e');
    }
  }

  static Future<void> _showUpdateDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String currentVersion,
    required int currentBuild,
    required String latestVersion,
    required int latestBuild,
    required bool forceUpdate,
    required String androidUrl,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !forceUpdate,
        child: _UpdateDialogContent(
          title: title,
          content: content,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          latestVersion: latestVersion,
          latestBuild: latestBuild,
          forceUpdate: forceUpdate,
          androidUrl: androidUrl,
        ),
      ),
    );
  }

  static Future<void> _downloadWithProgress(
    BuildContext context,
    String url,
    bool forceUpdate,
  ) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) { AppDialog.toast('无法获取存储目录'); return; }
      final file = File('${dir.path}/synology_cloud_update.apk');

      // Show the update dialog with progress
      if (context.mounted) {
        Navigator.of(context).pop(); // close the first dialog
      }
      if (context.mounted) {
        _showProgressDialog(context, url, file, forceUpdate);
      }
    } catch (e) {
      AppDialog.toast('更新失败: $e');
    }
  }

  static void _showProgressDialog(BuildContext context, String url, File file, bool forceUpdate) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateProgressDialog(
        url: url,
        file: file,
        downloadUrl: url,
        forceUpdate: forceUpdate,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Update Dialog Content (仿享脉风格)
// ---------------------------------------------------------------------------
class _UpdateDialogContent extends StatelessWidget {
  final String title;
  final String content;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final bool forceUpdate;
  final String androidUrl;

  const _UpdateDialogContent({
    required this.title,
    required this.content,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.forceUpdate,
    required this.androidUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo at top-right area
          // Title
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Version info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('当前版本', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('v$currentVersion ($currentBuild)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward, size: 18, color: Colors.grey),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('最新版本', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('v$latestVersion ($latestBuild)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (forceUpdate) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.red),
                  SizedBox(width: 6),
                  Text('当前版本过低，请立即更新', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
          if (content.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                content,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      actions: [
        // Buttons in a Row (横排)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!forceUpdate)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('稍后', style: TextStyle(fontSize: 15)),
                ),
              if (!forceUpdate) const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  UpdateService._downloadWithProgress(context, androidUrl, forceUpdate);
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text('立即更新', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // "更新失败点击这里" 放在按钮下方
        GestureDetector(
          onTap: () async {
            if (androidUrl.isNotEmpty) {
              final uri = Uri.tryParse(androidUrl);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '更新失败点击这里',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Download Progress Dialog
// ---------------------------------------------------------------------------
class _UpdateProgressDialog extends StatefulWidget {
  final String url;
  final File file;
  final String downloadUrl;
  final bool forceUpdate;

  const _UpdateProgressDialog({
    required this.url,
    required this.file,
    required this.downloadUrl,
    required this.forceUpdate,
  });

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double _progress = 0;
  bool _isDownloading = true;
  bool _hasError = false;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    _cancelToken = CancelToken();
    try {
      await Dio().download(
        widget.downloadUrl,
        widget.file.path,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;
      setState(() => _isDownloading = false);
      // Close progress dialog
      Navigator.of(context).pop();
      AppDialog.toast('下载完成，正在安装...');
      await OpenFilex.open(widget.file.path, type: 'application/vnd.android.package-archive');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      if (mounted) setState(() => _hasError = true);
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 强更时禁止返回键关闭进度弹窗，防止绕过强更
    return PopScope(
      canPop: !widget.forceUpdate,
      child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.cloud, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            _hasError ? '更新失败' : (_isDownloading ? '正在下载...' : '下载完成'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (!_hasError) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
            ),
          ] else ...[
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const SizedBox(height: 8),
            const Text('下载失败，请重试', style: TextStyle(fontSize: 14, color: Colors.red)),
          ],
          const SizedBox(height: 4),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actions: [
        if (_hasError)
          FilledButton(
            onPressed: () {
              setState(() {
                _hasError = false;
                _progress = 0;
                _isDownloading = true;
              });
              _startDownload();
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('重新下载', style: TextStyle(fontSize: 15)),
          ),
        if (!_hasError && _isDownloading && !widget.forceUpdate)
          OutlinedButton(
            onPressed: () {
              _cancelToken?.cancel();
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('取消', style: TextStyle(fontSize: 15)),
          ),
      ],
      ),
    );
  }
}

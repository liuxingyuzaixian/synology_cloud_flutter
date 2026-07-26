import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Tunes libmpv for smooth NAS video streaming.
///
/// Design goals, driven by real device testing:
///  * No dropped frames — force hardware decoding and, if the network buffer
///    ever runs dry, briefly re-buffer instead of skipping frames.
///  * No black flash on entry — pre-buffer before the first frame while the
///    poster thumbnail (drawn behind the transparent [Video]) stays visible.
///  * Fast backward seek / replay within a session via the on-disk demuxer
///    cache. (Cross-session replay is handled separately by VideoCache, which
///    plays a fully-downloaded local file with no buffering at all.)
class MediaCache {
  MediaCache._();

  static String? _cacheDir;

  /// Apply streaming/cache mpv properties to the given player.
  ///
  /// Must be called before [Player.open]. No-op on platforms whose backend
  /// is not the native libmpv player.
  static Future<void> configure(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      // Force hardware decoding. Software-decoding high-bitrate / 4K clips is
      // the usual cause of "severe frame drops" on mobile devices.
      await platform.setProperty('hwdec', 'auto-safe');

      // Auto-reconnect transient NAS/network drops instead of erroring out.
      await platform.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,'
            'reconnect_on_network_error=1,reconnect_delay_max=5',
      );

      // Built-in on-disk demuxer cache so seeking backwards within the current
      // session does not re-download.
      _cacheDir ??= await _initDir();
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('cache-on-disk', 'yes');
      if (_cacheDir != null) {
        await platform.setProperty('cache-dir', _cacheDir!);
      }

      // Large forward read-ahead cushion so the stream banks data during easy
      // moments and coasts through slow ones.
      await platform.setProperty('cache-secs', '120');
      await platform.setProperty('demuxer-readahead-secs', '60');
      await platform.setProperty('demuxer-max-bytes', '256MiB');
      await platform.setProperty('demuxer-max-back-bytes', '64MiB');

      // Prefer a short re-buffer over dropping frames. Pre-buffer before the
      // first frame (hidden behind the poster thumbnail); if the buffer runs
      // dry mid-play, pause briefly to refill rather than skipping frames.
      await platform.setProperty('cache-pause', 'yes');
      await platform.setProperty('cache-pause-initial', 'yes');
      await platform.setProperty('cache-pause-wait', '2');
    } catch (_) {
      // Cache tuning is best-effort; ignore failures on unsupported backends.
    }
  }

  /// Start recording the *currently streamed* bytes to [partPath] using mpv's
  /// `stream-record`. This reuses the data the player is already downloading,
  /// so it adds no extra network load. Best-effort; a no-op if unsupported.
  static Future<void> startRecording(Player player, String partPath) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('stream-record', partPath);
    } catch (_) {}
  }

  /// Stop / flush an in-progress recording.
  static Future<void> stopRecording(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('stream-record', '');
    } catch (_) {}
  }

  static Future<String?> _initDir() async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/mpv_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    } catch (_) {
      return null;
    }
  }
}

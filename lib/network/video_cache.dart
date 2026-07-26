import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent, cross-session video cache shared across the preview page and
/// slideshow.
///
/// libmpv's own `cache-on-disk` is only a transient demuxer spill file that is
/// deleted when the clip is closed, so it cannot make a *replay* start
/// instantly.
///
/// Rather than downloading each clip a second time (a parallel download
/// competes with the player for the same NAS bandwidth and makes playback
/// stutter / re-buffer mid-clip), we let the player itself persist the bytes
/// it is *already* downloading via mpv's `stream-record`. Recording costs zero
/// extra bandwidth. It writes to a `.part` file while streaming; on natural
/// end-of-file the `.part` is promoted to the final cache file. On the next
/// play the player opens that local file directly — no network, no buffering.
///
/// A Matroska (`.mkv`) container is used for the recording because it can
/// re-mux essentially any codec the source uses without transcoding.
class VideoCache {
  VideoCache._();

  static Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/video_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _key(String url) => 'vc_${url.hashCode}.mkv';

  /// Final (fully recorded) cache file for a video URL.
  static Future<File> file(String url) async =>
      File('${(await _dir()).path}/${_key(url)}');

  /// In-progress recording file for a video URL.
  static Future<File> partFile(String url) async =>
      File('${(await _dir()).path}/${_key(url)}.part');

  /// Local path if the clip is fully cached, else null (caller streams).
  static Future<String?> cachedPath(String url) async {
    try {
      final f = await file(url);
      if (await f.exists() && await f.length() > 0) return f.path;
    } catch (_) {}
    return null;
  }

  /// Promote a completed `.part` recording to the final cache file. Call this
  /// only once the clip has played through to its natural end.
  static Future<void> finalize(String url) async {
    try {
      final part = await partFile(url);
      if (!await part.exists() || await part.length() <= 0) return;
      final f = await file(url);
      if (await f.exists()) await f.delete();
      await part.rename(f.path);
    } catch (_) {}
  }

  /// Delete a stale/incomplete `.part` recording (e.g. the user left before
  /// the clip finished, so the recording is not usable).
  static Future<void> discardPart(String url) async {
    try {
      final part = await partFile(url);
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }
}

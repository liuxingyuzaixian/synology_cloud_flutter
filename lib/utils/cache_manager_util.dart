import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// 图片/视频缓存统计与清理
///
/// 缓存目录（均位于系统临时目录下）：
///  * 图片：`cached_network_image_ce`（cached_network_image_ce 磁盘缓存）
///  * 视频：`video_cache`（VideoCache 跨会话缓存）、`mpv_cache`（libmpv 会话内 demuxer 缓存）
class CacheManagerUtil {
  CacheManagerUtil._();

  static const _imageCacheDir = 'cached_network_image_ce';
  static const _videoCacheDirs = ['video_cache', 'mpv_cache'];

  /// 图片缓存大小（字节）
  static Future<int> imageCacheSize() async {
    final tmp = await getTemporaryDirectory();
    return _dirSize(Directory('${tmp.path}/$_imageCacheDir'));
  }

  /// 视频缓存大小（字节）
  static Future<int> videoCacheSize() async {
    final tmp = await getTemporaryDirectory();
    int total = 0;
    for (final name in _videoCacheDirs) {
      total += await _dirSize(Directory('${tmp.path}/$name'));
    }
    return total;
  }

  /// 图片 + 视频缓存总大小（字节）
  static Future<int> totalCacheSize() async {
    return await imageCacheSize() + await videoCacheSize();
  }

  /// 清理图片和视频缓存
  static Future<void> clearCache() async {
    // 图片磁盘缓存（使用组件内共享的单例，避免文件句柄冲突）
    try {
      await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
    } catch (_) {}

    // 内存中的图片缓存一并清理
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // 视频缓存目录
    final tmp = await getTemporaryDirectory();
    for (final name in _videoCacheDirs) {
      final dir = Directory('${tmp.path}/$name');
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }

    // 图片缓存目录兜底删除（emptyCache 保留空目录结构，不影响后续使用）
    final imageDir = Directory('${tmp.path}/$_imageCacheDir');
    try {
      if (await imageDir.exists()) {
        await for (final entity in imageDir.list(followLinks: false)) {
          // hive 元数据文件由 emptyCache 维护，只清理残留的图片文件
          if (entity is File && !entity.path.contains('hive')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// 递归统计目录大小
  static Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }
}

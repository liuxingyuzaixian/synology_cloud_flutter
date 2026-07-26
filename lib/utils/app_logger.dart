import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../network/license_api.dart';

/// 应用日志收集器：缓存最近 N 条日志，支持一键上传到后端供排查。
///
/// 使用方式：
/// ```dart
/// AppLogger.d('License', '刷新权益结果: $info');
/// AppLogger.section('权益校验');
/// ```
class AppLogger {
  AppLogger._();

  static const int maxEntries = 500;
  static final ListQueue<_LogEntry> _buffer = ListQueue<_LogEntry>(maxEntries);

  /// Debug 级别
  static void d(String tag, String message) {
    _add('D', tag, message);
  }

  /// Warning 级别
  static void w(String tag, String message) {
    _add('W', tag, message);
  }

  /// Error 级别
  static void e(String tag, String message) {
    _add('E', tag, message);
  }

  /// 流程分隔线，帮助阅读日志时区分不同事件
  static void section(String title) {
    _add('I', '────', '═══ $title ═══');
  }

  static void _add(String level, String tag, String message) {
    final entry = _LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );
    if (_buffer.length >= maxEntries) _buffer.removeFirst();
    _buffer.add(entry);
    // 同步输出到 debugPrint，方便本地调试
    debugPrint('[$level/$tag] $message');
  }

  /// 获取所有缓存日志（按时间正序）
  static List<String> getAll() {
    return _buffer.map((e) => e.format()).toList();
  }

  /// 清空日志缓存
  static void clear() => _buffer.clear();

  /// 上传日志到后端（POST /api/device/upload-log）
  /// 返回是否成功。
  static Future<bool> upload({String? deviceId, String? remark}) async {
    try {
      final logs = getAll();
      if (logs.isEmpty) return true;
      final body = {
        'deviceId': deviceId ?? 'unknown',
        'remark': remark ?? '',
        'logs': logs,
        'uploadTime': DateTime.now().toIso8601String(),
      };
      final dio = Dio(BaseOptions(
        baseUrl: LicenseApi.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final resp = await dio.post('/device/upload-log',
          data: jsonEncode(body),
          options: Options(headers: {'Content-Type': 'application/json'}));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[AppLogger] upload failed: $e');
      return false;
    }
  }
}

class _LogEntry {
  _LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });

  final DateTime time;
  final String level;
  final String tag;
  final String message;

  String format() {
    final ts = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
    return '$ts [$level/$tag] $message';
  }
}

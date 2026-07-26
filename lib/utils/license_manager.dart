import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/license_info.dart';
import '../network/dsm_api.dart';
import '../network/license_api.dart';
import 'app_logger.dart';
import 'app_preferences.dart';

/// 权益管理单例：负责登录后检测、缓存、离线宽限、域名放行判定。
///
/// 设计见 docs/付费权益系统设计方案.md §5.3 / §5.4。
/// - 管理员：读 serial/model/mac/hostname → /device/register；
/// - 普通用户：仅域名 → /device/queryByDomain；
/// - 后端不可达时按缓存 + 72h 宽限放行，避免误伤付费用户。
class LicenseManager {
  LicenseManager._();

  factory LicenseManager() => _instance;

  static final LicenseManager _instance = LicenseManager._();

  static const _cacheKey = 'license_cache';
  static const _allowDomainsKey = 'license_allow_domains';

  /// 缓存有效期：期内不重复请求后端。
  static const cacheTtl = Duration(hours: 1);

  /// 离线宽限：后端不可达时，缓存 ACTIVE 允许继续使用的时长（§5.4）。
  static const graceDuration = Duration(hours: 72);

  /// 当前设备是否被识别为管理员（能读到 serial）。
  bool isAdmin = false;

  /// 最近一次权益结果（可能来自网络或缓存）。
  final ValueNotifier<LicenseInfo?> license = ValueNotifier<LicenseInfo?>(null);

  LicenseInfo? get current => license.value;

  String? get deviceId => current?.deviceId;

  /// 是否应拦截进入主功能。
  bool get shouldBlock => (current ?? const LicenseInfo()).shouldBlock;

  String get currentDomain => DsmApi().server?.host ?? '';

  /// 登录成功后调用：检测当前设备权益。
  ///
  /// [force] 为 false 时命中新鲜缓存直接返回，减少后端压力。
  Future<LicenseInfo> refresh({bool force = false}) async {
    final domain = currentDomain;
    AppLogger.d('License', 'refresh(force=$force) domain=$domain');

    if (!force) {
      final cached = _readFreshCache(domain);
      if (cached != null) {
        AppLogger.d('License', '→ 命中新鲜缓存: status=${cached.status}, banned=${cached.isBanned}');
        license.value = cached;
        return cached;
      }
    }

    try {
      final info = await _queryFromServer(domain);
      AppLogger.d('License', '→ 服务端响应: status=${info.status}, banned=${info.isBanned}, '
          'banReason=${info.banReason}, expire=${info.expireTime}');
      license.value = info;
      await _writeCache(info, domain);
      if (info.isActive && domain.isNotEmpty) {
        await _addAllowDomain(domain);
      } else if (domain.isNotEmpty) {
        await _removeAllowDomain(domain);
        AppLogger.d('License', '→ 非放行状态,已移除allow-domain');
      }
      return info;
    } catch (e) {
      AppLogger.w('License', '→ 服务端不可达: $e');
      final fallback = _readCacheWithGrace(domain);
      AppLogger.d('License', '→ 缓存宽限结果: status=${fallback.status}, banned=${fallback.isBanned}');
      license.value = fallback;
      return fallback;
    }
  }

  Future<LicenseInfo> _queryFromServer(String domain) async {
    final api = LicenseApi();
    final dsm = DsmApi();

    String serial = '';
    String model = '';
    String mac = '';
    String hostname = '';

    // 尝试读取硬件信息：能读到 serial 即视为管理员（§2.1）。
    try {
      final sys = await dsm.systemInfo();
      final sysData = (sys['data'] ?? {}) as Map;
      serial = (sysData['serial'] ?? '').toString();
      model = (sysData['model'] ?? '').toString();
      hostname = (sysData['hostname'] ?? '').toString();
    } catch (_) {}

    if (serial.isNotEmpty) {
      try {
        final net = await dsm.networkInfo();
        final netData = (net['data'] ?? {}) as Map;
        final nifs = (netData['nif'] as List?) ?? const [];
        mac = nifs
            .map((e) => (e is Map ? e['mac']?.toString() : null) ?? '')
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      } catch (_) {}
    }

    isAdmin = serial.isNotEmpty;

    if (isAdmin) {
      return api.registerDevice(
        serial: serial,
        model: model,
        mac: mac,
        hostname: hostname,
        domain: domain,
      );
    }
    // 普通用户：仅按域名查询。
    if (domain.isEmpty) return const LicenseInfo();
    return api.queryByDomain(domain);
  }

  /// 申请试用后刷新。
  Future<LicenseInfo> applyTrial() async {
    final id = deviceId;
    if (id == null) {
      throw StateError('设备未识别，无法申请试用');
    }
    final info = await LicenseApi().applyTrial(id);
    // 试用接口可能只回 expireTime，这里补齐 deviceId/status。
    final merged = info.copyWith(
      deviceId: info.deviceId ?? id,
      status: info.status == LicenseInfo.statusUnknown
          ? LicenseInfo.statusActive
          : info.status,
    );
    license.value = merged;
    await _writeCache(merged, currentDomain);
    if (merged.isActive && currentDomain.isNotEmpty) {
      await _addAllowDomain(currentDomain);
    }
    return merged;
  }

  // ==================== 缓存 & 宽限 ====================

  LicenseInfo? _readFreshCache(String domain) {
    final raw = _readCacheRaw();
    if (raw == null) return null;
    if (raw.domain != domain) return null;
    final checkedAt = raw.checkedAt;
    if (checkedAt == null) return null;
    if (DateTime.now().difference(checkedAt) > cacheTtl) return null;
    return raw.info;
  }

  /// 后端不可达时的兜底：命中放行域名或缓存 ACTIVE 且在宽限内 → 放行。
  LicenseInfo _readCacheWithGrace(String domain) {
    final raw = _readCacheRaw();
    // 缓存明确为封禁/过期时以缓存为准（不被 allow-domain 误放行），
    // 保证服务器曾判定异常后即便离线也持续拦截。
    if (raw != null && raw.domain == domain) {
      final cached = raw.info;
      if (cached.isBanned ||
          cached.status == LicenseInfo.statusExpired) {
        return cached;
      }
    }
    // 放行域名缓存优先（贴合「域名彻底放行」）。
    if (domain.isNotEmpty && _allowDomains().contains(domain)) {
      return const LicenseInfo(status: LicenseInfo.statusActive, type: 'CACHE');
    }
    if (raw == null) return const LicenseInfo();
    final info = raw.info;
    if (raw.domain == domain && info.isActive) {
      // FOREVER 或未到期直接放行。
      if (info.isForever) return info;
      final expire = info.expireTime;
      final checkedAt = raw.checkedAt;
      final withinExpire = expire == null || expire.isAfter(DateTime.now());
      final withinGrace = checkedAt != null &&
          DateTime.now().difference(checkedAt) <= graceDuration;
      if (withinExpire && withinGrace) return info;
    }
    // 无法验证：返回 UNKNOWN（不主动拦截），交由上层结合缓存展示提示。
    return const LicenseInfo();
  }

  _CacheEntry? _readCacheRaw() {
    final str = AppPreferences.getString(_cacheKey);
    if (str.isEmpty) return null;
    try {
      final map = jsonDecode(str) as Map<String, dynamic>;
      return _CacheEntry(
        info: LicenseInfo.fromJson(map),
        domain: (map['domain'] ?? '').toString(),
        checkedAt: DateTime.tryParse((map['checkedAt'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(LicenseInfo info, String domain) async {
    final map = info.toJson()
      ..['domain'] = domain
      ..['checkedAt'] = DateTime.now().toIso8601String();
    await AppPreferences.putString(_cacheKey, jsonEncode(map));
  }

  List<String> _allowDomains() {
    final str = AppPreferences.getString(_allowDomainsKey);
    if (str.isEmpty) return const [];
    try {
      return (jsonDecode(str) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _addAllowDomain(String domain) async {
    final set = _allowDomains().toSet()..add(domain);
    await AppPreferences.putString(_allowDomainsKey, jsonEncode(set.toList()));
  }

  Future<void> _removeAllowDomain(String domain) async {
    final set = _allowDomains().toSet()..remove(domain);
    await AppPreferences.putString(_allowDomainsKey, jsonEncode(set.toList()));
  }

  /// 退出登录时清理内存态（缓存保留用于宽限）。
  void reset() {
    license.value = null;
    isAdmin = false;
  }
}

class _CacheEntry {
  _CacheEntry({required this.info, required this.domain, this.checkedAt});

  final LicenseInfo info;
  final String domain;
  final DateTime? checkedAt;
}

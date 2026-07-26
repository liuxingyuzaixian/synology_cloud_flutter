/// 权益信息模型（对应后端 /device/register、/device/queryByDomain、/license/status 返回）
///
/// 设计见 docs/付费权益系统设计方案.md §2、§3。
class LicenseInfo {
  const LicenseInfo({
    this.deviceId,
    this.status = statusUnknown,
    this.type,
    this.expireTime,
    this.isNew = false,
    this.banReason,
  });

  /// 服务端生成的永久设备标识；普通用户域名未命中时为 null。
  final String? deviceId;

  /// ACTIVE / EXPIRED / NONE / UNKNOWN / BANNED。
  final String status;

  /// TRIAL / BUY / FOREVER / GIFT。
  final String? type;

  /// 到期时间；FOREVER 为 null。
  final DateTime? expireTime;

  /// 本次注册是否新建设备。
  final bool isNew;

  /// 设备被封禁时的原因（status==BANNED 时有值）。
  final String? banReason;

  static const statusActive = 'ACTIVE';
  static const statusExpired = 'EXPIRED';
  static const statusNone = 'NONE';
  static const statusUnknown = 'UNKNOWN';
  static const statusBanned = 'BANNED';

  bool get isActive => status == statusActive;

  bool get isForever => (type ?? '').toUpperCase() == 'FOREVER';

  /// 是否被封禁：封禁期间 App 完全不可用（含试用）。
  bool get isBanned => status == statusBanned;

  /// 是否应拦截：已识别到 deviceId 且无有效权益（NONE/EXPIRED），或设备被封禁（BANNED）。
  /// UNKNOWN（未识别设备，通常是普通用户域名未命中）一律不拦截，避免误伤。
  bool get shouldBlock =>
      deviceId != null &&
      (status == statusNone ||
          status == statusExpired ||
          status == statusBanned);

  LicenseInfo copyWith({
    String? deviceId,
    String? status,
    String? type,
    DateTime? expireTime,
    bool? isNew,
    String? banReason,
  }) {
    return LicenseInfo(
      deviceId: deviceId ?? this.deviceId,
      status: status ?? this.status,
      type: type ?? this.type,
      expireTime: expireTime ?? this.expireTime,
      isNew: isNew ?? this.isNew,
      banReason: banReason ?? this.banReason,
    );
  }

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    return LicenseInfo(
      deviceId: json['deviceId']?.toString(),
      status: (json['status'] ?? json['licenseStatus'] ?? statusUnknown).toString(),
      type: json['type']?.toString(),
      expireTime: _parseTime(json['expireTime']),
      isNew: json['isNew'] == true,
      banReason: json['banReason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'status': status,
        'type': type,
        'expireTime': expireTime?.toIso8601String(),
        'isNew': isNew,
        'banReason': banReason,
      };

  static DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    // 兼容 "2026-12-31 23:59:59" 与 ISO8601。
    return DateTime.tryParse(str.replaceFirst(' ', 'T')) ?? DateTime.tryParse(str);
  }

  @override
  String toString() =>
      'LicenseInfo(deviceId: $deviceId, status: $status, type: $type, expire: $expireTime)';
}

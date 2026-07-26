/// 套餐模型（对应后端 /config/plans / product_plan 表）
///
/// 设计见 docs/付费权益系统设计方案.md §3.1.1、§7 product_plan。
class PlanInfo {
  const PlanInfo({
    required this.code,
    required this.name,
    required this.price,
    required this.days,
    required this.licenseType,
  });

  /// WEEK / MONTH / QUARTER / YEAR / FOREVER。
  final String code;

  /// 周卡 / 月卡 / 季卡 / 年卡 / 买断。
  final String name;

  /// 价格（元）。
  final double price;

  /// 时长天数，-1 表示永久（买断）。
  final int days;

  /// BUY / FOREVER。
  final String licenseType;

  bool get isForever => days < 0 || licenseType.toUpperCase() == 'FOREVER';

  factory PlanInfo.fromJson(Map<String, dynamic> json) {
    return PlanInfo(
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      price: _toDouble(json['price']),
      days: _toInt(json['days']),
      licenseType: (json['licenseType'] ?? json['license_type'] ?? 'BUY').toString(),
    );
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }
}

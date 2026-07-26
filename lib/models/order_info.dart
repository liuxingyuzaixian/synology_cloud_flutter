/// 订单模型（对应后端 /order/create、/order/paid-check、/order/status）
///
/// 设计见 docs/付费权益系统设计方案.md §4.3 订单状态机。
class OrderInfo {
  const OrderInfo({
    required this.orderId,
    this.status = statusCreated,
    this.qrCode,
    this.planCode,
    this.amount,
    this.payRemark,
  });

  final String orderId;

  /// CREATED / USER_PAID / WAIT_CONFIRM / CONFIRMED / COMPLETED / CANCELLED。
  final String status;

  /// 收款二维码地址。
  final String? qrCode;

  final String? planCode;

  /// 金额（元）。
  final double? amount;

  /// 付款备注（形如 `NAS-{orderId}`），用于人工对帐。
  final String? payRemark;

  static const statusCreated = 'CREATED';
  static const statusUserPaid = 'USER_PAID';
  static const statusWaitConfirm = 'WAIT_CONFIRM';
  static const statusConfirmed = 'CONFIRMED';
  static const statusCompleted = 'COMPLETED';
  static const statusCancelled = 'CANCELLED';

  /// 已发权益（终态）。
  bool get isCompleted => status == statusCompleted;

  /// 取消（终态）。
  bool get isCancelled => status == statusCancelled;

  /// 是否处于人工确认过程中（需要继续轮询）。
  bool get isPending =>
      status == statusUserPaid ||
      status == statusWaitConfirm ||
      status == statusConfirmed;

  bool get isTerminal => isCompleted || isCancelled;

  OrderInfo copyWith({String? status}) => OrderInfo(
        orderId: orderId,
        status: status ?? this.status,
        qrCode: qrCode,
        planCode: planCode,
        amount: amount,
        payRemark: payRemark,
      );

  factory OrderInfo.fromJson(Map<String, dynamic> json) {
    final orderId = (json['orderId'] ?? '').toString();
    return OrderInfo(
      orderId: orderId,
      status: (json['status'] ?? statusCreated).toString(),
      qrCode: json['qrCode']?.toString(),
      planCode: (json['plan'] ?? json['planCode'])?.toString(),
      amount: json['amount'] is num ? (json['amount'] as num).toDouble() : null,
      payRemark: (json['payRemark'] ?? (orderId.isEmpty ? null : 'NAS-$orderId'))?.toString(),
    );
  }
}

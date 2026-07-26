import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../network/license_api.dart';
import '../../utils/license_manager.dart';
import 'purchase_page.dart';

/// 「我的订单」页：展示本设备历史订单；被禁用的订单在卡片内逐单标红展示原因。
///
/// 数据来自后端 `GET /api/order/list?deviceId=`（见 OrderController）。
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  static const routeName = '/license/orders';

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final LicenseApi _api = LicenseApi();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final deviceId = LicenseManager().deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      setState(() {
        _loading = false;
        _error = '当前设备未识别，暂无订单记录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchOrders(deviceId);
      final rawOrders = (data['orders'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _orders = rawOrders
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '订单加载失败，请稍后重试';
      });
    }
  }

  String _statusText(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'CREATED':
        return '待付款';
      case 'USER_PAID':
      case 'WAIT_CONFIRM':
        return '待确认';
      case 'CONFIRMED':
        return '确认中';
      case 'COMPLETED':
        return '已完成';
      case 'CANCELLED':
        return '已取消';
      case 'REVOKED':
        return '已禁用';
      default:
        return status ?? '-';
    }
  }

  Color _statusColor(String? status, ThemeData theme) {
    switch ((status ?? '').toUpperCase()) {
      case 'COMPLETED':
        return Colors.green;
      case 'CANCELLED':
        return theme.hintColor;
      case 'REVOKED':
        return Colors.red;
      case 'USER_PAID':
      case 'WAIT_CONFIRM':
      case 'CONFIRMED':
        return Colors.orange;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的订单'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _hint(theme, Icons.info_outline, _error!);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          if (_orders.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 80.h),
              child: _hint(theme, Icons.receipt_long_outlined, '暂无订单记录'),
            )
          else
            ..._orders.map((o) => _orderCard(theme, o)),
        ],
      ),
    );
  }

  Widget _orderCard(ThemeData theme, Map<String, dynamic> o) {
    final status = o['status']?.toString();
    final planName = (o['planName'] ?? o['planCode'] ?? '-').toString();
    final amount = o['amount'];
    final orderId = (o['orderId'] ?? '-').toString();
    final createdTime = (o['createdTime'] ?? '-').toString();
    final payRemark = o['payRemark']?.toString();
    final payProofUrl = o['payProofUrl']?.toString();
    final revoked = o['revoked'] == true;
    final revokeReason = o['revokeReason']?.toString();
    final revokeTime = o['revokeTime']?.toString();
    // 待付款订单可点击，跳转购买权益页完成付款闭环。
    final canPay = (status ?? '').toUpperCase() == 'CREATED';

    final card = Card(
      margin: EdgeInsets.only(bottom: 12.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(planName,
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: _statusColor(status, theme).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(_statusText(status),
                      style: TextStyle(
                          fontSize: 12.sp,
                          color: _statusColor(status, theme),
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            _kv(theme, '金额', amount == null ? '-' : '¥$amount'),
            _kv(theme, '订单号', orderId),
            if (payRemark != null && payRemark.isNotEmpty)
              _kv(theme, '付款备注', payRemark),
            _kv(theme, '下单时间', createdTime),
            if (payProofUrl != null && payProofUrl.isNotEmpty)
              _proofRow(theme, payProofUrl),
            if (revoked) _revokedBox(theme, revokeReason, revokeTime),
            if (canPay) ...[
              SizedBox(height: 10.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('点击去付款',
                      style: TextStyle(
                          fontSize: 12.sp,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right,
                      size: 18.w, color: theme.colorScheme.primary),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (!canPay) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(14.r),
      onTap: () => _goPay(orderId),
      child: card,
    );
  }

  /// 待付款订单→携带 orderId 跳购买权益页（继续原订单支付）；付款成功回来后刷新列表。
  Future<void> _goPay(String orderId) async {
    final ok = await Navigator.of(context).pushNamed(
      PurchasePage.routeName,
      arguments: {'orderId': orderId},
    );
    if (!mounted) return;
    if (ok == true) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } else {
      _load();
    }
  }

  /// 已完成订单的付款截图查看行
  Widget _proofRow(ThemeData theme, String payProofUrl) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 72.w,
            child: Text('付款凭证', style: TextStyle(fontSize: 13.sp, color: theme.hintColor)),
          ),
          GestureDetector(
            onTap: () => _showProofImage(payProofUrl),
            child: Text('点击查看',
                style: TextStyle(
                    fontSize: 13.sp,
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }

  void _showProofImage(String url) {
    // 图片路径为 /uploads/xxx.jpg，取服务器根地址拼接。
    final fullUrl = url.startsWith('http') ? url : '${LicenseApi.serverRoot}$url';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('付款凭证'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 400.h),
              child: InteractiveViewer(
                child: Image.network(
                  fullUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: EdgeInsets.all(24.w),
                    child: const Text('图片加载失败'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单张订单被禁用时的红色提示块（原因 + 时间）。
  Widget _revokedBox(ThemeData theme, String? reason, String? time) {
    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gpp_bad_outlined, color: Colors.red, size: 20.w),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('该订单已被管理员禁用',
                    style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.red)),
                SizedBox(height: 4.h),
                Text(
                  '原因：${(reason == null || reason.isEmpty) ? '未填写' : reason}',
                  style: TextStyle(fontSize: 12.sp, color: theme.colorScheme.onSurface),
                ),
                if (time != null && time.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text('时间：$time',
                      style: TextStyle(fontSize: 11.sp, color: theme.hintColor)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72.w,
            child: Text(label, style: TextStyle(fontSize: 13.sp, color: theme.hintColor)),
          ),
          Expanded(
            child: SelectableText(value, style: TextStyle(fontSize: 13.sp)),
          ),
        ],
      ),
    );
  }

  Widget _hint(ThemeData theme, IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48.w, color: theme.hintColor),
          SizedBox(height: 12.h),
          Text(text, style: TextStyle(fontSize: 14.sp, color: theme.hintColor)),
        ],
      ),
    );
  }
}

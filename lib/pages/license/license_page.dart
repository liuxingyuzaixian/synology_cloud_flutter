import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../models/license_info.dart';
import '../../utils/license_manager.dart';
import 'orders_page.dart';
import 'purchase_page.dart';

/// 「我的权益」详情页：展示当前状态/类型/到期时间，支持刷新与续费。
class LicenseDetailPage extends StatefulWidget {
  const LicenseDetailPage({super.key});

  static const routeName = '/license';

  @override
  State<LicenseDetailPage> createState() => _LicenseDetailPageState();
}

class _LicenseDetailPageState extends State<LicenseDetailPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await LicenseManager().refresh(force: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _goPurchase() async {
    // 路由框架统一生成 MaterialPageRoute<dynamic>，此处不能指定 <bool> 泛型，
    // 否则 pushNamed 内部 cast 为 Route<bool?> 会报错。返回值按 dynamic 接。
    final ok = await Navigator.of(context).pushNamed(PurchasePage.routeName);
    if (ok == true) {
      await _refresh();
      AppDialog.toast('权益已更新');
    }
  }

  void _goOrders() {
    Navigator.of(context).pushNamed(OrdersPage.routeName);
  }

  String _statusText(LicenseInfo info) {
    switch (info.status) {
      case LicenseInfo.statusActive:
        return '有效';
      case LicenseInfo.statusExpired:
        return '已过期';
      case LicenseInfo.statusNone:
        return '未开通';
      default:
        return '未识别';
    }
  }

  String _typeText(String? type) {
    switch ((type ?? '').toUpperCase()) {
      case 'TRIAL':
        return '免费试用';
      case 'BUY':
        return '时长套餐';
      case 'FOREVER':
        return '买断（永久）';
      case 'GIFT':
        return '赠送';
      default:
        return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的权益'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ValueListenableBuilder<LicenseInfo?>(
        valueListenable: LicenseManager().license,
        builder: (context, info, _) {
          // 首次加载（无任何缓存/结果）时展示页内局部 loading，
          // 避免刚进页就闪现「未开通」误导用户；不用全局弹窗以免阻塞操作。
          if (info == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  SizedBox(height: 16.h),
                  Text('正在加载权益信息...',
                      style: TextStyle(fontSize: 13.sp, color: theme.hintColor)),
                ],
              ),
            );
          }
          final license = info;
          final active = license.isActive;
          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                child: Padding(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            active ? Icons.verified : Icons.lock_outline,
                            color: active ? Colors.green : theme.hintColor,
                            size: 28.w,
                          ),
                          SizedBox(width: 10.w),
                          Text(
                            _statusText(license),
                            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      SizedBox(height: 16.h),
                      _row('类型', _typeText(license.type)),
                      _row(
                        '到期时间',
                        license.isForever
                            ? '永久'
                            : (license.expireTime
                                    ?.toLocal()
                                    .toString()
                                    .split('.')
                                    .first ??
                                '-'),
                      ),
                      _row('设备标识', license.deviceId ?? '未识别'),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _goPurchase,
                  style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                  child: Text(active ? '续费 / 升级' : '去购买'),
                ),
              ),
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _goOrders,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('我的订单'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88.w,
            child: Text(label, style: TextStyle(fontSize: 14.sp, color: theme.hintColor)),
          ),
          Expanded(
            child: SelectableText(value, style: TextStyle(fontSize: 14.sp)),
          ),
        ],
      ),
    );
  }
}

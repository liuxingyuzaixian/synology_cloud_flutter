import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../models/license_info.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_preferences.dart';
import '../../utils/license_manager.dart';
import 'banned_page.dart';
import 'purchase_page.dart';

/// 未付费 / 试用到期引导页（硬拦截时展示）。
///
/// 设计见 docs/付费权益系统设计方案.md §4.1 / §4.2。
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  static const routeName = '/license/paywall';

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 安全检查：若当前已是封禁状态，直接跳转 BannedPage（避免残留显示“权益到期”）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final info = LicenseManager().current;
      if (info != null && info.isBanned && mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(BannedPage.routeName, (route) => false);
      }
    });
  }

  Future<void> _applyTrial() async {
    setState(() => _busy = true);
    final close = AppDialog.showLoading(label: '正在申请试用...');
    try {
      final info = await LicenseManager().applyTrial();
      close();
      if (info.isActive) {
        AppDialog.toast('免费周卡已领取');
        _enterApp();
      } else {
        AppDialog.toast('领取未成功（免费周卡每设备仅限一次），请尝试购买');
      }
    } catch (e) {
      close();
      AppDialog.toast('领取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goPurchase() async {
    // 路由框架生成 MaterialPageRoute<dynamic>，不能指定 <bool> 泛型，否则 cast 报错。
    final ok = await Navigator.of(context).pushNamed(PurchasePage.routeName);
    if (ok == true) _enterApp();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final info = await LicenseManager().refresh(force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (info.isBanned) {
      // 被封禁→跳转用户状态异常页（展示禁用原因 + 申诉入口）。
      Navigator.of(context)
          .pushNamedAndRemoveUntil(BannedPage.routeName, (route) => false);
    } else if (info.isActive) {
      _enterApp();
    } else {
      AppDialog.toast('当前仍无有效权益');
    }
  }

  void _enterApp() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Future<void> _logout() async {
    final ok = await AppDialog.confirm(title: '退出登录', message: '确定退出当前账号吗？');
    if (!ok) return;
    try {
      await DsmApi().logout();
    } catch (_) {}
    AppPreferences.remove('sid');
    AppPreferences.remove('smid');
    LicenseManager().reset();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = LicenseManager().current ?? const LicenseInfo();
    final expired = info.status == LicenseInfo.statusExpired;
    final banned = info.isBanned;

    return Scaffold(
      appBar: AppBar(
        title: Text(banned ? '账号已被禁用' : '开通权益'),
        actions: [
          TextButton(onPressed: _busy ? null : _logout, child: const Text('退出登录')),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
          child: banned ? _buildBanned(theme, info) : _buildPaywall(theme, expired),
        ),
      ),
    );
  }

  /// 设备被封禁：完全不可用，仅提示原因，隐藏领取试用/购买入口。
  Widget _buildBanned(ThemeData theme, LicenseInfo info) {
    final reason = (info.banReason ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 24.h),
        Icon(Icons.block, size: 72.w, color: theme.colorScheme.error),
        SizedBox(height: 16.h),
        Text(
          '账号已被禁用',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: theme.colorScheme.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
          ),
          child: Text(
            reason.isEmpty
                ? '当前设备已被管理员禁用，App 暂时无法使用。如有疑问请联系管理员。'
                : '禁用原因：$reason\n如有疑问请联系管理员。',
            style: TextStyle(fontSize: 13.sp, color: theme.colorScheme.error, height: 1.5),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('刷新状态'),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  Widget _buildPaywall(ThemeData theme, bool expired) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 24.h),
        Icon(Icons.workspace_premium_outlined,
            size: 72.w, color: theme.colorScheme.primary),
        SizedBox(height: 16.h),
        Text(
          expired ? '试用/权益已到期' : '解锁全部功能',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8.h),
        Text(
          '本设备暂无有效权益。可先免费领取一张周卡（限一次），或选择套餐购买。\n权益绑定当前 NAS，同设备成员共享。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.sp, color: theme.hintColor, height: 1.5),
        ),
        const Spacer(),
        if (!expired)
          OutlinedButton(
            onPressed: _busy ? null : _applyTrial,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
            child: const Text('免费领取周卡（7 天·限一次）'),
          ),
        SizedBox(height: 12.h),
        FilledButton(
          onPressed: _busy ? null : _goPurchase,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: 14.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
          child: const Text('查看套餐并购买'),
        ),
        SizedBox(height: 12.h),
        TextButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('我已开通，刷新权益'),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }
}

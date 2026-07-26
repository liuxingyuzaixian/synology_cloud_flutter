import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../models/license_info.dart';
import '../../network/dsm_api.dart';
import '../../network/license_api.dart';
import '../../utils/app_logger.dart';
import '../../utils/app_preferences.dart';
import '../../utils/license_manager.dart';

/// 用户状态异常页（设备被封禁时硬跳转）：展示禁用原因 + 解封申诉入口。
///
/// 申诉状态机：无 / REJECTED → 可提交；PENDING → 等待管理员处理（不可重复提交）；
/// APPROVED → 已解封（刷新后自动进入 App）。见后端 AppealService。
class BannedPage extends StatefulWidget {
  const BannedPage({super.key});

  static const routeName = '/license/banned';

  @override
  State<BannedPage> createState() => _BannedPageState();
}

class _BannedPageState extends State<BannedPage> {
  final LicenseApi _api = LicenseApi();

  bool _busy = false;
  bool _loadingAppeal = true;
  Map<String, dynamic>? _appeal;

  @override
  void initState() {
    super.initState();
    _loadAppeal();
  }

  Future<void> _loadAppeal() async {
    final deviceId = LicenseManager().deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      setState(() => _loadingAppeal = false);
      return;
    }
    try {
      final data = await _api.appealStatus(deviceId);
      if (!mounted) return;
      setState(() {
        _appeal = data;
        _loadingAppeal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAppeal = false);
    }
  }

  bool get _canSubmit {
    // 无申诉记录，或上一条已被拒绝时可再次提交；PENDING 期间不可重复。
    final a = _appeal;
    if (a == null) return true;
    return a['canSubmit'] == true;
  }

  String? get _appealStatus => _appeal?['appealStatus']?.toString();

  Future<void> _submitAppeal() async {
    final deviceId = LicenseManager().deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      AppDialog.toast('当前设备未识别，无法提交申诉');
      return;
    }
    final reason = await _inputReason();
    if (reason == null) return;
    setState(() => _busy = true);
    final close = AppDialog.showLoading(label: '正在提交申诉...');
    try {
      final data = await _api.submitAppeal(deviceId, reason);
      close();
      if (!mounted) return;
      setState(() => _appeal = data);
      AppDialog.toast('申诉已提交，请等待管理员处理');
    } catch (e) {
      close();
      AppDialog.toast('提交失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _inputReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('申请解封'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: '请说明情况（如已完成付款、误操作等），便于管理员核实',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  AppDialog.toast('请填写申诉理由');
                  return;
                }
                Navigator.of(ctx).pop(text);
              },
              child: const Text('提交'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final info = await LicenseManager().refresh(force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!info.isBanned) {
      // 已解封：有权益进 App，无权益则去付费引导页。
      if (info.shouldBlock) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/license/paywall', (route) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } else {
      await _loadAppeal();
      AppDialog.toast('当前仍处于禁用状态');
    }
  }

  Future<void> _uploadLog() async {
    setState(() => _busy = true);
    try {
      final ok = await AppLogger.upload(
        deviceId: LicenseManager().deviceId,
        remark: '用户从BannedPage手动上传',
      );
      if (!mounted) return;
      AppDialog.toast(ok ? '日志已上传，感谢配合' : '上传失败，请检查网络');
    } catch (e) {
      if (!mounted) return;
      AppDialog.toast('上传失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final reason = (info.banReason ?? '').trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('账号状态异常'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _busy ? null : _logout,
              child: const Text('退出登录'),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 16.h),
                Icon(Icons.gpp_bad_outlined,
                    size: 72.w, color: theme.colorScheme.error),
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
                    border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    reason.isEmpty
                        ? '当前账号已被管理员禁用，App 暂时无法使用。你可以提交解封申诉，等待管理员核实处理。'
                        : '禁用原因：$reason',
                    style: TextStyle(
                        fontSize: 13.sp,
                        color: theme.colorScheme.error,
                        height: 1.5),
                  ),
                ),
                SizedBox(height: 16.h),
                _buildAppealSection(theme),
                const Spacer(),
                if (_canSubmit)
                  FilledButton(
                    onPressed: _busy ? null : _submitAppeal,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r)),
                    ),
                    child: Text(_appealStatus == 'REJECTED' ? '重新申请解封' : '申请解封'),
                  ),
                SizedBox(height: 12.h),
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('刷新状态'),
                ),
                SizedBox(height: 8.h),
                TextButton(
                  onPressed: _busy ? null : _uploadLog,
                  child: Text('上传诊断日志',
                      style: TextStyle(fontSize: 12.sp, color: theme.hintColor)),
                ),
                SizedBox(height: 12.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 申诉状态区：审核中 / 被拒绝提示。
  Widget _buildAppealSection(ThemeData theme) {
    if (_loadingAppeal) {
      return const Center(child: CircularProgressIndicator());
    }
    final status = _appealStatus;
    if (status == 'PENDING') {
      return _statusBox(
        theme,
        Icons.hourglass_top,
        Colors.orange,
        '申诉审核中',
        '你的解封申诉已提交，请耐心等待管理员处理，期间无法重复提交。',
      );
    }
    if (status == 'REJECTED') {
      final remark = (_appeal?['adminRemark'] ?? '').toString().trim();
      return _statusBox(
        theme,
        Icons.cancel_outlined,
        theme.colorScheme.error,
        '申诉被拒绝',
        remark.isEmpty ? '管理员未通过你的申诉，你可以重新提交申请。' : '管理员回复：$remark\n你可以重新提交申请。',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _statusBox(ThemeData theme, IconData icon, Color color, String title,
      String desc) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22.w),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: color)),
                SizedBox(height: 4.h),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12.sp,
                        color: theme.colorScheme.onSurface,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

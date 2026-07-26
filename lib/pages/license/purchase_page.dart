import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../components/app_dialog.dart';
import '../../models/order_info.dart';
import '../../models/plan_info.dart';
import '../../network/license_api.dart';
import '../../utils/license_manager.dart';

/// 购买页：选套餐 → 创建订单 → 展示收款码 + 备注 → 我已付款 → 轮询确认。
///
/// 设计见 docs/付费权益系统设计方案.md §4.3。
class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key});

  static const routeName = '/license/purchase';

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> with WidgetsBindingObserver {
  final LicenseApi _api = LicenseApi();

  bool _loadingPlans = true;
  List<PlanInfo> _plans = const [];
  PlanInfo? _selected;

  /// 付款备注（选填）：用户不填则不拼接，后台通知也不显示。
  final TextEditingController _remarkCtrl = TextEditingController();

  OrderInfo? _order;
  bool _creating = false;
  bool _paidChecking = false;

  /// 付款凭证截图（本地路径）。用户必须上传截图才能点「我已付款」。
  File? _proofImage;
  /// 上传后服务端返回的 URL（如 /uploads/xxx.jpg）。
  String? _proofUrl;
  bool _uploading = false;

  /// 进入付款视图后是否发生过退后台（paused）。
  /// 用户未离开 App 即点“我已付款”时视为存疑（通常未真实完成付款）。
  bool _leftAppSincePay = false;

  Timer? _pollTimer;
  int _pollCount = 0;
  static const _maxPoll = 60; // 5s * 60 = 5 分钟

  bool _argsHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlans();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsHandled) {
      _argsHandled = true;
      // 支持从订单列表传入 orderId 继续支付（而非创建新订单）。
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['orderId'] != null) {
        _resumeOrder(args['orderId'].toString());
      }
    }
  }

  /// 继续支付已有订单：调 orderStatus 获取完整 OrderInfo（含 qrCode），跳过套餐选择直接进入付款视图。
  Future<void> _resumeOrder(String orderId) async {
    setState(() => _creating = true);
    try {
      final info = await _api.orderStatus(orderId);
      if (!mounted) return;
      setState(() {
        _order = info;
        _leftAppSincePay = false;
      });
    } catch (e) {
      AppDialog.toast('订单加载失败：$e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarkCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台（去付款 App）会触发 paused，据此判断用户确实离开过。
    if (state == AppLifecycleState.paused) {
      _leftAppSincePay = true;
    }
  }

  Future<void> _loadPlans() async {
    setState(() => _loadingPlans = true);
    try {
      final plans = await _api.fetchPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _selected = plans.isNotEmpty ? plans.first : null;
        _loadingPlans = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPlans = false);
      AppDialog.toast('套餐加载失败：$e');
    }
  }

  Future<void> _createOrder() async {
    final plan = _selected;
    final deviceId = LicenseManager().deviceId;
    if (plan == null) return;
    if (deviceId == null) {
      AppDialog.toast('设备未识别，无法下单');
      return;
    }
    setState(() => _creating = true);
    try {
      final order = await _api.createOrder(
        deviceId: deviceId,
        plan: plan.code,
        payRemark: _remarkCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _order = order;
        // 进入付款视图，重置退后台标记。
        _leftAppSincePay = false;
      });
    } catch (e) {
      AppDialog.toast('创建订单失败：$e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _onPaid() async {
    final order = _order;
    if (order == null) return;
    // 必须先上传付款凭证截图。
    if (_proofUrl == null || _proofUrl!.isEmpty) {
      AppDialog.toast('请先上传付款截图凭证');
      return;
    }
    // 用户未离开 App（未退后台）即点已付款：弹窗警告，确认后以存疑提交。
    bool suspicious = false;
    if (!_leftAppSincePay) {
      final proceed = await AppDialog.confirm(
        title: '确认已完成付款？',
        message: '检测到您未打开付款 App，可能尚未完成付款。\n'
            '若确认已付款，可发起验证；若验证不通过（未真实付款），账号将被禁用。',
        confirmText: '发起验证',
        cancelText: '取消',
      );
      if (!proceed) return;
      suspicious = true;
    }
    setState(() => _paidChecking = true);
    try {
      final res = await _api.paidCheck(order.orderId,
          suspicious: suspicious, payProofUrl: _proofUrl);
      if (!mounted) return;
      setState(() => _order = order.copyWith(status: res.status));
      AppDialog.toast('已提交，正在等待作者确认收款');
      _startPolling(order.orderId);
    } catch (e) {
      AppDialog.toast('提交失败：$e');
    } finally {
      if (mounted) setState(() => _paidChecking = false);
    }
  }

  void _startPolling(String orderId) {
    _pollTimer?.cancel();
    _pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      _pollCount++;
      if (_pollCount > _maxPoll) {
        timer.cancel();
        return;
      }
      try {
        final res = await _api.orderStatus(orderId);
        if (!mounted) return;
        setState(() => _order = _order?.copyWith(status: res.status));
        if (res.isCompleted) {
          timer.cancel();
          await LicenseManager().refresh(force: true);
          if (!mounted) return;
          AppDialog.toast('权益已开通');
          Navigator.of(context).pop(true);
        } else if (res.isCancelled) {
          timer.cancel();
          AppDialog.toast('订单已取消，请联系客服或重新下单');
        }
      } catch (_) {
        // 单次轮询失败忽略，等待下次。
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('购买权益')),
      body: _loadingPlans
          ? const Center(child: CircularProgressIndicator())
          : _order == null
              ? _buildPlanSelector()
              : _buildPayView(),
    );
  }

  Widget _buildPlanSelector() {
    final theme = Theme.of(context);
    if (_plans.isEmpty) {
      return Center(
        child: TextButton(onPressed: _loadPlans, child: const Text('暂无套餐，点击重试')),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.all(16.w),
            itemCount: _plans.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final plan = _plans[index];
              final selected = plan.code == _selected?.code;
              return InkWell(
                onTap: () => setState(() => _selected = plan),
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: selected ? theme.colorScheme.primary : theme.dividerColor,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(plan.name,
                                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                            SizedBox(height: 4.h),
                            Text(
                              plan.isForever ? '永久有效' : '${plan.days} 天',
                              style: TextStyle(fontSize: 13.sp, color: theme.hintColor),
                            ),
                          ],
                        ),
                      ),
                      Text('￥${plan.price.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary)),
                      if (selected) ...[
                        SizedBox(width: 8.w),
                        Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20.w),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _remarkCtrl,
                  maxLength: 30,
                  decoration: InputDecoration(
                    labelText: '付款备注（选填）',
                    hintText: '例如填写您的昵称，方便作者对账',
                    isDense: true,
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _creating ? null : _createOrder,
                    style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                    child: Text(_creating ? '创建订单中...' : '立即购买'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayView() {
    final theme = Theme.of(context);
    final order = _order!;
    final remark = (order.payRemark ?? '').trim();
    final hasRemark = remark.isNotEmpty;

    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          Text('扫码付款', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
          SizedBox(height: 16.h),
          _buildQr(order.qrCode),
          SizedBox(height: 20.h),
          _infoRow('订单号', order.orderId),
          _infoRow('金额', order.amount != null ? '￥${order.amount!.toStringAsFixed(0)}' : '-'),
          if (hasRemark) _infoRow('付款备注', remark, highlight: true),
          SizedBox(height: 8.h),
          Text(
            hasRemark
                ? '付款时请在备注中填写：$remark\n方便作者核对到您的订单。'
                : '付款后点“我已付款”即可；上方订单号可作对账参考。',
            style: TextStyle(fontSize: 12.sp, color: theme.hintColor, height: 1.5),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.h),
          // 付款截图凭证上传区域
          if (!order.isPending) _buildProofSection(theme),
          if (!order.isPending) SizedBox(height: 16.h),
          if (order.isPending)
            Column(
              children: [
                const CircularProgressIndicator(),
                SizedBox(height: 12.h),
                Text('正在等待作者确认收款...',
                    style: TextStyle(fontSize: 13.sp, color: theme.hintColor)),
                SizedBox(height: 16.h),
                _buildPendingTips(theme),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_paidChecking || _uploading ||_proofUrl == null || _proofUrl!.isEmpty) ? null : _onPaid,
                style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.h)),
                child: Text(_paidChecking ? '提交中...' : '我已付款'),
              ),
            ),
        ],
      ),
    );
  }

  /// 付款后的安心提示：缓解“没人确认”的焦虑，告知可离开页面。
  Widget _buildPendingTips(ThemeData theme) {
    final color = theme.colorScheme.primary;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color, size: 20.w),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('付款已收到，无需一直等待',
                    style: TextStyle(
                        fontSize: 14.sp, fontWeight: FontWeight.w700, color: color)),
                SizedBox(height: 8.h),
                Text(
                  '作者确认后权益会自动开通。若作者一时未看到，系统会再次提醒处理。\n'
                  '你可以直接离开此页面：下次重启 App、或重新打开「我的权益」下拉刷新，都会自动更新为最新权益。',
                  style: TextStyle(
                      fontSize: 12.sp, color: theme.hintColor, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQr(String? url) {
    final placeholder = Container(
      width: 220.w,
      height: 220.w,
      alignment: Alignment.center,
      color: Colors.black12,
      child: const Text('收款码待配置'),
    );
    if (url == null || url.isEmpty) return placeholder;
    return Image.network(
      url,
      width: 220.w,
      height: 220.w,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }

  /// 付款截图凭证上传区：用户必须上传付款截图才能点「我已付款」。
  Widget _buildProofSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('上传付款截图（必须）',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        if (_proofImage != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: Image.file(_proofImage!, height: 160.h, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _proofImage = null;
                    _proofUrl = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: Icon(Icons.close, size: 16.w, color: Colors.white),
                  ),
                ),
              ),
              if (_proofUrl != null)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text('已上传',
                        style: TextStyle(fontSize: 10.sp, color: Colors.white)),
                  ),
                ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickAndUploadImage,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_uploading ? '上传中...' : '点击选择截图'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 14.h),
            ),
          ),
      ],
    );
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile == null) return;
    setState(() {
      _proofImage = File(xFile.path);
      _uploading = true;
    });
    try {
      final url = await _api.uploadImage(xFile.path);
      if (!mounted) return;
      setState(() {
        _proofUrl = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppDialog.toast('截图上传失败：$e');
    }
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp, color: theme.hintColor)),
          SizedBox(width: 16.w),
          Flexible(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: highlight ? theme.colorScheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

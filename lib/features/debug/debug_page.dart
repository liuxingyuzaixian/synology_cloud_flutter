import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/network/api_client.dart';
import '../../core/permissions/permission_util.dart';
import '../../core/router/fly_router.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/ui/app_adaptive.dart';
import '../../core/ui/app_dialog.dart';
import '../image/image_preview_page.dart';

class DebugRouteModule extends FlyRouteModule {
  @override
  List<AppRoute> get routes => [
        AppRoute(
          name: DebugPage.routeName,
          builder: (_, _) => const DebugPage(),
        ),
      ];
}

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  static const routeName = '/debug';

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  static const _demoImageUrl = 'http://zhanglei.nasfuns.fun:8089/i/2026/04/27/69eecb16afa80.gif';
  static const _weatherUrl = 'http://zhanglei.nasfuns.fun:4000/api/weather?city=杭州';

  late final TextEditingController _baseUrlController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late bool _proxyEnabled;
  String _networkResult = '未请求';
  String _permissionResult = '未申请';

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: ApiClient().dio.options.baseUrl);
    _hostController = TextEditingController(text: AppPreferences.getString(ApiClient.debugIp));
    _portController = TextEditingController(text: AppPreferences.getString(ApiClient.debugPort));
    _proxyEnabled = AppPreferences.getBool(ApiClient.debugIpSwitch);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    ApiClient().setBaseUrl(_baseUrlController.text.trim());
    await ApiClient().saveProxy(
      enabled: _proxyEnabled,
      host: _hostController.text,
      port: _portController.text,
    );
    AppDialog.toast('调试配置已保存');
  }

  Future<void> _requestWeather() async {
    await _save();
    setState(() => _networkResult = '请求中...');

    try {
      final data = await ApiClient().request<dynamic>(
        _weatherUrl,
        showErrorToast: false,
      );
      setState(() {
        _networkResult = const JsonEncoder.withIndent('  ').convert(data);
      });
    } on DioException catch (error) {
      setState(() => _networkResult = error.message ?? '请求失败');
    } catch (error) {
      setState(() => _networkResult = '$error');
    }
  }

  Future<void> _showLoadingDemo() async {
    final close = AppDialog.showLoading(label: '模拟加载中...');
    await Future<void>.delayed(const Duration(seconds: 1));
    close();
    AppDialog.toast('加载示例结束');
  }

  Future<void> _showConfirmDemo() async {
    final result = await AppDialog.confirm(
      title: '全局弹窗示例',
      message: '这是 AppDialog.confirm，可以在没有页面 context 的业务层通过全局 navigator 弹出。',
    );
    AppDialog.toast(result ? '点击了确定' : '点击了取消');
  }

  Future<void> _showBottomSheetDemo() {
    return AppDialog.bottomSheet<void>(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('底部弹窗示例', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 10.h),
              Text('适合选择器、操作菜单、确认信息等场景。', style: TextStyle(fontSize: 14.sp)),
              SizedBox(height: 18.h),
              FilledButton(
                onPressed: () => FlyRouter().pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestPermission(
    String label,
    Future<bool> Function() request,
  ) async {
    final granted = await request();
    setState(() => _permissionResult = '$label：${granted ? '已授权' : '未授权'}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('调试工具')),
      body: ListView(
        padding: EdgeInsets.all(16.r),
        children: [
          _DebugSection(
            title: 'Dio 网络与代理',
            children: [
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.example.com',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12.h),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('开启 Dio 代理'),
                subtitle: const Text('用于 Charles、Proxyman、Fiddler 等抓包'),
                value: _proxyEnabled,
                onChanged: (value) => setState(() => _proxyEnabled = value),
              ),
              SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: '代理 IP',
                        hintText: '127.0.0.1',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        hintText: '8888',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存配置'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _requestWeather,
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('请求天气示例'),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              SelectableText(_weatherUrl, style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
              SizedBox(height: 10.h),
              _ResultBox(text: _networkResult),
            ],
          ),
          _DebugSection(
            title: '查看大图',
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: Image.network(
                  _demoImageUrl,
                  height: 160.h,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(height: 12.h),
              SelectableText(_demoImageUrl, style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
              SizedBox(height: 10.h),
              FilledButton.icon(
                onPressed: () => AppImage.previewNetwork(_demoImageUrl, title: 'GIF 大图预览'),
                icon: const Icon(Icons.open_in_full_outlined),
                label: const Text('打开大图预览'),
              ),
            ],
          ),
          _DebugSection(
            title: '全局弹窗',
            children: [
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  FilledButton(
                    onPressed: () => AppDialog.toast('这是全局 Toast 示例'),
                    child: const Text('Toast'),
                  ),
                  OutlinedButton(
                    onPressed: _showLoadingDemo,
                    child: const Text('Loading'),
                  ),
                  OutlinedButton(
                    onPressed: _showConfirmDemo,
                    child: const Text('Confirm'),
                  ),
                  OutlinedButton(
                    onPressed: _showBottomSheetDemo,
                    child: const Text('BottomSheet'),
                  ),
                ],
              ),
            ],
          ),
          _DebugSection(
            title: '权限工具',
            children: [
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  FilledButton(
                    onPressed: () => _requestPermission('相机', PermissionUtil.requestCamera),
                    child: const Text('相机'),
                  ),
                  OutlinedButton(
                    onPressed: () => _requestPermission('相册', PermissionUtil.requestGallery),
                    child: const Text('相册'),
                  ),
                  OutlinedButton(
                    onPressed: () => _requestPermission('麦克风', PermissionUtil.requestMicrophone),
                    child: const Text('麦克风'),
                  ),
                  OutlinedButton(
                    onPressed: () => _requestPermission('定位', PermissionUtil.requestLocation),
                    child: const Text('定位'),
                  ),
                  OutlinedButton(
                    onPressed: () => _requestPermission('通知', PermissionUtil.requestNotification),
                    child: const Text('通知'),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              _ResultBox(text: _permissionResult),
            ],
          ),
          _DebugSection(
            title: '屏幕适配',
            children: [
              Text(
                '已接入 flutter_screenutil，可直接使用 13.sp、16.w、12.h、8.r。',
                style: TextStyle(fontSize: 13.sp),
              ),
              SizedBox(height: 8.h),
              Text(
                '额外补了百分比单位：50.wp = 屏幕宽度 50%，20.hp = 屏幕高度 20%。',
                style: TextStyle(fontSize: 13.sp),
              ),
              SizedBox(height: 12.h),
              Container(
                width: 50.wp,
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text('50.wp 宽度', style: TextStyle(fontSize: 13.sp)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 22.h),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Padding(
          padding: EdgeInsets.all(14.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 12.h),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultBox extends StatelessWidget {
  const _ResultBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.r),
        child: SelectableText(
          text,
          style: TextStyle(fontSize: 12.sp, color: const Color(0xFF374151)),
        ),
      ),
    );
  }
}

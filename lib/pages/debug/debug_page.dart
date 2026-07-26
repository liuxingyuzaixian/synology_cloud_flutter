import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../components/app_dialog.dart';
import '../../network/api_client.dart';
import '../../network/dsm_api.dart';
import '../../network/license_api.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/app_preferences.dart';
import '../../utils/fly_router.dart';
import '../../utils/permission_util.dart';
import '../common/image_preview_page.dart';
import '../common/viewers/music_player_page.dart';
import '../common/viewers/text_reader_page.dart';
import '../common/viewers/video_player_page.dart';

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

  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _licenseUrlController;
  late bool _proxyEnabled;
  late bool _licenseUseInternal;
  String _networkResult = '未请求';
  String _permissionResult = '未申请';
  String _deviceInfo = '未获取'; // 设备唯一标识测试结果
  bool _deviceLoading = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: AppPreferences.getString(ApiClient.debugIp));
    _portController = TextEditingController(text: AppPreferences.getString(ApiClient.debugPort));
    _proxyEnabled = AppPreferences.getBool(ApiClient.debugIpSwitch);
    _licenseUrlController = TextEditingController(text: AppPreferences.getString(LicenseApi.prefInternalUrl));
    _licenseUseInternal = AppPreferences.getBool(LicenseApi.prefUseInternal);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _licenseUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ApiClient().saveProxy(
      enabled: _proxyEnabled,
      host: _hostController.text,
      port: _portController.text,
    );
    AppDialog.toast('代理配置已保存');
  }

  Future<void> _saveLicenseNet() async {
    final url = _licenseUrlController.text.trim();
    if (url.isNotEmpty && !url.startsWith('http')) {
      AppDialog.toast('地址需以 http:// 或 https:// 开头');
      return;
    }
    await AppPreferences.putString(LicenseApi.prefInternalUrl, url);
    setState(() {}); // 刷新「当前生效」显示
    AppDialog.toast('内网地址已保存，会记住上次输入');
  }

  String _resolveSynoToken() {
    // 优先用 DsmApi 中已存储的 synoToken
    final saved = DsmApi().synoToken;
    if (saved.isNotEmpty) return saved;

    // 从 Cookie 中解析 fallback（兼容已登录的旧会话）
    final cookie = DsmApi().cookie;
    if (cookie.isEmpty) return '';
    for (final part in cookie.split('; ')) {
      final idx = part.indexOf('=');
      if (idx == -1) continue;
      final name = part.substring(0, idx);
      final value = part.substring(idx + 1);
      if (name.toLowerCase() == 'syno_token' && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  Future<void> _copySynoToken() async {
    final token = _resolveSynoToken();
    if (token.isEmpty) {
      AppDialog.toast('当前没有 SynoToken，请先登录');
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    AppDialog.toast('SynoToken 已复制到剪贴板');
  }

  Future<void> _refreshSynoToken() async {
    AppDialog.toast('正在刷新 SynoToken...');
    try {
      final token = await DsmApi().refreshSynoToken();
      if (token.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: token));
        setState(() {});
        AppDialog.toast('SynoToken 已刷新并复制到剪贴板');
      } else {
        AppDialog.toast('刷新失败，服务器未返回 SynoToken');
      }
    } catch (e) {
      AppDialog.toast('刷新失败: $e');
    }
  }

  /// 拉取设备唯一标识（序列号/MAC/型号等），用于授权绑定测试。
  /// 注意：serial/mac 很可能需要管理员权限，普通账号可能返回空。
  Future<void> _loadDeviceInfo() async {
    setState(() {
      _deviceLoading = true;
      _deviceInfo = '获取中...';
    });
    try {
      final sys = await DsmApi().systemInfo();
      final net = await DsmApi().networkInfo();
      final sysData = (sys['data'] ?? {}) as Map;
      final netData = (net['data'] ?? {}) as Map;
      final nifs = (netData['nif'] as List?) ?? const [];
      final macs = nifs
          .map((e) => (e is Map ? e['mac']?.toString() : null) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final buffer = StringBuffer()
        ..writeln('序列号 serial : ${sysData['serial'] ?? '(空/无权限)'}')
        ..writeln('型号 model    : ${sysData['model'] ?? '-'}')
        ..writeln('主机名        : ${sysData['hostname'] ?? '-'}')
        ..writeln('DSM 版本      : ${sysData['version_string'] ?? sysData['version'] ?? '-'}')
        ..writeln('MAC 地址      : ${macs.isEmpty ? '(空/无权限)' : macs.join(', ')}')
        ..writeln('')
        ..writeln('--- systemInfo 原始 data ---')
        ..writeln(const JsonEncoder.withIndent('  ').convert(sysData))
        ..writeln('')
        ..writeln('--- networkInfo 原始 data ---')
        ..writeln(const JsonEncoder.withIndent('  ').convert(netData));
      if (!mounted) return;
      setState(() => _deviceInfo = buffer.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _deviceInfo = '获取失败: $e');
    } finally {
      if (mounted) setState(() => _deviceLoading = false);
    }
  }

  Future<void> _copyDeviceInfo() async {
    await Clipboard.setData(ClipboardData(text: _deviceInfo));
    AppDialog.toast('设备信息已复制到剪贴板');
  }

  Future<void> _requestWeather() async {
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80.w,
            child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(value, style: TextStyle(fontSize: 13.sp)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('调试工具')),
      body: ListView(
        padding: EdgeInsets.all(16.r),
        children: [
          _DebugSection(
            title: '服务器连接信息',
            children: [
              _infoRow('Base URL', DsmApi().baseUrl.isEmpty ? '未连接' : DsmApi().baseUrl),
              _infoRow('Session ID', DsmApi().sid.isEmpty ? '无' : '${DsmApi().sid.substring(0, DsmApi().sid.length > 16 ? 16 : DsmApi().sid.length)}...'),
              _infoRow('DSM 版本', 'DSM ${DsmApi().dsmVersion}'),
              _infoRow('Cookie', DsmApi().cookie.isEmpty ? '无' : '${DsmApi().cookie.substring(0, DsmApi().cookie.length > 32 ? 32 : DsmApi().cookie.length)}...'),
              _infoRow('已登录', DsmApi().sid.isNotEmpty ? '是' : '否'),
              _infoRow('SynoToken', _resolveSynoToken().isEmpty ? '无' : '${_resolveSynoToken().substring(0, _resolveSynoToken().length > 24 ? 24 : _resolveSynoToken().length)}...'),
              if (DsmApi().server != null) ...[
                _infoRow('账号', DsmApi().server!.account),
                _infoRow('主机', DsmApi().server!.host),
                _infoRow('端口', DsmApi().server!.port),
                _infoRow('HTTPS', DsmApi().server!.https ? '是' : '否'),
                _infoRow('SSL验证', DsmApi().server!.checkSsl ? '是' : '否'),
              ],
              SizedBox(height: 8.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                  ),
                  FilledButton.icon(
                    onPressed: _refreshSynoToken,
                    icon: const Icon(Icons.update),
                    label: const Text('刷新 SynoToken'),
                  ),
                  FilledButton.icon(
                    onPressed: _copySynoToken,
                    icon: const Icon(Icons.content_copy),
                    label: const Text('复制 SynoToken'),
                  ),
                ],
              ),
            ],
          ),
          _DebugSection(
            title: '设备唯一标识（授权测试）',
            children: [
              Text(
                '从 SYNO.Core.System 读取序列号/MAC/型号等，用于设备授权绑定测试。'
                '若当前账号无权限，serial/mac 可能为空。',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
              ),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  FilledButton.icon(
                    onPressed: _deviceLoading ? null : _loadDeviceInfo,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('获取设备信息'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyDeviceInfo,
                    icon: const Icon(Icons.content_copy),
                    label: const Text('复制'),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              _ResultBox(text: _deviceInfo),
            ],
          ),
          _DebugSection(
            title: 'Dio 网络与代理',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('开启 Dio 代理'),
                subtitle: const Text('用于 Charles、Proxyman、Fiddler 等抓包'),
                value: _proxyEnabled,
                onChanged: (value) async {
                  setState(() => _proxyEnabled = value);
                  await ApiClient().saveProxy(
                    enabled: value,
                    host: _hostController.text,
                    port: _portController.text,
                  );
                },
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
                ],
              ),
            ],
          ),
          _DebugSection(
            title: '权益服务网络（公网/内网）',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('使用内网地址'),
                subtitle: Text(
                  '关闭：公网 ${LicenseApi.externalRoot}；开启：使用下方手动输入的内网根地址',
                  style: TextStyle(fontSize: 12.sp),
                ),
                value: _licenseUseInternal,
                onChanged: (value) async {
                  if (value && _licenseUrlController.text.trim().isEmpty) {
                    AppDialog.toast('请先填写内网根地址，如 http://192.168.31.193:4001');
                    return;
                  }
                  setState(() => _licenseUseInternal = value);
                  await AppPreferences.putBool(LicenseApi.prefUseInternal, value);
                  AppDialog.toast('已切换为${value ? '内网' : '公网'}，立即生效');
                },
              ),
              SizedBox(height: 8.h),
              TextField(
                controller: _licenseUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '内网根地址',
                  hintText: 'http://192.168.31.193:4001',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 14.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  FilledButton.icon(
                    onPressed: _saveLicenseNet,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存内网地址'),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              _infoRow('当前生效', LicenseApi.baseUrl),
            ],
          ),
          _DebugSection(
            title: '功能演示',
            children: [
              FilledButton.icon(
                onPressed: _requestWeather,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('请求天气示例'),
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
                onPressed: () => AppImage.preview(photos: [PreviewPhoto(thumbnailUrl: _demoImageUrl, fullUrl: _demoImageUrl, filename: 'GIF 大图预览')]),
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
          _DebugSection(
            title: '内置阅读器示例',
            children: [
              Text(
                '文件页面单击使用App内置方式打开，双击使用系统方式打开。',
                style: TextStyle(fontSize: 13.sp),
              ),
              SizedBox(height: 12.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MusicPlayerPage(
                        fileName: '示例音乐.mp3',
                        filePath: '/demo/sample.mp3',
                      ),
                    )),
                    icon: const Icon(Icons.music_note),
                    label: const Text('音乐播放器'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const VideoPlayerPage(
                        fileName: '示例视频.mp4',
                        filePath: '/demo/sample.mp4',
                      ),
                    )),
                    icon: const Icon(Icons.videocam),
                    label: const Text('视频播放器'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TextReaderPage(
                        fileName: '示例文本.txt',
                        filePath: '/demo/sample.txt',
                      ),
                    )),
                    icon: const Icon(Icons.article),
                    label: const Text('文本阅读器'),
                  ),
                ],
              ),
            ],
          ),
          _DebugSection(
            title: '开发工具',
            children: [
              FilledButton.icon(
                onPressed: () => _downloadHotReloadApk(),
                icon: const Icon(Icons.system_update),
                label: const Text('开发HotReload更新'),
              ),
              SizedBox(height: 8.h),
              SelectableText(
                'http://172.172.99.241:5421/api/download?filename=app-arm64-v8a-release.apk',
                style: TextStyle(fontSize: 11.sp, color: Colors.black54),
              ),
              SizedBox(height: 12.h),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('每次启动检查更新', style: TextStyle(fontSize: 13.sp)),
                subtitle: Text('关闭（默认）：每天仅检查一次；开启：每次启动都检查', style: TextStyle(fontSize: 12.sp, color: Colors.grey[500])),
                value: AppPreferences.getBool('auto_check_update'),
                onChanged: (v) {
                  AppPreferences.putBool('auto_check_update', v);
                  setState(() {});
                },
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _downloadHotReloadApk() async {
    const url = 'http://172.172.99.241:5421/api/download?filename=app-arm64-v8a-release.apk';
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) { AppDialog.toast('无法获取存储目录'); return; }
      final file = File('${dir.path}/${url.split('=').last}');
      AppDialog.toast('正在下载...');
      await Dio().download(url, file.path);
      AppDialog.toast('下载完成，正在安装...');
      await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    } catch (e) {
      AppDialog.toast('下载失败: $e');
    }
  }
  Future<void> _downloadApk(String url) async {
    AppDialog.toast('正在下载更新...');
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) { AppDialog.toast('无法获取存储目录'); return; }
      final file = File('${dir.path}/app-update.apk');
      final closeLoading = AppDialog.showLoading(label: '下载中...');
      await Dio().download(url, file.path);
      closeLoading();
      AppDialog.toast('下载完成，正在安装...');
      await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    } catch (e) {
      AppDialog.toast('更新失败: $e');
    }
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

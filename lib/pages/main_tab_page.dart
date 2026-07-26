import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/webview_entry.dart';
import '../network/dsm_api.dart';
import '../utils/app_logger.dart';
import '../utils/app_preferences.dart';
import '../utils/fly_router.dart';
import '../utils/license_manager.dart';
import '../utils/update_service.dart';
import './home/home_page.dart';
import './license/banned_page.dart';
import './license/paywall_page.dart';
import './photos/photos_page.dart';
import 'common/webview_page.dart';
import 'files/files_page.dart';
import 'mine/mine_page.dart';

class MainTabRouteModule extends FlyRouteModule {
  static const home = '/';

  @override
  List<AppRoute> get routes => [
        AppRoute(name: home, builder: (_, _) => const MainTabPage()),
      ];
}

class MainTabPage extends StatefulWidget {
  const MainTabPage({super.key});

  @override
  State<MainTabPage> createState() => _MainTabPageState();
}

class _MainTabPageState extends State<MainTabPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime? _lastBackAt;
  List<WebViewEntry> _webViewEntries = [];

  /// 定时校验权益（每 3 分钟），避免用户被禁用后仍长期使用。
  Timer? _licenseTimer;

  /// 是否正在做权益拦截跳转，避免 resume 重复触发。
  bool _redirecting = false;

  // FilesPage 的返回状态
  static bool _filesAtRoot = true;
  static void Function()? _filesGoUp;
  static bool _filesInSelectMode = false;
  static void Function()? _filesExitSelect;

  // PhotosPage 的多选状态
  static bool _photosInSelectMode = false;
  static void Function()? _photosExitSelect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWebViewEntries();
    // 启动即检查更新：频率（开关关=每天一次，开=每次启动）由 UpdateService 内部控制，
    // 强更不受频率限制，确保重启后强更弹窗必现
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdate(context);
      // 进入主页后重新校验权益（覆盖 saved-session 直进 '/' 未拦截的场景）。
      _checkLicense();
    });
    // 定时校验权益：每 30 秒检查一次，及时拦截已被禁用/过期的设备。
    _licenseTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkLicense();
    });
  }

  @override
  void dispose() {
    _licenseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 回到前台时重新校验，及时拦截已过期/被封禁的设备。
    if (state == AppLifecycleState.resumed) {
      AppLogger.d('MainTab', 'App回到前台，触发权益校验');
      _checkLicense();
    }
  }

  /// 校验当前设备权益：被封禁→跳用户状态异常页，无权益→跳付费引导页。
  /// 权益接口异常时走缓存宽限（LicenseManager），不因网络问题误伤。
  Future<void> _checkLicense() async {
    if (_redirecting || !mounted) return;
    AppLogger.section('定时权益校验');
    final info = await LicenseManager().refresh(force: true);
    AppLogger.d('MainTab', '校验结果: status=${info.status}, shouldBlock=${info.shouldBlock}, '
        'isBanned=${info.isBanned}, deviceId=${info.deviceId}');
    if (!mounted || _redirecting) return;
    if (!info.shouldBlock) return;
    _redirecting = true;
    final target =
        info.isBanned ? BannedPage.routeName : PaywallPage.routeName;
    AppLogger.w('MainTab', '⚠️ 权益拦截→跳转: $target');
    Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
  }

  void _loadWebViewEntries() {
    final json = AppPreferences.getString('webview_entries');
    final entries = WebViewEntry.listFromStorage(json);
    setState(() {
      _webViewEntries = entries.where((e) => e.openAsTab).toList();
    });
  }

  List<_TabInfo> get _orderedTabs {
    // 读取隐藏列表
    final hiddenJson = AppPreferences.getString('tab_hidden');
    final hidden = <String>{
      if (hiddenJson.isNotEmpty)
        ...?(() {
          try { return List<String>.from(jsonDecode(hiddenJson) as List); } catch (_) { return null; }
        })(),
    };

    // 首页和我的永远不隐藏
    hidden.remove('home');
    hidden.remove('settings');

    final dynamicIds = _webViewEntries.map((e) => e.id).toList();
    final middleIds = ['photos', 'files', ...dynamicIds].where((id) => !hidden.contains(id)).toList();

    final orderJson = AppPreferences.getString('tab_order');
    List<String> savedOrder = [];
    if (orderJson.isNotEmpty) {
      try {
        savedOrder = List<String>.from(jsonDecode(orderJson) as List);
      } catch (_) {}
    }

    List<String> orderedMiddle;
    if (savedOrder.isEmpty) {
      orderedMiddle = middleIds;
    } else {
      final byId = {for (final id in middleIds) id: id};
      orderedMiddle = <String>[];
      for (final id in savedOrder) {
        if (id == 'home' || id == 'settings') continue;
        final removed = byId.remove(id);
        if (removed != null) orderedMiddle.add(removed);
      }
      orderedMiddle.addAll(byId.values);
    }

    // 首页固定第一，我的固定最后
    final allIds = ['home', ...orderedMiddle, 'settings'];
    return allIds.map(_idToInfo).toList();
  }

  _TabInfo _idToInfo(String id) {
    switch (id) {
      case 'home':
        return _TabInfo(
          id: id,
          label: '首页',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          body: HomePage(onWebViewChanged: _loadWebViewEntries),
        );
      case 'photos':
        return _TabInfo(
          id: id,
          label: '照片',
          icon: Icons.photo_outlined,
          selectedIcon: Icons.photo,
          body: PhotosPage(
            onSelectModeChanged: (inSelect, exitFn) {
              notifyPhotosSelectMode(inSelect, exitFn);
            },
          ),
        );
      case 'files':
        return _TabInfo(
          id: id,
          label: '文件',
          icon: Icons.folder_outlined,
          selectedIcon: Icons.folder,
          body: FilesPage(
            onPathChanged: (isAtRoot, goUpFn) {
              _filesAtRoot = isAtRoot;
              _filesGoUp = goUpFn;
            },
            onSelectModeChanged: (inSelect, exitFn) {
              notifyFilesSelectMode(inSelect, exitFn);
            },
          ),
        );
      case 'settings':
        return _TabInfo(
          id: id,
          label: '我的',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          body: SettingsPage(),
        );
      default:
        final entry = _webViewEntries.firstWhere(
          (e) => e.id == id,
          orElse: () => WebViewEntry(id: id, title: '未知', url: 'about:blank'),
        );
        final resolvedUrl = DsmApi().resolveUrlWithAuth(entry.url.replaceFirst('BASE_URL', DsmApi().server?.host ?? ''));
        return _TabInfo(
          id: id,
          label: entry.title,
          icon: Icons.language,
          selectedIcon: Icons.language,
          body: WebViewPage(title: entry.title, url: resolvedUrl, hideUrl: entry.hideUrl),
        );
    }
  }

  /// 当前 tab 的 ID
  String get _currentTabId {
    final tabs = _orderedTabs;
    if (_currentIndex < tabs.length) return tabs[_currentIndex].id;
    return '';
  }

  /// 通知文件页面的多选状态变化
  static void notifyFilesSelectMode(bool inSelect, void Function()? exitFn) {
    _filesInSelectMode = inSelect;
    _filesExitSelect = exitFn;
  }

  /// 通知照片页面的多选状态变化
  static void notifyPhotosSelectMode(bool inSelect, void Function()? exitFn) {
    _photosInSelectMode = inSelect;
    _photosExitSelect = exitFn;
  }

  Future<bool> _onBackPressed() async {
    if (!Platform.isAndroid) return true;

    // 如果当前是文件 tab 且处于多选模式，先退出多选
    if (_currentTabId == 'files' && _filesInSelectMode) {
      _filesExitSelect?.call();
      return false;
    }

    // 如果当前是照片 tab 且处于多选模式，先退出多选
    if (_currentTabId == 'photos' && _photosInSelectMode) {
      _photosExitSelect?.call();
      return false;
    }

    // 如果当前是文件 tab 且不在根目录，返回上一级
    if (_currentTabId == 'files' && !_filesAtRoot) {
      _filesGoUp?.call();
      return false;
    }

    // 其他情况：2 秒内连按两次返回键才最小化 App（回到桌面，进程保活），
    // 按一次不做任何反应（无 toast）
    final now = DateTime.now();
    if (_lastBackAt == null ||
        now.difference(_lastBackAt!) > const Duration(seconds: 2)) {
      _lastBackAt = now;
      return false;
    }
    _lastBackAt = null;
    const MethodChannel('app.navigation').invokeMethod('moveTaskToBack');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _orderedTabs;
    if (_currentIndex >= tabs.length) {
      _currentIndex = 0;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _onBackPressed();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: tabs.map((tab) => tab.body).toList(),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            height: 60.h,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
              _checkLicense(); // 切 tab 时顺带校验
            },
            destinations: tabs
                .map(
                  (tab) => NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.label,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _TabInfo {
  const _TabInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.body,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
}

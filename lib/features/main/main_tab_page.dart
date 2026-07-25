import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/router/fly_router.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/suspension_button.dart';
import '../debug/debug_page.dart';
import '../gallery/photo_gallery_page.dart';

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

class _MainTabPageState extends State<MainTabPage> {
  int _currentIndex = 0;
  DateTime? _lastBackAt;

  final _tabs = const [
    _TabSpec('首页', Icons.home_outlined, Icons.home),
    _TabSpec('文件', Icons.folder_outlined, Icons.folder),
    _TabSpec('传输', Icons.sync_alt_outlined, Icons.sync_alt),
    _TabSpec('我的', Icons.person_outline, Icons.person),
  ];

  Future<bool> _onBackPressed() async {
    if (!Platform.isAndroid) return true;

    final now = DateTime.now();
    if (_lastBackAt == null ||
        now.difference(_lastBackAt!) > const Duration(seconds: 2)) {
      _lastBackAt = now;
      AppDialog.toast('再按一次退出App');
      return false;
    }
    SystemNavigator.pop();
    return false;
  }

  Widget _buildTabBody(int index) {
    switch (index) {
      case 1:
        return const PhotoGalleryPage();
      default:
        return _PlaceholderTab(
          title: _tabs[index].label,
          icon: _tabs[index].selectedIcon,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _onBackPressed();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Stack(
          children: [
            Scaffold(
              appBar: AppBar(title: Text(_tabs[_currentIndex].label)),
              body: IndexedStack(
                index: _currentIndex,
                children: List.generate(_tabs.length, _buildTabBody),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _currentIndex,
                height: 60.h,
                onDestinationSelected: (index) {
                  setState(() => _currentIndex = index);
                },
                destinations: _tabs
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
            SuspensionButton(
              initialRight: 10,
              initialBottom: 100,
              inTabBar: true,
              onPressed: () => FlyRouter().push(DebugPage.routeName),
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(22.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 9.h,
                    ),
                    child: Text(
                      '调试',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42.r, color: Theme.of(context).colorScheme.primary),
          SizedBox(height: 12.h),
          Text(
            '$title模块',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6.h),
          Text(
            '后续业务页面可以挂到当前 Tab 或注册成独立路由',
            style: TextStyle(fontSize: 13.sp, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

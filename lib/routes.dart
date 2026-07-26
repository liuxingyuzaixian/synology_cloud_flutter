import 'package:flutter/material.dart';
import 'package:synology_cloud_flutter/pages/common/image_preview_page.dart';
import 'package:synology_cloud_flutter/pages/common/share_upload_page.dart';
import 'package:synology_cloud_flutter/pages/main_tab_page.dart';
import 'package:synology_cloud_flutter/pages/mine/tab_sort_page.dart';
import 'package:synology_cloud_flutter/utils/fly_router.dart';

import 'network/dsm_api.dart';
import 'pages/debug/debug_page.dart';
import 'pages/license/banned_page.dart';
import 'pages/license/license_page.dart';
import 'pages/license/orders_page.dart';
import 'pages/license/paywall_page.dart';
import 'pages/license/purchase_page.dart';
import 'pages/login/login_page.dart';
import 'pages/photos/photos_page.dart';

class LoginRouteModule extends FlyRouteModule {
  static const routeName = '/login';
  @override
  List<AppRoute> get routes => [
        AppRoute(name: routeName, builder: (_, __) => const LoginPage()),
      ];
}

/// 付费权益相关页面（引导页 / 购买页 / 权益详情）
class LicenseRouteModule extends FlyRouteModule {
  @override
  List<AppRoute> get routes => [
        AppRoute(name: PaywallPage.routeName, builder: (_, __) => const PaywallPage()),
        AppRoute(name: BannedPage.routeName, builder: (_, __) => const BannedPage()),
        AppRoute(name: PurchasePage.routeName, builder: (_, __) => const PurchasePage()),
        AppRoute(name: LicenseDetailPage.routeName, builder: (_, __) => const LicenseDetailPage()),
        AppRoute(name: OrdersPage.routeName, builder: (_, __) => const OrdersPage()),
      ];
}

/// 登录状态拦截器：未登录时自动跳转登录页
class LoginInterceptor extends RouteInterceptor {
  @override
  String get key => 'login';

  @override
  RouteSettings? beforeRoute(RouteSettings settings, Map<String, dynamic> routeOptions) {
    // 允许登录页无需认证
    if (settings.name == '/login') return null;
    // 检查是否已登录
    final sid = DsmApi().sid;
    if (sid.isEmpty) {
      return const RouteSettings(name: '/login');
    }
    return null;
  }
}

final List<FlyRouteModule> routes = [
  MainTabRouteModule(),
  LoginRouteModule(),
  LicenseRouteModule(),
  DebugRouteModule(),
  ImagePreviewRouteModule(),
  PhotosRouteModule(),
  TabSortRouteModule(),
  ShareUploadRouteModule(),
];

final uniLinkOptions = FlyUniLinkOptions(
  customScheme: 'synologycloud',
  links: [
    FlyUniLink(path: '/home', route: MainTabRouteModule.home),
    FlyUniLink(path: '/debug', route: DebugPage.routeName),
  ],
);

import 'core/router/fly_router.dart';
import 'features/debug/debug_page.dart';
import 'features/image/image_preview_page.dart';
import 'features/main/main_tab_page.dart';

final List<FlyRouteModule> routes = [
  MainTabRouteModule(),
  DebugRouteModule(),
  ImagePreviewRouteModule(),
];

final uniLinkOptions = FlyUniLinkOptions(
  customScheme: 'synologycloud',
  links: [
    FlyUniLink(path: '/home', route: MainTabRouteModule.home),
    FlyUniLink(path: '/debug', route: DebugPage.routeName),
  ],
);

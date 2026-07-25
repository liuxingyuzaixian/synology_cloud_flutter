import 'package:flutter/material.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/router/fly_router.dart';
import 'core/storage/app_preferences.dart';
import 'routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 扩大全局图片缓存
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 300;        // 最多缓存 300 张图片（默认 1000，如果你图片很大可以调低）
  imageCache.maximumSizeBytes = 100 << 20; // 100 MB（根据实际情况调整）

  await AppPreferences.init();
  ApiClient();

  FlyRouter().initRoutes(
    routes,
    uniLinkOptions: uniLinkOptions,
  );

  runApp(const SynologyCloudApp());
}

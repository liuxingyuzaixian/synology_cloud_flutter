import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synology_cloud_flutter/app.dart';
import 'package:synology_cloud_flutter/core/network/api_client.dart';
import 'package:synology_cloud_flutter/core/router/fly_router.dart';
import 'package:synology_cloud_flutter/core/storage/app_preferences.dart';
import 'package:synology_cloud_flutter/routes.dart';

void main() {
  testWidgets('app shell renders main tab page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
    ApiClient();
    FlyRouter().initRoutes(routes, uniLinkOptions: uniLinkOptions);

    await tester.pumpWidget(const SynologyCloudApp());
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('传输'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synology_cloud_flutter/pages/common/share_upload_page.dart';
import 'package:synology_cloud_flutter/utils/app_preferences.dart';
import 'package:synology_cloud_flutter/utils/fly_router.dart';

import 'app.dart';
import 'components/app_dialog.dart';
import 'components/debug_tools.dart';
import 'models/server_model.dart';
import 'network/dsm_api.dart';
import 'routes.dart';

const MethodChannel _shareIntentChannel = MethodChannel('app.share_intents');
bool _shareUploadPending = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit（libmpv 视频内核）
  MediaKit.ensureInitialized();

  // 扩大全局图片缓存
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 500;        // 最多缓存 500 张图片
  imageCache.maximumSizeBytes = 200 << 20; // 200 MB

  // 核心初始化（必须同步完成）
  await AppPreferences.init();
  await DebugTools.init();
  DsmApi();

  // Restore saved session so LoginInterceptor sees a valid sid
  _restoreSession();

  FlyRouter().initRoutes(
    routes,
    interceptors: [LoginInterceptor()],
    uniLinkOptions: uniLinkOptions,
  );

  _shareIntentChannel.setMethodCallHandler((call) async {
    if (call.method != 'onShareIntent') return;
    final args = call.arguments;
    if (args is! List) return;

    final files = <ShareUploadFile>[];
    for (final item in args) {
      if (item is! Map) continue;
      final path = item['path']?.toString().trim() ?? '';
      if (path.isEmpty) continue;
      final name = item['name']?.toString().trim() ?? '';
      files.add(ShareUploadFile(
        path: path,
        name: name.isEmpty ? path.split(Platform.pathSeparator).where((e) => e.isNotEmpty).last : name,
      ));
    }

    if (files.isNotEmpty) {
      _openShareUploadPage(files);
    }
  });

  runApp(const SynologyCloudApp());
}

void _openShareUploadPage(List<ShareUploadFile> files) {
  final navigator = FlyRouter().navigatorKey.currentState;
  if (navigator == null) {
    if (_shareUploadPending) return;
    _shareUploadPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareUploadPending = false;
      _openShareUploadPage(files);
    });
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) return;
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    AppDialog.toast('收到共享文件，准备上传');
    FlyRouter().push<void>(
      ShareUploadPage.routeName,
      arguments: files,
    );
  });
}

/// Lightweight session restore – just set server + sid so the
/// LoginInterceptor allows navigation to the main page.
void _restoreSession() {
  final host = AppPreferences.getString('host');
  final sid = AppPreferences.getString('sid');
  if (host.isEmpty || sid.isEmpty) return;

  final baseUrl = AppPreferences.getString('base_url');
  final port = AppPreferences.getString('port', defaultValue: '5000');
  final account = AppPreferences.getString('account');
  final password = AppPreferences.getString('password');
  final note = AppPreferences.getString('note');
  final smid = AppPreferences.getString('smid');
  final https = AppPreferences.getString('https') == '1';
  final checkSsl = AppPreferences.getString('check_ssl') != '0';

  final server = ServerModel(
    host: host,
    port: port,
    https: https,
    account: account,
    password: password,
    note: note,
    baseUrl: baseUrl,
    checkSsl: checkSsl,
    sid: sid,
    cookie: smid,
    dsmVersion: 7,
  );

  DsmApi().setServer(server);
  DsmApi().setSession(sid: sid, cookie: smid);

  // 恢复 SynoToken 用于 WebView 自动登录
  final synoToken = AppPreferences.getString('syno_token');
  debugPrint('【调试】main.dart 恢复 syno_token: "${synoToken.length > 20 ? '${synoToken.substring(0, 20)}...' : synoToken}" 长度=${synoToken.length}');
  if (synoToken.isNotEmpty) {
    DsmApi().setSynoToken(synoToken);
  }
}

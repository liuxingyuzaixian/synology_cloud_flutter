import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/router/fly_router.dart';
import 'core/ui/app_adaptive.dart';
import 'core/ui/app_dialog.dart';

class SynologyCloudApp extends StatelessWidget {
  const SynologyCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: AppAdaptive.designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Synology Cloud',
          debugShowCheckedModeBanner: false,
          navigatorKey: FlyRouter().navigatorKey,
          scaffoldMessengerKey: AppDialog.messengerKey,
          onGenerateRoute: FlyRouter().onGenerateRoute,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB),
              primary: const Color(0xFF2563EB),
            ),
            scaffoldBackgroundColor: const Color(0xFFF7F8FA),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              foregroundColor: Color(0xFF111827),
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
            inputDecorationTheme: const InputDecorationTheme(isDense: true),
          ),
        );
      },
    );
  }
}

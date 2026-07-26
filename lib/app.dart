import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:synology_cloud_flutter/utils/app_adaptive.dart';
import 'package:synology_cloud_flutter/utils/app_preferences.dart';
import 'package:synology_cloud_flutter/utils/fly_router.dart';
import 'components/app_dialog.dart';
import 'components/debug_tools.dart';
import 'components/suspension_button.dart';
import 'pages/debug/debug_page.dart';

/// Global dark mode notifier – toggle from settings_page.dart
final ValueNotifier<bool> darkModeNotifier =
    ValueNotifier<bool>(AppPreferences.getBool('darkMode'));

/// Global route observer for detecting navigation events
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

class SynologyCloudApp extends StatelessWidget {
  const SynologyCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: AppAdaptive.designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: darkModeNotifier,
          builder: (context, isDark, _) {
            return MaterialApp(
              title: 'Synology Cloud',
              debugShowCheckedModeBanner: false,
              navigatorKey: FlyRouter().navigatorKey,
              scaffoldMessengerKey: AppDialog.messengerKey,
              onGenerateRoute: FlyRouter().onGenerateRoute,
              navigatorObservers: [routeObserver],
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF2563EB),
                  primary: const Color(0xFF2563EB),
                  brightness: Brightness.light,
                ),
                scaffoldBackgroundColor: const Color(0xFFF7F8FA),
                appBarTheme: const AppBarTheme(
                  centerTitle: true,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  foregroundColor: Color(0xFF111827),
                  elevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.dark,
                  titleTextStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                    letterSpacing: 0.3,
                  ),
                ),
                inputDecorationTheme: const InputDecorationTheme(isDense: true),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF2563EB),
                  primary: const Color(0xFF2563EB),
                  brightness: Brightness.dark,
                ),
                scaffoldBackgroundColor: const Color(0xFF121212),
                appBarTheme: const AppBarTheme(
                  centerTitle: true,
                  backgroundColor: Color(0xFF1E1E1E),
                  surfaceTintColor: Color(0xFF1E1E1E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.light,
                  titleTextStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                inputDecorationTheme: const InputDecorationTheme(isDense: true),
              ),
              builder: (context, child) {
                // Wrap with Stack to overlay the global debug button
                return _GlobalOverlay(child: child ?? const SizedBox.shrink());
              },
            );
          },
        );
      },
    );
  }
}

/// Global overlay that shows the draggable debug button on ALL pages.
class _GlobalOverlay extends StatelessWidget {
  const _GlobalOverlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DebugTools.debugButtonNotifier,
      builder: (context, showDebug, _) {
        return Stack(
          children: [
            child,
            if (showDebug)
              SuspensionButton(
                initialRight: 10,
                initialBottom: 150,
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
        );
      },
    );
  }
}

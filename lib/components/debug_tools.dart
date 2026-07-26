import 'package:flutter/foundation.dart';

import '../utils/app_preferences.dart';
import '../utils/fly_router.dart';
import '../../pages/debug/debug_page.dart';
import 'app_dialog.dart';

const _debugButtonKey = 'debug_button_enabled';

class DebugTools {
  DebugTools._();

  static final ValueNotifier<bool> debugButtonNotifier = ValueNotifier<bool>(false);

  static Future<void> init() async {
    debugButtonNotifier.value = AppPreferences.getBool(_debugButtonKey);
  }

  static bool isDebugButtonEnabled() => debugButtonNotifier.value;

  static Future<void> enableDebugButton() async {
    await AppPreferences.putBool(_debugButtonKey, true);
    debugButtonNotifier.value = true;
  }

  static Future<void> activate() async {
    await enableDebugButton();
    AppDialog.toast('调试已启用');
  }

  static Future<void> activateAndOpen() async {
    await enableDebugButton();
    AppDialog.toast('调试已启用');
    FlyRouter().push(DebugPage.routeName);
  }

  static Future<void> disableDebugButton() async {
    await AppPreferences.putBool(_debugButtonKey, false);
    debugButtonNotifier.value = false;
  }
}

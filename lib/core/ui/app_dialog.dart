import 'package:flutter/material.dart';

import '../router/fly_router.dart';

class AppDialog {
  AppDialog._();

  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static BuildContext? get _context => FlyRouter().getContext();

  static void toast(String message) {
    final messenger = messengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  static VoidCallback showLoading({String label = '加载中...'}) {
    final context = _context;
    if (context == null) return () {};

    var closed = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 132,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return () {
      if (closed) return;
      closed = true;
      final navigator = FlyRouter().navigatorKey.currentState;
      if (navigator?.canPop() ?? false) {
        navigator!.pop();
      }
    };
  }

  static Future<T?> showAppDialog<T>({
    required Widget child,
    bool barrierDismissible = true,
  }) {
    final context = _context;
    if (context == null) return Future.value();

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => child,
    );
  }

  static Future<bool> confirm({
    required String title,
    required String message,
    String cancelText = '取消',
    String confirmText = '确定',
  }) async {
    final result = await showAppDialog<bool>(
      child: AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => FlyRouter().pop(false),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => FlyRouter().pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<T?> bottomSheet<T>({
    required Widget child,
    bool isScrollControlled = true,
  }) {
    final context = _context;
    if (context == null) return Future.value();

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      builder: (_) => child,
    );
  }
}

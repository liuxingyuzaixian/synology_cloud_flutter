import 'package:flutter/material.dart';

import '../utils/fly_router.dart';

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

  /// 危险操作确认弹窗 (iOS风格，确认按钮标红)
  static Future<bool> dangerConfirm({
    required String title,
    required String message,
    String cancelText = '取消',
    String confirmText = '确认',
  }) async {
    final context = _context;
    if (context == null) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: Text(message, style: const TextStyle(fontSize: 15)),
        actionsPadding: const EdgeInsets.only(bottom: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText, style: const TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmText,
              style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.w600),
            ),
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

  /// 输入对话框
  static Future<String?> input({
    required String title,
    String label = '请输入',
    String? initialValue,
    String confirmText = '确定',
    String cancelText = '取消',
  }) async {
    final context = _context;
    if (context == null) return null;

    final controller = TextEditingController(text: initialValue ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

/// 显示"敬请期待"占位弹窗
extension ComingSoon on AppDialog {
  static void comingSoon(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction, size: 48, color: Colors.orange),
            SizedBox(height: 12),
            Text('开发中，敬请期待', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('此功能正在努力开发中，请关注后续版本更新', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
        actions: [TextButton(onPressed: Navigator.of(context).pop, child: Text('知道了'))],
      ),
    );
  }
}

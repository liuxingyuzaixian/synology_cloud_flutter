import 'package:flutter/material.dart';

class CustomScrollBar extends StatelessWidget {
  const CustomScrollBar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility = false,
    this.interactive = true,
    this.thickness = 20,
    this.radius = const Radius.circular(999),
    this.minThumbLength = 48,
    this.crossAxisMargin = 10,
    this.thumbColor = const Color(0x61000000), // Colors.black38
  });

  final Widget child;

  /// 与 ScrollView 使用同一个 controller
  final ScrollController? controller;

  final bool thumbVisibility;
  final bool interactive;
  final double thickness;
  final Radius radius;
  final double minThumbLength;
  final double crossAxisMargin;
  final Color thumbColor;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    return RawScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      interactive: interactive,
      thickness: thickness,
      radius: radius,
      minThumbLength: minThumbLength,
      crossAxisMargin: crossAxisMargin,
      thumbColor:
      isDark ? Colors.white24 : Colors.black54,
      child: child,
    );
  }
}

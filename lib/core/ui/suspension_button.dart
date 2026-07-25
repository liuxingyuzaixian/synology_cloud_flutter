import 'dart:math' as math;

import 'package:flutter/material.dart';

class SuspensionButton extends StatefulWidget {
  const SuspensionButton({
    required this.onPressed,
    required this.child,
    super.key,
    this.initialRight = 0,
    this.initialBottom = 300,
    this.canMoveEnable = true,
    this.inTabBar = false,
    this.positionLeftCallback,
  });

  final VoidCallback onPressed;
  final Widget child;
  final double initialRight;
  final double initialBottom;
  final bool canMoveEnable;
  final bool inTabBar;
  final ValueChanged<bool>? positionLeftCallback;

  @override
  State<SuspensionButton> createState() => _SuspensionButtonState();
}

class _SuspensionButtonState extends State<SuspensionButton> {
  static const _tapMoveDistance = 3.0;
  static const _edgePadding = 10.0;
  static const _topPadding = 80.0;
  static const _tabBarHeight = 60.0;

  Offset _position = Offset.zero;
  Offset _startPointer = Offset.zero;
  Offset _startPosition = Offset.zero;
  Size _buttonSize = Size.zero;
  bool _initialized = false;
  bool _isTap = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializePositionIfNeeded();
  }

  void _initializePositionIfNeeded() {
    if (_initialized) return;

    final media = MediaQuery.of(context);
    final screenSize = media.size;
    _position = Offset(
      screenSize.width - widget.initialRight,
      screenSize.height - widget.initialBottom,
    );
    _initialized = true;
  }

  void _onPanStart(DragStartDetails details) {
    _startPointer = details.globalPosition;
    _startPosition = _position;
    _isTap = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.canMoveEnable) return;

    final delta = details.globalPosition - _startPointer;
    if (delta.distance > _tapMoveDistance) {
      _isTap = false;
    }
    if (_isTap) return;

    setState(() {
      _position = _clampPosition(_startPosition + delta);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isTap) {
      widget.onPressed();
      return;
    }
    _snapToEdge();
  }

  Offset _clampPosition(Offset position) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final bottomReserved = widget.inTabBar ? _tabBarHeight + media.padding.bottom : 0.0;

    final maxX = math.max(_edgePadding, size.width - _buttonSize.width - _edgePadding);
    final maxY = math.max(
      _topPadding,
      size.height - _buttonSize.height - bottomReserved - _edgePadding,
    );

    return Offset(
      position.dx.clamp(_edgePadding, maxX),
      position.dy.clamp(_topPadding, maxY),
    );
  }

  void _snapToEdge() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLeft = _position.dx < screenWidth / 2;
    widget.positionLeftCallback?.call(isLeft);

    setState(() {
      _position = _clampPosition(
        Offset(
          isLeft ? _edgePadding : screenWidth - _buttonSize.width - _edgePadding,
          _position.dy,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _initializePositionIfNeeded();

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: MeasureSize(
          onChange: (size) {
            if (_buttonSize == size) return;
            setState(() {
              _buttonSize = size;
              _position = _clampPosition(_position);
            });
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class MeasureSize extends StatefulWidget {
  const MeasureSize({
    required this.child,
    required this.onChange,
    super.key,
  });

  final Widget child;
  final ValueChanged<Size> onChange;

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = context.findRenderObject();
      if (renderBox is! RenderBox) return;

      final size = renderBox.size;
      if (_oldSize == size) return;
      _oldSize = size;
      widget.onChange(size);
    });

    return widget.child;
  }
}

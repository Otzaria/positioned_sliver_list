import "dart:ui";

import "package:flutter/widgets.dart";

import "extent_manager.dart";

class AnimateToItem {
  AnimateToItem({
    required this.extentManager,
    required this.index,
    required this.alignment,
    required this.rect,
    required this.position,
    required this.duration,
    required this.curve,
  });

  final ExtentManager extentManager;
  final ValueGetter<int?> index;
  final double alignment;
  final Rect? rect;
  final ScrollPosition position;
  final Duration Function(double estimatedDistance) duration;
  final Curve Function(double estimatedDistance) curve;

  double lastPosition = 0.0;
  AnimationController? _controller;

  void animate() {
    final index = this.index();
    if (index == null) {
      return;
    }
    final start = position.pixels;
    final estimatedTarget = extentManager.getOffsetToReveal(
      index,
      alignment,
      rect: rect,
      estimationOnly: true,
    );
    final estimatedDistance = (estimatedTarget - start).abs();
    final controller = AnimationController(
      vsync: position.context.vsync,
      duration: duration(estimatedDistance),
    );
    _controller = controller;
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        cancel();
      }
    });
    final animation = CurvedAnimation(
      parent: controller,
      curve: curve(estimatedDistance),
    );
    animation.addListener(() {
      final value = animation.value;
      final index = this.index();
      if (index == null) {
        cancel();
        return;
      }
      var targetPosition = extentManager.getOffsetToReveal(
        index,
        alignment,
        rect: rect,
        estimationOnly: value < 1.0,
      );
      if (value < 1.0) {
        // Clamp position during animation to prevent overscroll.
        targetPosition = targetPosition.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
      }
      final jumpPosition = lerpDouble(start, targetPosition, value)!;
      lastPosition = jumpPosition;
      if ((jumpPosition <= position.minScrollExtent &&
              position.pixels == position.minScrollExtent) ||
          (jumpPosition >= position.maxScrollExtent &&
              position.pixels == position.maxScrollExtent)) {
        // Do not jump when already at the edge. This prevents scrollbar handle artifacts.
        return;
      }
      position.jumpTo(jumpPosition);
    });
    controller.forward();
  }

  /// Cancels the animation and disposes resources.
  void cancel() {
    final controller = _controller;
    if (controller != null) {
      _controller = null;
      controller.stop();
      controller.dispose();
    }
  }

  /// Whether the animation is currently running.
  bool get isAnimating => _controller?.isAnimating ?? false;
}

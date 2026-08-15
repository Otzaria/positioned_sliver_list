import "dart:async";

import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";

import "perf_flags.dart";
import "stick_target.dart";
import "super_sliver_list.dart";

/// Keeps a [SuperSliverList] pinned to a target while its content changes.
///
/// User scrolling disengages the target. For [StickTarget.bottom], scrolling
/// back into [threshold] re-engages it. Pointer interaction temporarily
/// suspends corrections so widgets can expand under a tap without fighting the
/// gesture.
class StickToTarget extends StatefulWidget {
  const StickToTarget({
    super.key,
    required this.scrollController,
    required this.listController,
    required this.target,
    required this.child,
    this.threshold = 20,
    this.onStickStateChanged,
  });

  final ScrollController scrollController;
  final ListController listController;
  final StickTarget? target;
  final Widget child;
  final double threshold;
  final ValueChanged<bool>? onStickStateChanged;

  @override
  State<StickToTarget> createState() => _StickToTargetState();
}

class _StickToTargetState extends State<StickToTarget> {
  static const _interactionGrace = Duration(milliseconds: 500);
  static const _precisionErrorTolerance = 0.001;

  bool _isSticking = false;
  bool _userIsInteracting = false;
  bool _userOptedOut = false;
  bool _isChangingScrollOffset = false;
  final Set<int> _activePointers = <int>{};
  Timer? _interactionTimer;
  int _jumpGeneration = 0;

  @override
  void initState() {
    super.initState();
    _contentListenable(widget.listController).addListener(_onContentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluateInitialPosition();
    });
  }

  @override
  void didUpdateWidget(covariant StickToTarget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final listControllerChanged =
        oldWidget.listController != widget.listController;
    final scrollControllerChanged =
        oldWidget.scrollController != widget.scrollController;
    final targetChanged = oldWidget.target != widget.target;

    if (listControllerChanged) {
      _contentListenable(
        oldWidget.listController,
      ).removeListener(_onContentChanged);
      oldWidget.listController.stickTarget = null;
      _contentListenable(widget.listController).addListener(_onContentChanged);
    }

    if (scrollControllerChanged) {
      _cancelScheduledJumps();
      _isSticking = false;
      _userOptedOut = false;
      oldWidget.listController.stickTarget = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _evaluateInitialPosition();
      });
      return;
    }

    if (targetChanged) {
      if (widget.target == null) {
        _userOptedOut = false;
        _setSticking(false);
        return;
      }

      if (_isSticking) {
        // The boolean state did not change, but the render object still needs
        // the new target value.
        widget.listController.stickTarget = widget.target;
        _syncRenderTarget();
        _scheduleJumpToTarget();
      } else if (!_userOptedOut && _shouldEngageTarget()) {
        _setSticking(true);
        _scheduleJumpToTarget();
      }
    } else if (listControllerChanged) {
      widget.listController.stickTarget = _isSticking ? widget.target : null;
      _syncRenderTarget();
      if (_isSticking) _scheduleJumpToTarget();
    }

    // A threshold update deliberately does not re-engage an unstuck list.
  }

  @override
  void dispose() {
    _interactionTimer?.cancel();
    _cancelScheduledJumps();
    _contentListenable(
      widget.listController,
    ).removeListener(_onContentChanged);
    widget.listController.stickTarget = null;
    super.dispose();
  }

  Listenable _contentListenable(ListController controller) =>
      SuperSliverListPerfFlags.extentsOnlyStickNotifications
          ? controller.extentsChangedListenable
          : controller;

  void _evaluateInitialPosition() {
    if (!widget.scrollController.hasClients) {
      _setSticking(false, notify: false);
      return;
    }
    _userOptedOut = false;
    _setSticking(_shouldEngageTarget(), notify: false);
    if (_isSticking) _scheduleJumpToTarget();
  }

  bool _shouldEngageTarget() {
    final target = widget.target;
    if (target == null || !widget.scrollController.hasClients) return false;
    if (target.isBottom) return _isAtBottom();
    return _targetExists(target);
  }

  bool _targetExists(StickTarget target) =>
      target.isBottom ||
      (target.index >= 0 && target.index < widget.listController.numberOfItems);

  bool _isAtBottom() {
    if (!widget.scrollController.hasClients) return false;
    final position = widget.scrollController.position;
    return (_bottomOffset(position) - position.pixels).abs() <=
        widget.threshold;
  }

  double _bottomOffset(ScrollPosition position) {
    return switch (position.axisDirection) {
      AxisDirection.down || AxisDirection.right => position.maxScrollExtent,
      AxisDirection.up || AxisDirection.left => position.minScrollExtent,
    };
  }

  void _setSticking(bool value, {bool notify = true}) {
    final target = value ? widget.target : null;
    final changed = _isSticking != value;
    _isSticking = value;
    widget.listController.stickTarget = target;
    _syncRenderTarget();
    if (changed && notify) widget.onStickStateChanged?.call(value);
  }

  void _syncRenderTarget() {
    final position = widget.scrollController.hasClients
        ? widget.scrollController.position
        : null;
    final renderTarget = _isSticking &&
            !_userIsInteracting &&
            position?.axisDirection != AxisDirection.up
        ? widget.target
        : null;
    widget.listController.renderStickTarget = renderTarget;
  }

  void _optOutFromUserScroll() {
    _userOptedOut = true;
    _setSticking(false);
  }

  void _beginInteraction() {
    _interactionTimer?.cancel();
    _userIsInteracting = true;
    // Keep the logical stick state, but suspend render-object corrections.
    widget.listController.stickTarget = null;
  }

  void _scheduleInteractionEnd() {
    _interactionTimer?.cancel();
    _interactionTimer = Timer(_interactionGrace, _finishInteraction);
  }

  void _finishInteraction() {
    if (!mounted || _activePointers.isNotEmpty) return;
    _userIsInteracting = false;

    // Only bottom sticking can be regained by user scrolling. Item targets
    // remain opted out until their owner explicitly supplies a fresh state.
    if (_userOptedOut && widget.target?.isBottom == true && _isAtBottom()) {
      _userOptedOut = false;
      _setSticking(true);
    }
    if (_isSticking) {
      widget.listController.stickTarget = widget.target;
      _syncRenderTarget();
      _onContentChanged();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _beginInteraction();
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _scheduleInteractionEnd();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _scheduleInteractionEnd();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    _beginInteraction();
    // A wheel signal at an edge may produce no ScrollEndNotification.
    _scheduleInteractionEnd();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      if (notification is ScrollStartNotification && _isSticking) {
        // Pointer events bubble through this widget even when a descendant
        // scrollable owns the gesture. Undo the outer interaction suspension.
        _activePointers.clear();
        _interactionTimer?.cancel();
        _userIsInteracting = false;
        widget.listController.stickTarget = widget.target;
        _syncRenderTarget();
      }
      return false;
    }

    if (notification is ScrollStartNotification) {
      _beginInteraction();
    } else if (notification is ScrollUpdateNotification) {
      if (!_isChangingScrollOffset && _isSticking) {
        _optOutFromUserScroll();
      }
    } else if (notification is ScrollEndNotification) {
      // Pointer-up owns the grace period for touch interaction. Keyboard and
      // semantics scrolling have no active pointer, so may finish immediately.
      if (_activePointers.isEmpty && !_interactionTimerIsActive) {
        _finishInteraction();
      }
    }
    return false;
  }

  bool get _interactionTimerIsActive => _interactionTimer?.isActive ?? false;

  bool _onMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.depth == 0 && _isSticking && !_userIsInteracting) {
      _scheduleJumpToTarget();
    }
    return false;
  }

  void _onContentChanged() {
    if (!_isSticking || _userIsInteracting) return;
    final target = widget.target;
    if (target == null) return;
    if (!_targetExists(target)) {
      _userOptedOut = true;
      _setSticking(false);
      return;
    }

    widget.listController.stickTarget = target;
    _syncRenderTarget();
    _scheduleJumpToTarget();
  }

  void _cancelScheduledJumps() {
    _jumpGeneration++;
  }

  void _scheduleJumpToTarget() {
    final generation = ++_jumpGeneration;
    final scrollController = widget.scrollController;
    final listController = widget.listController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _jumpGeneration ||
          scrollController != widget.scrollController ||
          listController != widget.listController ||
          !_isSticking ||
          _userIsInteracting) {
        return;
      }
      _jumpToTarget(scrollController, listController);
    });
  }

  void _jumpToTarget(
    ScrollController scrollController,
    ListController listController,
  ) {
    if (!scrollController.hasClients) return;
    final target = widget.target;
    if (target == null) return;

    final position = scrollController.position;
    late final double desiredOffset;
    if (target.isBottom) {
      desiredOffset = _bottomOffset(position);
    } else {
      if (!_targetExists(target)) {
        _userOptedOut = true;
        _setSticking(false);
        return;
      }
      desiredOffset = listController.getOffsetToReveal(
        target.index,
        target.alignment,
        rect: target.rect,
      );
    }

    if (!desiredOffset.isFinite) return;
    final clampedOffset = desiredOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clampedOffset - position.pixels).abs() <= _precisionErrorTolerance) {
      return;
    }

    _isChangingScrollOffset = true;
    try {
      scrollController.jumpTo(clampedOffset);
    } finally {
      _isChangingScrollOffset = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetricsNotification,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: widget.child,
        ),
      ),
    );
  }
}

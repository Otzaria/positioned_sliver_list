import "dart:async";

import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart" show ScrollDirection;
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";

import "perf_flags.dart";
import "stick_target.dart";
import "super_sliver_list.dart";

/// Keeps a [SuperSliverList] pinned to a target while its content changes.
///
/// [scrollController] must be attached to at most one scrollable at a time.
///
/// User scrolling disengages the target. For [StickTarget.bottom], scrolling
/// back into [threshold] re-engages it. Pointer interaction temporarily
/// suspends corrections so widgets can expand under a tap without fighting the
/// gesture.
///
/// Engagement waits without a timeout for scroll dimensions and the target
/// item to exist. A late item can therefore cause a jump. Clear or replace
/// [target] to cancel a stale request. While pending, drag/wheel scrolling
/// cancels engagement, but programmatic scrolling does not. Pointer-free
/// keyboard/semantics scrolling is indistinguishable from programmatic
/// scrolling in this state; clear [target] if that navigation should cancel it.
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

enum _PendingEngagement { silent, notifying }

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
  // A controller can attach before its viewport reports any dimensions.
  // Keep engagement pending until metrics (and item data) become available.
  _PendingEngagement? _pendingEngagement = _PendingEngagement.silent;
  bool get _needsEngagement => _pendingEngagement != null;
  bool _contentChangeScheduled = false;

  @override
  void initState() {
    super.initState();
    _contentListenable(widget.listController).addListener(_onContentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluatePendingEngagement();
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
      _pendingEngagement = _PendingEngagement.silent;
      oldWidget.listController.stickTarget = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _evaluatePendingEngagement();
      });
      return;
    }

    if (targetChanged) {
      _cancelScheduledJumps();
      _pendingEngagement = null;
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
      } else if (!_userOptedOut) {
        _pendingEngagement = _PendingEngagement.notifying;
        _evaluatePendingEngagement();
        if (_needsEngagement) {
          // The new item or scroll dimensions may not exist until layout.
          _scheduleTargetEngagementAfterLayout(widget.target!);
        }
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

  ScrollPosition? _readyPosition(ScrollController controller) {
    assert(controller.positions.length <= 1,
        "StickToTarget requires a ScrollController with at most one position.");
    if (controller.positions.length != 1) return null;
    final position = controller.position;
    if (!position.hasPixels ||
        !position.hasViewportDimension ||
        !position.hasContentDimensions) {
      return null;
    }
    return position;
  }

  void _evaluatePendingEngagement() {
    if (!_needsEngagement || _userOptedOut || _userIsInteracting) return;
    final target = widget.target;
    if (target != null &&
        (_readyPosition(widget.scrollController) == null ||
            !_targetExists(target))) {
      return;
    }
    final notify = _pendingEngagement == _PendingEngagement.notifying;
    _pendingEngagement = null;
    _setSticking(_shouldEngageTarget(), notify: notify);
    if (_isSticking) _scheduleJumpToTarget();
  }

  bool _shouldEngageTarget() {
    final target = widget.target;
    if (target == null || _readyPosition(widget.scrollController) == null) {
      return false;
    }
    if (target.isBottom) return _isAtBottom();
    return _targetExists(target);
  }

  bool _targetExists(StickTarget target) =>
      target.isBottom ||
      (widget.listController.isAttached &&
          target.index >= 0 &&
          target.index < widget.listController.numberOfItems);

  bool _isAtBottom() {
    final position = _readyPosition(widget.scrollController);
    if (position == null) return false;
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
    final position = _readyPosition(widget.scrollController);
    final renderTarget = _isSticking &&
            !_userIsInteracting &&
            position != null &&
            position.axisDirection != AxisDirection.up
        ? widget.target
        : null;
    widget.listController.renderStickTarget = renderTarget;
  }

  void _optOutFromUserScroll() {
    _userOptedOut = true;
    _pendingEngagement = null;
    _setSticking(false);
  }

  void _beginInteraction() {
    _cancelScheduledJumps();
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
    _evaluatePendingEngagement();

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
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle &&
        _needsEngagement &&
        !_isChangingScrollOffset) {
      // Includes wheel input, which has neither a drag nor an active pointer.
      // jumpTo/animateTo do not emit a non-idle user scroll direction.
      _optOutFromUserScroll();
    } else if (notification is ScrollUpdateNotification) {
      final userDrag =
          notification.dragDetails != null || _activePointers.isNotEmpty;
      if (!_isChangingScrollOffset &&
          (_isSticking || (_needsEngagement && userDrag))) {
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
    if (notification.depth != 0) return false;
    _evaluatePendingEngagement();
    if (_isSticking && !_userIsInteracting) {
      _syncRenderTarget();
      _scheduleJumpToTarget();
    }
    return false;
  }

  void _onContentChanged() {
    // ListController notifies synchronously from layout. Both engagement and
    // target removal can call a consumer that rebuilds its UI. Coalesce the
    // work until after layout and evaluate the current target/controllers then,
    // rather than capturing a request that may have been cancelled meanwhile.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_contentChangeScheduled) return;
      _contentChangeScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _contentChangeScheduled = false;
        if (mounted) _handleContentChanged();
      });
      return;
    }
    _handleContentChanged();
  }

  void _handleContentChanged() {
    _evaluatePendingEngagement();
    if (!_isSticking ||
        _userIsInteracting ||
        !widget.listController.isAttached ||
        widget.listController.hasActiveHeaderAnchor) {
      return;
    }
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

  void _scheduleTargetEngagementAfterLayout(StickTarget target) {
    final generation = ++_jumpGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _jumpGeneration ||
          widget.target != target ||
          _isSticking ||
          _userOptedOut) {
        return;
      }
      _evaluatePendingEngagement();
    });
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
    // Engagement can now resolve in a post-frame content callback without a
    // metrics change. addPostFrameCallback alone would not request the next
    // frame, so its jump could otherwise wait indefinitely.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _jumpToTarget(
    ScrollController scrollController,
    ListController listController,
  ) {
    final position = _readyPosition(scrollController);
    if (position == null || listController.hasActiveHeaderAnchor) {
      return;
    }
    final target = widget.target;
    if (target == null) return;

    late final double desiredOffset;
    if (target.isBottom) {
      desiredOffset = _bottomOffset(position);
    } else {
      if (!listController.isAttached) return;
      if (!_targetExists(target)) {
        _userOptedOut = true;
        _setSticking(false);
        return;
      }
      desiredOffset = listController.estimateOffsetToReveal(
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

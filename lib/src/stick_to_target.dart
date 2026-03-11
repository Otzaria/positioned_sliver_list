import "dart:async";

import "package:flutter/widgets.dart";

import "stick_target.dart";
import "super_sliver_list.dart";

/// Keeps a scroll view pinned to the bottom (or to a specific item) as
/// content grows.
///
/// ## Target states
///
/// The [target] parameter controls all behavior:
///
/// - `null` — **disabled**. Normal scroll view, no corrections, no tracking.
/// - [StickTarget.bottom] — **stick to bottom**. The render object applies
///   zero-lag scroll corrections during layout to keep the trailing edge
///   pinned. A post-frame fallback handles edge cases.
/// - [StickTarget] with an index — **pin a specific item**. The item's top
///   pixel naturally stays put as it grows; a post-frame callback handles
///   initial positioning and drift.
///
/// ## Example — chat with streaming
///
/// ```dart
/// StickToTarget(
///   scrollController: _scrollController,
///   listController: _listController,
///   target: isStreaming
///       ? StickTarget(index: responseIndex, alignment: 0.1,
///           rect: const Rect.fromLTWH(0, 0, 0, 1))
///       : isRunning
///           ? const StickTarget.bottom()
///           : null,
///   child: SuperListView.builder(/* ... */),
/// )
/// ```
class StickToTarget extends StatefulWidget {
  const StickToTarget({
    super.key,
    required this.scrollController,
    required this.listController,
    required this.child,
    this.threshold = 20.0,
    this.target,
    this.onStickStateChanged,
  });

  /// The scroll controller used by the scrollable child.
  final ScrollController scrollController;

  /// The list controller used by the [SuperSliverList] or [SuperListView].
  final ListController listController;

  /// The scrollable child widget.
  final Widget child;

  /// How close to the bottom (in logical pixels) counts as "at the bottom."
  ///
  /// Defaults to 20.0.
  final double threshold;

  /// What to stick to, or `null` to disable.
  ///
  /// See the class documentation for the three states.
  final StickTarget? target;

  /// Called when the stick state changes.
  ///
  /// `true` means the list is stuck (auto-tracking).
  /// `false` means the user has scrolled away or sticking is disabled.
  final ValueChanged<bool>? onStickStateChanged;

  @override
  State<StickToTarget> createState() => _StickToTargetState();
}

class _StickToTargetState extends State<StickToTarget> {
  bool _isStuck = false;
  bool _userIsInteracting = false;
  bool _pendingJump = false;

  /// When true, re-sticking is suppressed until the user actively touches
  /// the screen. Set when we intentionally unstick (e.g. streaming ended).
  bool _requireUserScrollToReStick = false;

  /// Timer for delayed re-evaluation after user interaction ends.
  Timer? _interactionTimer;

  @override
  void initState() {
    super.initState();
    // If target is set at init, start stuck if at bottom (or assume bottom
    // since there are no clients yet).
    if (widget.target != null) {
      _isStuck = true;
      _syncRenderObjectTarget();
    }
    widget.listController.addListener(_onContentChanged);
  }

  @override
  void didUpdateWidget(StickToTarget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.listController != widget.listController) {
      oldWidget.listController.removeListener(_onContentChanged);
      oldWidget.listController.stickTarget = null;
      widget.listController.addListener(_onContentChanged);
      _syncRenderObjectTarget();
    }

    if (widget.target != oldWidget.target) {
      _onTargetChanged(oldWidget.target);
    }
  }

  void _onTargetChanged(StickTarget? oldTarget) {
    final newTarget = widget.target;

    if (newTarget == null) {
      // Disabled — unstick.
      if (_isStuck) _setStuck(false);
      return;
    }

    if (oldTarget == null) {
      // Was disabled, now enabled — re-stick if at bottom.
      if (!_isStuck && _isAtBottom) {
        _setStuck(true);
      }
      _syncRenderObjectTarget();
      if (_isStuck && !newTarget.isBottom) {
        _scheduleJump();
      }
      return;
    }

    // Both old and new are non-null — target type changed.
    if (!oldTarget.isBottom && newTarget.isBottom) {
      // Streaming ended but conversation is still running: transition from
      // item-pinning back to bottom-sticking immediately.
      _requireUserScrollToReStick = false;
      if (!_isStuck) {
        _setStuck(true);
      } else {
        _syncRenderObjectTarget();
      }
      _scheduleJump();
      return;
    }

    _syncRenderObjectTarget();
    if (_isStuck && !newTarget.isBottom) {
      _scheduleJump();
    }
  }

  @override
  void dispose() {
    _interactionTimer?.cancel();
    widget.listController.removeListener(_onContentChanged);
    widget.listController.stickTarget = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool get _isAtBottom {
    if (!widget.scrollController.hasClients) return true;
    return widget.scrollController.position.extentAfter <= widget.threshold;
  }

  void _setStuck(bool value) {
    if (_isStuck == value) return;
    _isStuck = value;
    _syncRenderObjectTarget();
    widget.onStickStateChanged?.call(value);
  }

  /// Tells the render object what to correct for during layout.
  ///
  /// Both bottom and item-based targets get render-object corrections when
  /// anchored at the end. Without this, item-based targets that are clamped
  /// to maxScrollExtent (effectively at the bottom) would lag by one frame
  /// on every content growth.
  void _syncRenderObjectTarget() {
    final shouldCorrect = _isStuck &&
        widget.target != null &&
        !_userIsInteracting;
    widget.listController.stickTarget =
        shouldCorrect ? widget.target : null;
  }

  // ---------------------------------------------------------------------------
  // User interaction — expand-in-place support
  // ---------------------------------------------------------------------------

  void _onInteractionStart() {
    _userIsInteracting = true;
    _requireUserScrollToReStick = false;
    _interactionTimer?.cancel();
    // Suspend render-object correction. Allows expand-in-place: tapping
    // to expand an item won't fight stick-to-bottom corrections.
    widget.listController.stickTarget = null;
  }

  void _onInteractionEnd() {
    // Don't re-sync immediately — expansion animations may still be running.
    // Keep corrections suppressed for a short window, then re-evaluate.
    _interactionTimer?.cancel();
    _interactionTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _userIsInteracting = false;
      if (_isStuck && !_isAtBottom) {
        // Interaction moved us away from the bottom (e.g. expand).
        _setStuck(false);
      } else {
        _syncRenderObjectTarget();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Content changes
  // ---------------------------------------------------------------------------

  void _onContentChanged() {
    if (!_isStuck) return;
    if (widget.target == null) return; // Disabled.
    if (_userIsInteracting && widget.target!.isBottom) return; // Expand-in-place.
    _scheduleJump();
  }

  void _scheduleJump() {
    if (_pendingJump) return;
    _pendingJump = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingJump = false;
      if (!mounted || !_isStuck) return;
      final target = widget.target;
      if (target == null) return;
      if (target.isBottom) {
        _jumpToBottom();
      } else {
        _jumpToTarget();
      }
    });
  }

  /// Fallback for the simple stick-to-bottom case.
  ///
  /// The render object correction handles most cases during layout (zero lag).
  /// This catches edge cases where the correction can't fire, such as when
  /// content first exceeds the viewport.
  void _jumpToBottom() {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    if (pos.extentAfter > widget.threshold) {
      pos.jumpTo(pos.maxScrollExtent);
    }
  }

  /// Jump to keep the target item pinned at the specified viewport position.
  ///
  /// Only scrolls forward — avoids pulling the user back up when extents
  /// shift during streaming.
  void _jumpToTarget() {
    if (!widget.scrollController.hasClients) return;
    if (!widget.listController.isAttached) return;
    final target = widget.target;
    if (target == null || target.isBottom) return;
    if (target.index >= widget.listController.numberOfItems) return;

    final targetOffset = widget.listController.getOffsetToReveal(
      target.index,
      target.alignment,
      rect: target.rect,
    );
    if (!targetOffset.isFinite) return;

    final pos = widget.scrollController.position;
    final clampedOffset = targetOffset.clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );

    // Only scroll forward, never backwards.
    if (clampedOffset > pos.pixels + 1.0) {
      pos.jumpTo(clampedOffset);
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (!widget.scrollController.hasClients) return false;
    if (widget.target == null) return false; // Disabled.

    final atBottom = _isAtBottom;

    if (_isStuck && _userIsInteracting && !atBottom) {
      // User scrolled away from the bottom.
      _setStuck(false);
    } else if (!_isStuck &&
        atBottom &&
        !_requireUserScrollToReStick &&
        widget.target != null) {
      _setStuck(true);
    }

    if (notification is ScrollEndNotification) {
      _userIsInteracting = false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _onInteractionStart(),
      onPointerUp: (_) => _onInteractionEnd(),
      onPointerCancel: (_) => _onInteractionEnd(),
      onPointerPanZoomStart: (_) => _onInteractionStart(),
      onPointerPanZoomEnd: (_) => _onInteractionEnd(),
      behavior: HitTestBehavior.translucent,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.child,
      ),
    );
  }
}

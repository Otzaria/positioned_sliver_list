import "package:flutter/widgets.dart";

import "stick_target.dart";
import "super_sliver_list.dart";

/// Keeps a scroll view pinned to the bottom (or to a specific item) as
/// content grows.
///
/// Wrap a [SuperListView] or [CustomScrollView] containing [SuperSliverList]
/// with this widget to automatically track the bottom of the list.
///
/// When the user can see the bottom of the list and new content arrives,
/// the scroll position automatically tracks the bottom. If the user scrolls
/// away, tracking pauses. If the user scrolls back to the bottom, tracking
/// resumes.
///
/// For the simple "stick to bottom" case, the actual scroll correction happens
/// during layout in the render object, before paint, so the user never sees
/// content at the wrong position. A post-frame fallback handles edge cases.
///
/// For target-based pinning (via [target]), the item's top pixel stays in
/// place naturally as the item grows downward; a post-frame fallback handles
/// the initial positioning and any drift.
///
/// Use [onStickStateChanged] to show or hide a "scroll to bottom" button.
///
/// Example — simple stick to bottom:
/// ```dart
/// StickToTarget(
///   scrollController: _scrollController,
///   listController: _listController,
///   onStickStateChanged: (isStuck) {
///     setState(() => _showScrollToBottomButton = !isStuck);
///   },
///   child: SuperListView.builder(
///     controller: _scrollController,
///     listController: _listController,
///     itemCount: _messages.length,
///     itemBuilder: (context, index) => MessageWidget(_messages[index]),
///   ),
/// )
/// ```
///
/// Example — pin reading position during streaming:
/// ```dart
/// StickToTarget(
///   scrollController: _scrollController,
///   listController: _listController,
///   target: isStreaming
///       ? StickTarget(
///           index: responseIndex,
///           alignment: topPadding / screenHeight,
///           rect: const Rect.fromLTWH(0, 0, 0, 1), // top pixel
///         )
///       : null,
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
  /// When [ScrollPosition.extentAfter] is less than or equal to this value,
  /// the user is considered to be at the bottom and stick-to-bottom
  /// (re-)engages.
  ///
  /// Defaults to 20.0.
  final double threshold;

  /// Optional: instead of sticking to the bottom of the list, pin a specific
  /// item to a specific viewport position.
  ///
  /// When non-null, the widget keeps the specified item pinned at the
  /// specified alignment in the viewport. This is useful for "reading
  /// position" UX during streaming.
  ///
  /// When null, the widget tracks the trailing edge of the list (default
  /// stick-to-bottom behavior).
  final StickTarget? target;

  /// Called when the stick state changes.
  ///
  /// `true` means the list is stuck (auto-tracking).
  /// `false` means the user has scrolled away.
  ///
  /// Use this to show or hide a "scroll to bottom" button.
  final ValueChanged<bool>? onStickStateChanged;

  @override
  State<StickToTarget> createState() => _StickToTargetState();
}

class _StickToTargetState extends State<StickToTarget> {
  bool _isStuck = true;
  bool _userIsInteracting = false;
  bool _pendingJump = false;
  /// When true, re-sticking is suppressed until the user actively scrolls.
  /// Set when we intentionally unstick (e.g. target removed after streaming).
  bool _requireUserScrollToReStick = false;

  @override
  void initState() {
    super.initState();
    _syncStickTarget();
    widget.listController.addListener(_onContentChanged);
  }

  @override
  void didUpdateWidget(StickToTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listController != widget.listController) {
      oldWidget.listController.removeListener(_onContentChanged);
      oldWidget.listController.stickTarget = null;
      widget.listController.addListener(_onContentChanged);
      _syncStickTarget();
    }

    // When target changes, reposition if stuck.
    if (widget.target != oldWidget.target) {
      if (oldWidget.target != null && widget.target == null && _isStuck) {
        // Target was removed (e.g. streaming ended). The user was reading
        // at a specific position — don't yank them to the bottom. Unstick
        // and let them scroll down in their own time.
        _requireUserScrollToReStick = true;
        _setStuck(false);
      } else {
        _syncStickTarget();
        if (_isStuck && widget.target != null) {
          _scheduleJump();
        }
      }
    }
  }

  @override
  void dispose() {
    widget.listController.removeListener(_onContentChanged);
    widget.listController.stickTarget = null;
    super.dispose();
  }

  void _setStuck(bool value) {
    if (_isStuck == value) return;
    _isStuck = value;
    _syncStickTarget();
    widget.onStickStateChanged?.call(value);
  }

  /// Communicates the current stick target to the render object via
  /// [ListController]. For [StickTarget.bottom], the render object applies
  /// zero-lag scroll corrections during layout. For item-based targets,
  /// the post-frame fallback handles positioning.
  void _syncStickTarget() {
    // Render object correction only applies to the simple stick-to-bottom
    // case. When a specific item target is set, the item's top pixel
    // naturally stays put as it grows — no correction needed.
    // Also suppressed during user interaction (expand-in-place).
    final shouldStickToBottom =
        _isStuck && widget.target == null && !_userIsInteracting;
    widget.listController.stickTarget =
        shouldStickToBottom ? const StickTarget.bottom() : null;
  }

  void _onInteractionEnd() {
    // Don't re-sync immediately — expansion animations may still be running.
    // Keep corrections suppressed for a short window, then re-evaluate.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _userIsInteracting = false;
      if (!widget.scrollController.hasClients) {
        _syncStickTarget();
        return;
      }
      final pos = widget.scrollController.position;
      if (_isStuck && pos.extentAfter > widget.threshold) {
        // Interaction moved us away from the bottom (e.g. expand).
        _setStuck(false);
      } else {
        _syncStickTarget();
      }
    });
  }

  /// Called when the list content changes (items added, extents changed).
  void _onContentChanged() {
    if (!_isStuck) return;
    // Don't fight user interaction (e.g. expand-in-place).
    // _userIsInteracting stays true for 500ms after pointer up to cover
    // expansion animations. Target-based jumping is NOT suppressed —
    // only the bottom-jump path.
    if (_userIsInteracting && widget.target == null) return;
    _scheduleJump();
  }

  void _scheduleJump() {
    if (_pendingJump) return;
    _pendingJump = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingJump = false;
      if (!mounted || !_isStuck) return;
      if (widget.target != null) {
        _jumpToTarget();
      } else {
        _jumpToBottom();
      }
    });
  }

  /// Fallback for the simple stick-to-bottom case.
  ///
  /// The render object correction handles most cases during layout (zero lag).
  /// This catches edge cases where the render object correction can't fire,
  /// such as when content first exceeds the viewport (anchoredAtEnd requires
  /// viewportIsScrolled, which is false at scroll position 0).
  void _jumpToBottom() {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    if (pos.extentAfter > widget.threshold) {
      pos.jumpTo(pos.maxScrollExtent);
    }
  }

  /// Jump to keep the target item pinned at the specified viewport position.
  ///
  /// Only scrolls forward (never backwards) to avoid pulling the user back
  /// up when extents shift during streaming.
  void _jumpToTarget() {
    if (!widget.scrollController.hasClients) return;
    if (!widget.listController.isAttached) return;
    final target = widget.target;
    if (target == null) return;
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

    // Only scroll forward, never backwards — avoids yanking the user up
    // when a thinking panel collapses or extents re-estimate.
    if (clampedOffset > pos.pixels + 1.0) {
      pos.jumpTo(clampedOffset);
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (!widget.scrollController.hasClients) return false;

    final pos = widget.scrollController.position;
    final atBottom = pos.extentAfter <= widget.threshold;

    if (_isStuck && _userIsInteracting && !atBottom) {
      // User has scrolled away from the bottom.
      _setStuck(false);
    } else if (!_isStuck && atBottom && !_requireUserScrollToReStick) {
      // Scrolled back to the bottom (user or programmatic).
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
      onPointerDown: (_) {
        _userIsInteracting = true;
        _requireUserScrollToReStick = false;
        // Suspend render-object correction while user is interacting.
        // Allows expand-in-place: tapping to expand an item won't fight
        // stick-to-bottom corrections.
        widget.listController.stickTarget = null;
      },
      onPointerUp: (_) => _onInteractionEnd(),
      onPointerCancel: (_) => _onInteractionEnd(),
      onPointerPanZoomStart: (_) {
        _userIsInteracting = true;
        _requireUserScrollToReStick = false;
        widget.listController.stickTarget = null;
      },
      onPointerPanZoomEnd: (_) => _onInteractionEnd(),
      behavior: HitTestBehavior.translucent,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.child,
      ),
    );
  }
}

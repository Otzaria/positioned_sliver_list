import "dart:async";
import "dart:math" as math;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "element.dart";
import "extent_manager.dart";
import "header_anchor.dart";
import "item_position.dart";
import "layout_budget.dart";
import "layout_pass.dart";
import "perf_flags.dart";
import "sliver_extensions.dart";
import "stick_target.dart";
import "super_sliver_list.dart";

final _log = Logger("SuperSliverList");

/// Pixels within which a pending item target counts as reached.
const _kTargetTolerance = 1e-3;

/// Item extent assumed when no estimator is given or an estimate is invalid.
const kDefaultEstimatedItemExtent = 100.0;

/// Where a target lands when blank space may be added around the content.
class _OverscrollSolution {
  const _OverscrollSolution(this.pixels, this.leading, this.trailing);

  /// Scroll pixels of the viewport.
  final double pixels;

  /// Blank space before the first item.
  final double leading;

  /// Blank space after the last item.
  final double trailing;
}

/// An item whose leading edge should be placed at [alignment] of the viewport
/// plus [offset] pixels. Resolved during layout, before paint.
class _PendingItemTarget {
  _PendingItemTarget({
    required this.index,
    required this.alignment,
    required this.offset,
    required this.owner,
    this.targetRectResolver,
  });

  final int index;
  final double alignment;
  final double offset;
  final Object owner;
  final TargetRectResolver? targetRectResolver;
  final completer = Completer<void>();
}

/// When providing child scroll offset for a child that is not currently visible
/// the list will estimate offset for the child and then will attempt to correct
/// the correct the scroll offset during layout;
class _ChildScrollOffsetEstimation {
  _ChildScrollOffsetEstimation({
    required this.owner,
    required this.index,
    required this.offset,
    required this.extent,
    required this.precedingScrollExtent,
    required this.revealingRect,
    required this.alignment,
    required this.childObstructionExtent,
  });

  final Object? owner;

  /// Index of child for which the offset was estimated.
  final int index;

  /// Estimated offset returned from childScrollOffset. This will be compared
  /// to actual child offset during layout and if different, the scroll offset
  /// will be corrected.
  final double offset;

  /// Last known extent of child when determining estimated scroll offset. Depending
  /// on child alignment within viewport the extent difference my affect the
  /// scroll offset correction.
  final double extent;

  /// Preceding scroll extent at the moment when offset was estimated. Used to compensate
  /// for change in preceding sliver extent change during layout.
  final double precedingScrollExtent;

  /// Whether the entire element or only a rect should be revealed.
  final bool revealingRect;

  /// Child alignment within viewport.
  final double alignment;

  /// Child obstruction extent when estimation was made.
  final ChildObstructionExtent childObstructionExtent;

  /// Scroll offset of viewport when estimation was made.
  double? viewportScrollOffset;
}

class RenderSuperSliverList extends RenderSliverMultiBoxAdaptor
    implements ExtentPrecalculationPolicyDelegate {
  @pragma("vm:prefer-inline")
  static SliverMultiBoxAdaptorParentData _parentDataOf(RenderObject child) {
    return child.parentData! as SliverMultiBoxAdaptorParentData;
  }

  @pragma("vm:prefer-inline")
  static int _indexOf(RenderBox child) {
    return _parentDataOf(child).index!;
  }

  RenderSuperSliverList({
    required super.childManager,
    ExtentPrecalculationPolicy? extentPrecalculationPolicy,
    required this.estimateExtent,
    Object? estimationKey,
    required this.delayPopulatingCacheArea,
    required this.layoutKeptAliveChildren,
    required InitialScrollPosition initialScrollPosition,
    int? initialIndex,
    double initialAlignment = 0.0,
    double initialOffset = 0.0,
    TargetRectResolver? initialTargetRectResolver,
    OverscrollToTarget overscrollToTarget = OverscrollToTarget.none,
  }) : _estimationKey = estimationKey,
       _overscrollToTarget = overscrollToTarget,
       _initialScrollPosition = initialScrollPosition,
       _didResolveInitialScrollPosition =
           initialScrollPosition == InitialScrollPosition.start {
    this.extentPrecalculationPolicy = extentPrecalculationPolicy;
    if (initialIndex != null) {
      _pendingTarget = _PendingItemTarget(
        index: initialIndex,
        alignment: initialAlignment,
        offset: initialOffset,
        targetRectResolver: initialTargetRectResolver,
        owner: _extentManager.beginReveal(),
      );
      _didResolveInitialScrollPosition = true;
    }
  }

  @override
  SuperSliverMultiBoxAdaptorElement get childManager =>
      super.childManager as SuperSliverMultiBoxAdaptorElement;

  set extentPrecalculationPolicy(ExtentPrecalculationPolicy? value) {
    if (value == _extentPrecalculationPolicy) {
      return;
    }
    _extentPrecalculationPolicy?.removeDelegate(this);
    _extentPrecalculationPolicy = value;
    _extentPrecalculationPolicy?.addDelegate(this);
  }

  ExtentPrecalculationPolicy? _extentPrecalculationPolicy;
  ExtentEstimationProvider estimateExtent;
  Object? _estimationKey;

  Object? get estimationKey => _estimationKey;
  set estimationKey(Object? value) {
    if (value == _estimationKey) return;
    _estimationKey = value;
    _extentManager.markAllDirty();
    markNeedsLayout();
  }

  bool delayPopulatingCacheArea;
  bool layoutKeptAliveChildren = false;
  InitialScrollPosition _initialScrollPosition;
  bool _didResolveInitialScrollPosition;

  InitialScrollPosition get initialScrollPosition => _initialScrollPosition;
  set initialScrollPosition(InitialScrollPosition value) {
    if (_initialScrollPosition == value) {
      return;
    }
    _initialScrollPosition = value;
    _didResolveInitialScrollPosition = value == InitialScrollPosition.start;
    markNeedsLayout();
  }

  bool _shouldPrecalculateExtents(LayoutPass pass) {
    final state = pass.getLayoutState(this);
    if (SuperSliverListPerfFlags.cachedShouldPrecalculateExtents) {
      // The result is cached per layout pass; skip the viewport walk and
      // context allocation when it is already present. This method is called
      // repeatedly per pass (also once per invisible sliver through
      // _shouldSkipExtentPrecalculationForInvisibleList).
      if (state.precalculateExtents == null) {
        final viewport = getViewport()!;
        final position = viewport.offset as ScrollPosition;
        final context = ExtentPrecalculationContext(
          viewportMainAxisExtent: position.hasViewportDimension
              ? position.viewportDimension
              : null,
          contentTotalExtent: position.hasContentDimensions
              ? position.maxScrollExtent - position.minScrollExtent
              : null,
          numberOfItems: _extentManager.numberOfItems,
          numberOfItemsWithEstimatedExtent:
              _extentManager.numberOfItemsWithEstimatedExtent,
        );
        state.precalculateExtents =
            _extentPrecalculationPolicy?.shouldPrecalculateExtents(context) ??
            false;
      }
      return state.precalculateExtents!;
    }
    final viewport = getViewport()!;
    final position = viewport.offset as ScrollPosition;
    final context = ExtentPrecalculationContext(
      viewportMainAxisExtent: position.hasViewportDimension
          ? position.viewportDimension
          : null,
      contentTotalExtent: position.hasContentDimensions
          ? position.maxScrollExtent - position.minScrollExtent
          : null,
      numberOfItems: _extentManager.numberOfItems,
      numberOfItemsWithEstimatedExtent:
          _extentManager.numberOfItemsWithEstimatedExtent,
    );
    state.precalculateExtents ??=
        _extentPrecalculationPolicy?.shouldPrecalculateExtents(context) ??
        false;
    return state.precalculateExtents!;
  }

  // If this sliver list is not visible it should not precalculate extents
  // while there are any visible lists that have dirty extents and want
  // extent precalculation.
  bool _shouldSkipExtentPrecalculationForInvisibleList(LayoutPass pass) {
    for (final sliver in pass.slivers) {
      if (sliver.firstChild != null &&
          sliver._extentManager.hasDirtyItems &&
          sliver._shouldPrecalculateExtents(pass)) {
        return true;
      }
    }
    return false;
  }

  _PendingItemTarget? _pendingTarget;

  OverscrollToTarget _overscrollToTarget;

  bool get _allowOverscrollToTarget =>
      _overscrollToTarget != OverscrollToTarget.none;

  /// Whether a jump may add blank space before the first or after the last
  /// item so that its target lands exactly where requested.
  OverscrollToTarget get overscrollToTarget => _overscrollToTarget;
  set overscrollToTarget(OverscrollToTarget value) {
    if (value == _overscrollToTarget) {
      return;
    }
    _overscrollToTarget = value;
    if (value != OverscrollToTarget.always) {
      _reservedLeadingSpace = 0.0;
      _trailingSpace = 0.0;
      _pinnedIndex = null;
      // Removing the leading space is done by the next layout.
      holdOverscrollSpace = false;
    }
    markNeedsLayout();
  }

  // Blank space before the first item. Item positions are kept in content
  // coordinates; everything outside layout sees them shifted by this amount.
  double _leadingSpace = 0.0;

  // State of the last completed layout, to tell a change of the leading
  // padding around this sliver from a scroll.
  ({double pixels, double padding, double scrollOffset})? _lastOuterLayout;

  double get _leadingPadding {
    final parent = this.parent;
    return parent is RenderSliverEdgeInsetsPadding ? parent.beforePadding : 0.0;
  }

  // Viewport scroll offset of the last layout; positions read from the render
  // tree after a later scroll are stale until the next layout.
  double? _layoutPixels;

  double? get _viewportPixels {
    final offset = getViewport()?.offset;
    return offset != null && offset.hasPixels ? offset.pixels : null;
  }

  // Blank space after the last item, part of this sliver's scroll extent.
  double _trailingSpace = 0.0;

  // Leading space requested before an animation; applied by the next layout
  // together with a correction that keeps the content in place.
  double _reservedLeadingSpace = 0.0;

  // The item a jump placed while blank space exists; it is the scroll anchor
  // until the space is gone.
  int? _pinnedIndex;

  /// While true (during a programmatic animation) the blank space does not
  /// shrink when the viewport moves into the content.
  bool holdOverscrollSpace = false;

  /// Blank space currently added before the first and after the last item.
  ({double leading, double trailing}) get overscrollSpace =>
      (leading: _leadingSpace, trailing: _trailingSpace);

  // Constraints in content coordinates, active while laying out.
  SliverConstraints? _contentConstraintsOverride;

  // Content constraints of the last layout, when there was leading space.
  SliverConstraints? _lastContentConstraints;

  @override
  SliverConstraints get constraints =>
      _contentConstraintsOverride ?? super.constraints;

  T _inContentSpace<T>(T Function() compute) {
    final content = _lastContentConstraints;
    if (content == null || _contentConstraintsOverride != null) {
      return compute();
    }
    _contentConstraintsOverride = content;
    try {
      return compute();
    } finally {
      _contentConstraintsOverride = null;
    }
  }

  SliverConstraints _contentConstraintsFor(
    SliverConstraints outer,
    double leading,
  ) {
    final beforePaint = calculatePaintOffset(outer, from: 0, to: leading);
    final beforeCache = calculateCacheOffset(outer, from: 0, to: leading);
    return outer.copyWith(
      scrollOffset: math.max(0.0, outer.scrollOffset - leading),
      cacheOrigin: math.min(0.0, outer.cacheOrigin + leading),
      overlap: math.max(0.0, outer.overlap - beforePaint),
      remainingPaintExtent: outer.remainingPaintExtent - beforePaint,
      remainingCacheExtent: outer.remainingCacheExtent - beforeCache,
      precedingScrollExtent: leading + outer.precedingScrollExtent,
    );
  }

  void _applyLeadingSpaceToGeometry(SliverConstraints outer, double leading) {
    final content = geometry!;
    final beforePaint = calculatePaintOffset(outer, from: 0, to: leading);
    final beforeCache = calculateCacheOffset(outer, from: 0, to: leading);
    final paintExtent = math.min(
      beforePaint + content.paintExtent,
      outer.remainingPaintExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: leading + content.scrollExtent,
      paintExtent: paintExtent,
      layoutExtent: math.min(beforePaint + content.layoutExtent, paintExtent),
      cacheExtent: math.min(
        beforeCache + content.cacheExtent,
        outer.remainingCacheExtent,
      ),
      maxPaintExtent: leading + content.maxPaintExtent,
      hitTestExtent: paintExtent,
      hasVisualOverflow: content.hasVisualOverflow,
    );
  }

  /// Where the item laid out at [layoutOffset] (content coordinates) lands
  /// with blank space allowed, and how much space that needs. Null when the
  /// sliver does not grow forward from the viewport's center.
  _OverscrollSolution? _solveOverscroll(
    double layoutOffset,
    double alignment,
    double offset,
  ) {
    if (constraints.growthDirection != GrowthDirection.forward) {
      return null;
    }
    final viewport = getViewport();
    if (viewport == null) {
      return null;
    }
    final extent = constraints.viewportMainAxisExtent;
    final finiteExtent = extent.isFinite ? extent : 0.0;
    // Start of this sliver in scroll pixels, without leading space.
    final origin =
        _centerOrigin(viewport) +
        constraints.precedingScrollExtent -
        _leadingSpace;
    final target = layoutOffset - alignment * finiteExtent - offset;
    // Content before this sliver (padding, other slivers) is used before
    // blank space is added.
    final position = viewport.offset;
    final minPixels =
        position is ScrollPosition && position.hasContentDimensions
        ? math.min(position.minScrollExtent, origin)
        : math.min(0.0, origin);
    if (!extent.isFinite) {
      return _OverscrollSolution(minPixels, 0.0, 0.0);
    }
    final room = origin - minPixels;
    if (_overscrollToTarget ==
        OverscrollToTarget.matchScrollablePositionedList) {
      return _matchScrollablePositionedList(
        minPixels: minPixels,
        desired: room + target,
        content: room + _totalExtent() + _trailingPaddingExtent(),
        viewportExtent: finiteExtent,
      );
    }
    final leading = math.max(0.0, -(target + room));
    final pixels = leading > 0 ? minPixels : origin + target;
    var trailing = 0.0;
    var clampedPixels = pixels;
    final maxPixels =
        origin +
        leading +
        _totalExtent() +
        _trailingPaddingExtent() -
        finiteExtent;
    if (_isTrailingSliver()) {
      trailing = math.max(0.0, pixels - maxPixels);
    } else {
      clampedPixels = math.min(pixels, math.max(origin, maxPixels));
    }
    return _OverscrollSolution(clampedPixels, leading, trailing);
  }

  /// The clamping of `scrollable_positioned_list`: its viewport anchors the
  /// target at pixel 0 and limits the scroll range to
  /// `max(min(0, top), bottom)` and `min(top, max)`, where `top` and `bottom`
  /// are the usual content limits (unbounded_viewport, viewport.dart:186-192).
  /// In content coordinates ([desired] and the result measured from the start
  /// of the content):
  ///
  /// - max = max(min(desired, 0), content - viewport)
  /// - min = min(0, max)
  ///
  /// So the position is clamped to the content, except that content shorter
  /// than the viewport may start below the leading edge, at most until its end
  /// reaches the trailing edge. No space is ever added after the content.
  _OverscrollSolution _matchScrollablePositionedList({
    required double minPixels,
    required double desired,
    required double content,
    required double viewportExtent,
  }) {
    final maxScroll = math.max(
      math.min(desired, 0.0),
      content - viewportExtent,
    );
    final minScroll = math.min(0.0, maxScroll);
    final scroll = desired.clamp(minScroll, maxScroll);
    if (scroll < 0) {
      return _OverscrollSolution(minPixels, -scroll, 0.0);
    }
    return _OverscrollSolution(minPixels + scroll, 0.0, 0.0);
  }

  /// Blank space after the last item that the viewport currently shows.
  double _trailingSpaceNeeded() {
    if (!_isTrailingSliver()) {
      return 0.0;
    }
    final visibleEnd =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    return math.max(
      0.0,
      visibleEnd - _totalExtent() - _trailingPaddingExtent(),
    );
  }

  /// Requests the blank space a jump to [index] needs before an animation to
  /// it starts, so the animation can reach the target.
  void reserveOverscrollSpace(
    int index,
    double alignment,
    double offset, {
    TargetRectResolver? targetRectResolver,
  }) {
    if (!_allowOverscrollToTarget || !attached || geometry == null) {
      return;
    }
    final count = _extentManager.numberOfItems;
    if (count == 0) {
      return;
    }
    final solution = _inContentSpace(() {
      final clamped = index.clamp(0, count - 1);
      final child = _liveChildForIndex(clamped);
      final layoutOffset = child != null
          ? childScrollOffset(child)! +
                _targetOffsetInItem(clamped, child, targetRectResolver)
          : _extentManager.offsetForIndex(clamped);
      return _solveOverscroll(layoutOffset, alignment, offset);
    });
    if (solution == null) {
      return;
    }
    _trailingSpace = math.max(_trailingSpace, solution.trailing);
    _reservedLeadingSpace = math.max(_leadingSpace, solution.leading);
    markNeedsLayout();
  }

  /// Places the leading edge of the item at [index] at [alignment] of the
  /// viewport plus [offset] pixels, before the next paint.
  ///
  /// The returned future completes once the target was reached, replaced or
  /// canceled.
  Future<void> jumpToIndex(
    int index,
    double alignment,
    double offset, {
    TargetRectResolver? targetRectResolver,
  }) {
    _completePendingTarget();
    _childScrollOffsetEstimation = null;
    final target = _PendingItemTarget(
      index: index,
      alignment: alignment,
      offset: offset,
      owner: _extentManager.beginReveal(),
      targetRectResolver: targetRectResolver,
    );
    _pendingTarget = target;
    if (_extentManager.isLocked) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached && identical(_pendingTarget, target)) {
          _markNeedsLayoutWithAncestors();
        }
      });
    } else {
      markNeedsLayout();
    }
    return target.completer.future;
  }

  bool get hasPendingTarget => _pendingTarget != null;

  void _completePendingTarget() {
    final target = _pendingTarget;
    _pendingTarget = null;
    if (target != null && !target.completer.isCompleted) {
      target.completer.complete();
    }
  }

  @override
  void dispose() {
    _completePendingTarget();
    _headerAnchorHandle?.cancel();
    super.dispose();
    _extentPrecalculationPolicy?.removeDelegate(this);
  }

  ExtentManager get _extentManager => childManager.extentManager;
  SliverConstraints? previousConstraints;

  RenderBox? _header;
  HeaderAnchorHandle? _headerAnchorHandle;
  double _headerViewportY = 0;

  /// Other slivers can change range after this list's layout, so only a sole
  /// vertical list with optional padding supports the header constraint.
  HeaderAnchorHandle? preserveHeader(RenderBox header) {
    _headerAnchorHandle?.cancel();
    final viewport = getViewport();
    if (viewport == null ||
        !header.attached ||
        !header.hasSize ||
        constraints.axisDirection != AxisDirection.down ||
        constraints.growthDirection != GrowthDirection.forward ||
        _headerItem(header) == null) {
      return null;
    }
    var supported = true;
    void check(RenderObject object) {
      if (identical(object, this)) return;
      if (object is RenderViewport ||
          object is RenderShrinkWrappingViewport ||
          object is RenderSliverPadding) {
        object.visitChildren(check);
      } else {
        supported = false;
      }
    }

    check(viewport);
    if (!supported) return null;
    final position = viewport.offset;
    if (position is! ScrollPosition || !position.hasContentDimensions) {
      return null;
    }
    _header = header;
    _headerViewportY = header.localToGlobal(Offset.zero, ancestor: viewport).dy;
    _childScrollOffsetEstimation = null;
    late final HeaderAnchorHandle handle;
    handle = HeaderAnchorHandle(() {
      if (!identical(_headerAnchorHandle, handle)) return;
      _header = null;
      _headerAnchorHandle = null;
      if (!_extentManager.isLocked) markNeedsLayout();
    });
    _headerAnchorHandle = handle;
    markNeedsLayout();
    return handle;
  }

  RenderBox? _headerItem(RenderBox header) {
    if (!header.attached) return null;
    RenderObject? item = header;
    while (item != null && item.parent != this) {
      // Do not cross a nested scrollable to anchor its contents.
      if (item is RenderViewportBase) return null;
      item = item.parent;
    }
    if (item is! RenderBox || _parentDataOf(item).keptAlive) return null;
    return item;
  }

  double? _headerCorrection() {
    final header = _header;
    if (header == null) return null;
    final item = _headerItem(header);
    if (item == null || !header.hasSize) {
      _headerAnchorHandle?.cancel();
      return null;
    }
    final localY = header.localToGlobal(Offset.zero, ancestor: item).dy;
    final itemOffset = childScrollOffset(item);
    if (!localY.isFinite || itemOffset == null) return null;
    final position = getViewport()!.offset as ScrollPosition;
    final desired =
        constraints.precedingScrollExtent +
        itemOffset +
        localY -
        _headerViewportY;
    // Read padding itself, not maxScrollExtent: a short list reports zero max
    // and cannot distinguish trailing padding from unused viewport space.
    final maxOffset = math.max(
      position.minScrollExtent,
      constraints.precedingScrollExtent +
          _totalExtent() +
          _trailingPaddingExtent() -
          constraints.viewportMainAxisExtent,
    );
    return desired.clamp(position.minScrollExtent, maxOffset) - position.pixels;
  }

  _ChildScrollOffsetEstimation? _childScrollOffsetEstimation;

  void sanitizeChildScrollOffsetEstimation(RenderViewportBase viewport) {
    if (_childScrollOffsetEstimation?.owner != _extentManager.revealOwner) {
      _childScrollOffsetEstimation = null;
    }
    if (_childScrollOffsetEstimation != null) {
      final offset = viewport.offset.pixels;
      if (_childScrollOffsetEstimation!.viewportScrollOffset != null &&
          (_childScrollOffsetEstimation!.viewportScrollOffset! - offset).abs() >
              1.0) {
        if (_log.isLoggable(Level.FINE)) {
          _log.fine(
            "Viewport scroll offset changed since estimation. Discarding",
          );
        }
        _childScrollOffsetEstimation = null;
      }
    }
  }

  // Outside layout, offsets include the leading blank space.
  @override
  double? childScrollOffset(covariant RenderObject child) {
    final offset = _contentChildScrollOffset(child);
    if (offset == null || _contentConstraintsOverride != null) {
      return offset;
    }
    return offset + _leadingSpace;
  }

  double? _contentChildScrollOffset(RenderObject child) {
    double? finish(double? value) {
      return value;
    }

    final renderBox = child as RenderBox;
    if (SuperSliverListPerfFlags.fastChildScrollOffsetLookup) {
      // O(1) membership check. Live children (the only ones the superclass
      // can answer for) are attached to this sliver with keptAlive == false.
      // Kept-alive children have keptAlive == true and _FakeRenderObject is
      // excluded explicitly - both fall through to the estimation path below,
      // matching the behavior of the linear scan.
      if (child is! _FakeRenderObject &&
          child.parent == this &&
          !_parentDataOf(child).keptAlive) {
        return super.childScrollOffset(renderBox);
      }
    } else {
      for (var c = firstChild; c != null; c = childAfter(c)) {
        if (renderBox == c) {
          return super.childScrollOffset(renderBox);
        }
      }
    }

    final offsetToRevealContext = OffsetToRevealContext.current();
    if (offsetToRevealContext == null) {
      return super.childScrollOffset(child);
    }

    // Trying to query child offset of child that's not currently visible;
    // Assume this is from viewPort.getOffsetToReveal, in which case we'll
    // estimate the offset, but also remember the index and offset so that
    // we can possibly correct scrollOffset in next performLayout call.
    final index = _indexOf(renderBox);

    assert(offsetToRevealContext.viewport == getViewport());

    if (offsetToRevealContext.estimationOnly == true) {
      return _extentManager.offsetForIndex(index);
    }

    // This should be as simple as reading precedingScrollExtent from the constraints,
    // but it is not. precedingScrollExtent is not included in SliverConstraints operator==
    // which means that all other fields being same the constraints will not be updated.
    // As a workaround, the preceding scroll extent is determined by summing all preceding
    // sliver scroll extents and the difference between preceding scroll extent of top
    // level parent of this sliver (viewport) and this sliver precedingScrollExtent.
    double getActualPrecedingScrollExtent() {
      final viewport = getViewport()!;
      double offset = 0;
      bool finished = false;
      if (SuperSliverListPerfFlags.fastPrecedingScrollExtent) {
        // Single upward walk (O(depth)) finds the direct viewport child that
        // contains this sliver, instead of walking the ancestor chain once
        // per preceding viewport child (O(children * depth)).
        RenderObject topLevel = this;
        var p = parent;
        while (p != null && p != viewport) {
          topLevel = p;
          p = p.parent;
        }
        viewport.visitChildren((child) {
          if (finished) {
            return;
          }
          if (child is! RenderSliver) {
            assert(false, "Unexpected non-sliver child of viewport");
            return;
          }
          if (child == topLevel) {
            if (child != this) {
              offset +=
                  constraints.precedingScrollExtent -
                  child.constraints.precedingScrollExtent;
            }
            finished = true;
            return;
          }
          offset += child.geometry!.scrollExtent;
        });
      } else {
        bool isParent(RenderObject object) {
          var parent = this.parent;
          while (parent != null && parent != viewport) {
            if (parent == object) {
              return true;
            }
            parent = parent.parent;
          }
          return false;
        }

        viewport.visitChildren((child) {
          if (finished) {
            return;
          }
          if (child is! RenderSliver) {
            assert(false, "Unexpected non-sliver child of viewport");
            return;
          }
          if (isParent(child)) {
            final difference =
                constraints.precedingScrollExtent -
                child.constraints.precedingScrollExtent;
            offset += difference;
            finished = true;
            return;
          }
          if (child == this) {
            finished = true;
            return;
          }
          offset += child.geometry!.scrollExtent;
        });
      }
      assert(finished, "Viewport doesn't seem to contain current sliver?");
      return offset;
    }

    final precedingScrollExtent = getActualPrecedingScrollExtent();
    if (constraints.precedingScrollExtent != precedingScrollExtent) {
      _log.fine(
        () =>
            "Constraints have outdated preceding scroll extent ${constraints.precedingScrollExtent.format()}, actual is ${precedingScrollExtent.format()}",
      );
    }

    _childScrollOffsetEstimation = _ChildScrollOffsetEstimation(
      owner: _extentManager.revealOwner ?? _extentManager.beginReveal(),
      index: index,
      offset: _extentManager.offsetForIndex(index),
      extent: _extentManager.getExtent(index),
      precedingScrollExtent: precedingScrollExtent,
      revealingRect: offsetToRevealContext.rect != null,
      alignment: offsetToRevealContext.alignment,
      childObstructionExtent: child.getParentChildObstructionExtent(),
    );

    assert(offsetToRevealContext.estimationOnly == false);
    offsetToRevealContext.registerOffsetResolvedCallback((value) {
      final offset = value.offset;
      // Remember the target scroll position. Scroll correction will only be enforced
      // when the viewport scroll position is the same as when the estimation was made.
      // This is enforced by [LayoutPass.sanitizeChildScrollOffsetEstimation].
      final position = getViewport()!.offset as ScrollPosition;
      // Only remember position if it is within scroll extent. Otherwise
      // it will be corrected and it is not possible to check against it.
      if (offset >= position.minScrollExtent &&
          offset <= position.maxScrollExtent) {
        _childScrollOffsetEstimation?.viewportScrollOffset = offset;
      }
    });

    _log.fine(
      () =>
          "$_logIdentifier remembering estimated offset ${_childScrollOffsetEstimation!.offset} for child $index (preceding extent ${constraints.precedingScrollExtent})",
    );
    final slivers = getSuperSliverLists();
    for (final sliver in slivers) {
      sliver.markNeedsLayout();
      if (sliver != this) {
        // Only one sliver should have active estimation.
        sliver._childScrollOffsetEstimation = null;
      } else if (sliver == this) {
        break;
      }
    }
    return finish(_childScrollOffsetEstimation!.offset);
  }

  /// Moves the layout offset of this and subsequent children by the given delta.
  void _shiftLayoutOffsets(RenderBox? child, double delta) {
    while (child != null) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.layoutOffset != null) {
        data.layoutOffset = data.layoutOffset! + delta;
      }
      child = childAfter(child);
    }
  }

  /// Layouts single child. Will return scrollOffset of the child, or `null`
  /// if scroll offset couldn't have been determined.
  ///
  /// Resets the layoutOffset of the child after.
  double? layoutChild(
    RenderBox child,
    BoxConstraints childConstraints, {
    RenderBox? lastChildWithScrollOffset,
  }) {
    final parentData = _parentDataOf(child);

    double? offset = parentData.layoutOffset ?? childScrollOffset(child);

    // If child offset can't be determined, there's no point laying out the child.
    if (offset == null && lastChildWithScrollOffset == null) {
      return null;
    }

    if (offset == null) {
      final lastData = _parentDataOf(lastChildWithScrollOffset!);
      final lastOffset =
          lastData.layoutOffset ?? childScrollOffset(lastChildWithScrollOffset);
      if (lastOffset == null) {
        return null;
      }
      final trailingExtent = paintExtentOf(lastChildWithScrollOffset);
      offset = lastOffset + trailingExtent;
      parentData.layoutOffset = offset;
    }

    child.layout(childConstraints, parentUsesSize: true);
    final childExtent = paintExtentOf(child);
    parentData.layoutOffset ??= offset;
    _extentManager.setExtent(parentData.index!, childExtent);
    final nextChild = childAfter(child);
    if (nextChild != null) {
      _parentDataOf(nextChild).layoutOffset = null;
    }
    return parentData.layoutOffset ?? offset;
  }

  static SuperSliverListLayoutBudget? _currentLayoutBudget;

  SuperSliverListLayoutBudget _getLayoutBudget() {
    if (_currentLayoutBudget == null) {
      _currentLayoutBudget = SuperSliverList.layoutBudget;
      Future.microtask(() {
        _currentLayoutBudget!.reset();
        _currentLayoutBudget = null;
      });
    }
    return _currentLayoutBudget!;
  }

  double _layoutKeptAliveChildren() {
    if (!layoutKeptAliveChildren) {
      return 0.0;
    }
    double correction = 0.0;
    final firstChildIndex = firstChild != null ? _indexOf(firstChild!) : -1;
    if (SuperSliverListPerfFlags.optimizedKeptAliveLayout) {
      // Single traversal: kept-alive children are collected while being laid
      // out, then their layout offsets are updated from the collected list
      // instead of re-visiting every child (live + kept alive) a second
      // time. The BoxConstraints conversion is also hoisted out of the
      // per-child visitor.
      final childConstraints = constraints.asBoxConstraints();
      List<RenderBox>? keptAlive;
      visitChildren((child_) {
        final child = child_ as RenderBox;
        final data = child.parentData! as SliverMultiBoxAdaptorParentData;
        if (data.keptAlive) {
          (keptAlive ??= <RenderBox>[]).add(child);
          final index = _indexOf(child);
          final prevExtent = _extentManager.getExtent(index);
          child.layout(childConstraints, parentUsesSize: true);
          final extentAfter = paintExtentOf(child);
          _extentManager.setExtent(index, extentAfter);
          if (index < firstChildIndex) {
            correction += extentAfter - prevExtent;
          }
        }
      });
      // Update layout offsets after all extents have been updated.
      final list = keptAlive;
      if (list != null) {
        for (final child in list) {
          final data = child.parentData! as SliverMultiBoxAdaptorParentData;
          data.layoutOffset = _extentManager.offsetForIndex(_indexOf(child));
        }
      }
      return correction;
    }
    // First step - layout all kept alive children.
    visitChildren((child_) {
      final child = child_ as RenderBox;
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.keptAlive) {
        final index = _indexOf(child);
        final constraints = this.constraints.asBoxConstraints();
        final prevExtent = _extentManager.getExtent(index);
        child.layout(constraints, parentUsesSize: true);
        final extentAfter = paintExtentOf(child);
        _extentManager.setExtent(index, extentAfter);
        if (index < firstChildIndex) {
          correction += extentAfter - prevExtent;
        }
      }
    });
    // Second step - update layout offset. This is done after all children have
    // been laid out.
    visitChildren((child_) {
      final child = child_ as RenderBox;
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.keptAlive) {
        final index = _indexOf(child);
        final data = child.parentData! as SliverMultiBoxAdaptorParentData;
        data.layoutOffset = _extentManager.offsetForIndex(index);
      }
    });
    return correction;
  }

  /// Calculates layout info for dirty items. Returns scroll offset correction.
  double _calculatePendingLayout({
    required LayoutPass layoutPass,
    required bool allowScrollOffsetCorrection,
    required bool precalculateExtents,
  }) {
    final SliverConstraints constraints = this.constraints;

    if (!_extentManager.hasDirtyItems || !precalculateExtents) {
      return 0;
    }

    double correction = 0;

    final budget = _getLayoutBudget();

    final childCount = childManager.childCount;

    budget.beginLayout();

    if (SuperSliverListPerfFlags.batchExtentPrecalculation) {
      // Single layout callback and build scope wrapping the entire measuring
      // loop; the per-item variant below pays for both once per item.
      invokeLayoutCallback((_) {
        childManager.measureExtentsBatch(constraints, (measure) {
          while (precalculateExtents &&
              _extentManager.hasDirtyItems &&
              budget.shouldLayoutNextItem()) {
            var start = _extentManager.cleanRangeStart;
            var end = _extentManager.cleanRangeEnd;

            if (start == null && end == null) {
              start = childCount;
              end = childCount;
            } else {
              start = start!;
              end = end!;
            }

            var didMeasure = false;

            // Only layout items before clean range if scroll correction is allowed.
            // There is limited amount of scroll correction attempts during layout pass
            // and if exceeded viewport layout will throw an exception.
            if (start > 0 && allowScrollOffsetCorrection) {
              final index = start - 1;
              final extent = measure(index);
              final prevExtent = _extentManager.getExtent(index);
              _extentManager.setExtent(index, extent);
              correction += extent - prevExtent;
              didMeasure = true;
            }

            if (end < childCount - 1) {
              final index = end + 1;
              final extent = measure(index);
              _extentManager.setExtent(index, extent);
              didMeasure = true;
            }

            if (!didMeasure) {
              // No progress possible (e.g. only leading dirty items remain but
              // scroll offset correction is not allowed). Don't spin until the
              // budget expires.
              break;
            }
          }
        });
      });
    } else {
      while (precalculateExtents &&
          _extentManager.hasDirtyItems &&
          budget.shouldLayoutNextItem()) {
        var start = _extentManager.cleanRangeStart;
        var end = _extentManager.cleanRangeEnd;

        if (start == null && end == null) {
          start = childCount;
          end = childCount;
        } else {
          start = start!;
          end = end!;
        }

        // Only layout items before clean range if scroll correction is allowed.
        // There is limited amount of scroll correction attempts during layout pass
        // and if exceeded viewport layout will throw an exception.
        if (start > 0 && allowScrollOffsetCorrection) {
          final index = start - 1;
          invokeLayoutCallback((_) {
            final extent = childManager.measureExtentForItem(
              index,
              constraints,
            );
            final prevExtent = _extentManager.getExtent(index);
            _extentManager.setExtent(index, extent);
            correction += extent - prevExtent;
          });
        }

        if (end < childCount - 1) {
          final index = end + 1;
          invokeLayoutCallback((_) {
            final extent = childManager.measureExtentForItem(
              index,
              constraints,
            );
            _extentManager.setExtent(index, extent);
          });
        }
      }
    }

    budget.endLayout();

    if (precalculateExtents && _extentManager.hasDirtyItems) {
      if (_log.isLoggable(Level.FINER)) {
        _log.finer(
          "Did not manage to calculate extents within budget. Scheduling layout pass.",
        );
      }
      _markNeedsLayoutDelayed(layoutPass);
    }
    return correction;
  }

  // Set while a delayed layout callback is pending; layout can run several
  // times per frame and one callback, with the latest pass, is enough.
  LayoutPass? _delayedLayoutPass;

  void _markNeedsLayoutDelayed(LayoutPass pass) {
    final isScheduled = _delayedLayoutPass != null;
    _delayedLayoutPass = pass;
    if (isScheduled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pass = _delayedLayoutPass!;
      _delayedLayoutPass = null;
      final thisIndex = pass.sliversDuringLayout.indexOf(this);
      // When scheduling layout pass, make sure that all slivers laid out after this
      // also get their layout invalidated. This is necessary because this sliver layout
      // may change precedingScrollExtent of slivers after. Preceding scroll extent is used
      // during correction for jump to index estimation.
      for (final s in pass.slivers) {
        final theirIndex = pass.sliversDuringLayout.indexOf(s);
        if (theirIndex == -1 || theirIndex >= thisIndex) {
          s._markNeedsLayoutWithAncestors();
        }
      }
    });
  }

  // A sliver can end up with its dirty layout flag set while the notification
  // never reached its relayout boundary: when scroll offset correction is
  // requested from `layout()` below, `markNeedsLayout` runs inside the
  // parent's `invokeLayoutCallback`, which records the dirty flag on the
  // ancestor chain but suppresses propagation to the pipeline owner. If the
  // viewport then finishes the frame without laying this sliver out again
  // (e.g. when dragging the scrollbar fast), a plain `markNeedsLayout()` here
  // is a no-op debug-asserting that the boundary is dirty — which it is not —
  // and in release mode the sliver silently never lays out again. Marking the
  // ancestor chain root-first guarantees every relayout boundary above is
  // dirty and registered with the pipeline owner before the sliver itself is
  // marked. Clean unrelated subtrees still short-circuit in `layout()`, so
  // this does not force a full-tree relayout.
  //
  // A RenderViewport is sized by its parent and therefore a relayout
  // boundary, so the chain stops there. Marking the ancestors above it would
  // leave them dirty between frames, where hit testing asserts on them.
  void _markNeedsLayoutWithAncestors() {
    if (!attached) {
      return;
    }
    final chain = <RenderObject>[];
    for (RenderObject? node = this; node != null; node = node.parent) {
      chain.add(node);
      if (node is RenderViewport) {
        break;
      }
    }
    for (final node in chain.reversed) {
      node.markNeedsLayout();
    }
  }

  RenderBox? _liveChildForIndex(int index) {
    final first = firstChild;
    final last = lastChild;
    if (first == null ||
        last == null ||
        index < _indexOf(first) ||
        index > _indexOf(last)) {
      return null;
    }
    for (RenderBox? c = first; c != null; c = childAfter(c)) {
      if (_indexOf(c) == index) {
        return c;
      }
    }
    return null;
  }

  double _centerOrigin(RenderViewportBase viewport) {
    if (viewport is! RenderViewport) {
      return 0.0;
    }
    final extent = constraints.viewportMainAxisExtent;
    final origin = extent.isFinite ? extent * viewport.anchor : 0.0;
    return origin - (viewport.center?.centerOffsetAdjustment ?? 0.0);
  }

  /// Whether no sliver follows this one in its viewport, so the end of this
  /// list is the end of the scrollable content.
  bool _isTrailingSliver() {
    RenderObject child = this;
    for (var p = parent; p != null; p = p.parent) {
      if (p is RenderViewportBase) {
        return identical(p.lastChild, child);
      } else if (p is RenderSliverMainAxisGroup) {
        if (!identical(p.lastChild, child)) {
          return false;
        }
      } else if (p is! RenderObjectWithChildMixin) {
        return false;
      }
      child = p;
    }
    return false;
  }

  /// Scroll pixels that put an item laid out at [layoutOffset] at the
  /// target's alignment, clamped to the scroll range. Null when the sliver
  /// does not grow forward from the viewport's center.
  double? _pixelsForItemOffset(
    double layoutOffset,
    double alignment,
    double offset,
  ) {
    if (constraints.growthDirection != GrowthDirection.forward) {
      return null;
    }
    final viewport = getViewport();
    if (viewport == null) {
      return null;
    }
    final extent = constraints.viewportMainAxisExtent;
    final finiteExtent = extent.isFinite ? extent : 0.0;
    final origin = _centerOrigin(viewport) + constraints.precedingScrollExtent;
    var pixels = origin + layoutOffset - alignment * finiteExtent - offset;
    final position = viewport.offset;
    final minExtent =
        position is ScrollPosition && position.hasContentDimensions
        ? position.minScrollExtent
        : 0.0;
    // A shrink-wrapping viewport without a size limit shows all content.
    if (!extent.isFinite) {
      return minExtent;
    }
    if (_isTrailingSliver()) {
      final maxExtent = math.max(
        minExtent,
        origin + _totalExtent() + _trailingPaddingExtent() - finiteExtent,
      );
      pixels = math.min(pixels, maxExtent);
    }
    return math.max(pixels, minExtent);
  }

  bool _leadingSpaceChanged = false;

  /// Target scroll pixels for [target] laid out at [layoutOffset]. With
  /// [overscrollToTarget] this updates the blank space it needs; a
  /// changed leading space is reported through [_leadingSpaceChanged].
  double? _targetPixels(
    double layoutOffset,
    _PendingItemTarget target, {
    RenderBox? child,
  }) {
    _leadingSpaceChanged = false;
    if (child != null) {
      layoutOffset += _targetOffsetInItem(
        _indexOf(child),
        child,
        target.targetRectResolver,
      );
    }
    if (!_allowOverscrollToTarget) {
      return _pixelsForItemOffset(
        layoutOffset,
        target.alignment,
        target.offset,
      );
    }
    final solution = _solveOverscroll(
      layoutOffset,
      target.alignment,
      target.offset,
    );
    if (solution == null) {
      return null;
    }
    _trailingSpace = solution.trailing;
    if ((solution.leading - _leadingSpace).abs() > _kTargetTolerance) {
      _leadingSpace = solution.leading;
      _leadingSpaceChanged = true;
    }
    return solution.pixels;
  }

  // Ends this layout attempt; performLayout lays out again with the new
  // leading space.
  void _relayoutWithNewLeadingSpace() {
    geometry = SliverGeometry.zero;
    childManager.didFinishLayout();
  }

  /// Scroll pixels that put the leading edge of the item at [index] at
  /// [alignment] of the viewport plus [offset] pixels. Exact for laid out
  /// items, estimated otherwise. Null before the first layout.
  double? pixelsForIndex(
    int index,
    double alignment,
    double offset, {
    TargetRectResolver? targetRectResolver,
  }) {
    if (!attached || geometry == null || _extentManager.isLocked) {
      return null;
    }
    final count = _extentManager.numberOfItems;
    if (count == 0) {
      return null;
    }
    index = index.clamp(0, count - 1);
    final clamped = index;
    return _inContentSpace(() {
      final child = _liveChildForIndex(clamped);
      final layoutOffset = child != null
          ? childScrollOffset(child)! +
                _targetOffsetInItem(clamped, child, targetRectResolver)
          : _extentManager.offsetForIndex(clamped);
      if (_allowOverscrollToTarget) {
        return _solveOverscroll(layoutOffset, alignment, offset)?.pixels;
      }
      return _pixelsForItemOffset(layoutOffset, alignment, offset);
    });
  }

  double _targetOffsetInItem(
    int index,
    RenderBox child,
    TargetRectResolver? resolver,
  ) {
    if (resolver == null) return 0;
    Rect? resolved;
    if (_extentManager.isLocked) {
      invokeLayoutCallback<SliverConstraints>((_) {
        resolved = resolver(index, child);
      });
    } else {
      resolved = resolver(index, child);
    }
    final rect = resolved;
    if (rect == null) return 0;
    if (!rect.isFinite) {
      throw ArgumentError.value(rect, "targetRect", "Must be finite.");
    }
    return switch (constraints.axisDirection) {
      AxisDirection.down => rect.top,
      AxisDirection.up => child.size.height - rect.bottom,
      AxisDirection.right => rect.left,
      AxisDirection.left => child.size.width - rect.right,
    };
  }

  /// The first at least partially visible item and the distance from its
  /// leading edge to the viewport's leading edge.
  ListAnchor? get currentAnchor {
    if (!attached || geometry == null || _extentManager.isLocked) {
      return null;
    }
    // Negative while blank space before the first item is visible.
    final scrollOffset = super.constraints.scrollOffset - _leadingSpace;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final layoutOffset = _parentDataOf(c).layoutOffset;
      if (layoutOffset == null || !c.hasSize) {
        continue;
      }
      final extent = paintExtentOf(c);
      if (layoutOffset + extent > scrollOffset) {
        return ListAnchor(
          index: _indexOf(c),
          offsetInItem: scrollOffset - layoutOffset,
          itemExtent: extent,
        );
      }
    }
    return null;
  }

  /// Positions of the items that are at least partially visible, in index
  /// order, or null when the list is not laid out in a viewport, the viewport
  /// scrolled after the last layout or a jump is pending. Cost is proportional
  /// to the number of laid out children.
  List<ItemPosition>? computeItemPositions() {
    final viewport = getViewport();
    if (!attached || viewport == null || !viewport.hasSize) {
      return null;
    }
    // Before a pending jump lands, the laid out positions are the ones it
    // replaces; the layout that resolves it publishes.
    if (_pendingTarget != null || _viewportPixels != _layoutPixels) {
      return null;
    }
    final axisDirection = applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    );
    final vertical = axisDirectionToAxis(axisDirection) == Axis.vertical;
    final viewportExtent = vertical
        ? viewport.size.height
        : viewport.size.width;
    if (viewportExtent <= 0) {
      return const [];
    }
    final result = <ItemPosition>[];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (!c.hasSize) {
        continue;
      }
      final origin = c.localToGlobal(Offset.zero, ancestor: viewport);
      final double leading;
      final double extent;
      switch (axisDirection) {
        case AxisDirection.down:
          leading = origin.dy;
          extent = c.size.height;
        case AxisDirection.up:
          leading = viewportExtent - origin.dy - c.size.height;
          extent = c.size.height;
        case AxisDirection.right:
          leading = origin.dx;
          extent = c.size.width;
        case AxisDirection.left:
          leading = viewportExtent - origin.dx - c.size.width;
          extent = c.size.width;
      }
      final trailing = leading + extent;
      if (!leading.isFinite || trailing <= 0 || leading >= viewportExtent) {
        continue;
      }
      result.add(
        ItemPosition(
          index: _indexOf(c),
          itemLeadingEdge: leading / viewportExtent,
          itemTrailingEdge: trailing / viewportExtent,
        ),
      );
    }
    return result;
  }

  bool _itemPositionsUpdateScheduled = false;

  void _scheduleItemPositionsUpdate() {
    final sink = _extentManager.itemPositionsSink;
    if (sink == null || !sink.wantsItemPositions) {
      return;
    }
    if (_itemPositionsUpdateScheduled) {
      return;
    }
    _itemPositionsUpdateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _itemPositionsUpdateScheduled = false;
      final sink = _extentManager.itemPositionsSink;
      if (!attached || sink == null) {
        return;
      }
      // When stale, the pending layout schedules a fresh update.
      final positions = computeItemPositions();
      if (positions != null) {
        sink.updateItemPositions(positions);
      }
    });
  }

  /// Requests a layout so that item positions get published.
  void requestItemPositions() {
    if (!attached) {
      return;
    }
    if (_extentManager.isLocked) {
      _scheduleItemPositionsUpdate();
    } else {
      markNeedsLayout();
    }
  }

  double estimateExtentForItem(int? index) {
    final crossAxisExtent = constraints.crossAxisExtent;
    final extent = estimateExtent(index, crossAxisExtent);
    if (extent.isFinite && extent >= 0) return extent;
    assert(() {
      if (_debugReportedInvalidEstimate) return true;
      _debugReportedInvalidEstimate = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: ArgumentError.value(
            extent,
            "extent",
            "Estimated extent for index $index at cross axis extent "
                "$crossAxisExtent must be finite and nonnegative",
          ),
          library: "positioned_sliver_list",
        ),
      );
      return true;
    }());
    // Zero for the uniform query makes the list ask for each item instead.
    return index == null ? 0 : kDefaultEstimatedItemExtent;
  }

  bool _debugReportedInvalidEstimate = false;

  int? indexForScrollOffset(double pixels) {
    if (!attached ||
        geometry == null ||
        !pixels.isFinite ||
        _extentManager.isLocked ||
        _extentManager.numberOfItems == 0 ||
        constraints.growthDirection != GrowthDirection.forward) {
      return null;
    }
    final origin = getOffsetToReveal(0, 0, estimationOnly: true);
    final contentOffset = pixels - origin;
    return contentOffset < 0
        ? null
        : _extentManager.indexForOffset(contentOffset);
  }

  @override
  void performLayout() {
    final outer = super.constraints;
    if (_overscrollToTarget == OverscrollToTarget.none) {
      _leadingSpace = 0.0;
      _reservedLeadingSpace = 0.0;
      _trailingSpace = 0.0;
    }
    final shift = _leadingPaddingShift(outer);
    if (shift != 0.0) {
      geometry = SliverGeometry(scrollOffsetCorrection: shift);
      return;
    }
    if (_leadingSpace > 0 || _reservedLeadingSpace > 0) {
      final correction = _updateLeadingSpace(outer);
      if (correction != 0.0) {
        geometry = SliverGeometry(scrollOffsetCorrection: correction);
        return;
      }
    }
    // Layout may change the leading space without a scroll correction; the
    // content is then laid out again in the new coordinates.
    for (var attempt = 0; ; ++attempt) {
      final leading = _leadingSpace;
      final content = leading > 0
          ? _contentConstraintsFor(outer, leading)
          : null;
      _contentConstraintsOverride = content;
      try {
        _extentManager.performLayout(_performLayoutInner);
      } finally {
        _contentConstraintsOverride = null;
      }
      if (geometry!.scrollOffsetCorrection != null) {
        break;
      }
      if (_leadingSpace == leading || attempt >= 2) {
        _lastContentConstraints = content;
        if (content != null) {
          _applyLeadingSpaceToGeometry(outer, leading);
        }
        break;
      }
    }
    if (_leadingSpace == 0 && _trailingSpace == 0) {
      _pinnedIndex = null;
    }
    final pixels = _viewportPixels;
    _lastOuterLayout =
        pixels == null || geometry!.scrollOffsetCorrection != null
        ? null
        : (
            pixels: pixels,
            padding: _leadingPadding,
            scrollOffset: outer.scrollOffset,
          );
    _scheduleItemPositionsUpdate();
    if (geometry!.scrollOffsetCorrection == null) {
      _extentManager.completeEstimateUpdates();
    }
  }

  /// Scroll correction that keeps the visible content in place when the
  /// leading padding around this sliver changed while the viewport is
  /// scrolled into the list.
  double _leadingPaddingShift(SliverConstraints outer) {
    final last = _lastOuterLayout;
    if (last == null ||
        last.scrollOffset <= 0 ||
        hasPendingTarget ||
        outer.growthDirection != GrowthDirection.forward ||
        _viewportPixels != last.pixels) {
      return 0.0;
    }
    final shift = _leadingPadding - last.padding;
    return shift.abs() > precisionErrorTolerance ? shift : 0.0;
  }

  /// Applies a reserved leading space, or shrinks the leading space by the
  /// part the viewport scrolled past. Returns the scroll offset correction
  /// that keeps the content in place.
  double _updateLeadingSpace(SliverConstraints outer) {
    if (_overscrollToTarget ==
            OverscrollToTarget.matchScrollablePositionedList &&
        outer.viewportMainAxisExtent.isFinite) {
      // Content that grew may no longer fit: the space shrinks so that the
      // content's end stays at or below the trailing edge, as the original
      // clamps.
      final allowed = math.max(
        0.0,
        outer.viewportMainAxisExtent -
            outer.precedingScrollExtent -
            _totalExtent() -
            _trailingPaddingExtent(),
      );
      _leadingSpace = math.min(_leadingSpace, allowed);
      _reservedLeadingSpace = math.min(_reservedLeadingSpace, allowed);
    }
    if (_reservedLeadingSpace > _leadingSpace) {
      final grow = _reservedLeadingSpace - _leadingSpace;
      _leadingSpace = _reservedLeadingSpace;
      _reservedLeadingSpace = 0.0;
      return grow;
    }
    _reservedLeadingSpace = 0.0;
    if (holdOverscrollSpace || outer.scrollOffset <= 0) {
      return 0.0;
    }
    final shrink = math.min(outer.scrollOffset, _leadingSpace);
    _leadingSpace -= shrink;
    if (_leadingSpace < _kTargetTolerance) {
      _leadingSpace = 0.0;
    }
    return -shrink;
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    super.layout(constraints, parentUsesSize: parentUsesSize);
    _layoutPixels = _viewportPixels;
    // It is possible that after requesting scroll offset correction the
    // constraints during next layout call are same as before, which will skip
    // performLayout meaning the scrollCorrection gets stuck and viewport will
    // throw exception. To work around this force layout if there is scroll
    // offset correction requested.
    if (geometry?.scrollOffsetCorrection != null &&
        geometry?.scrollOffsetCorrection != 0) {
      parent?.invokeLayoutCallback((constraints) {
        markNeedsLayout();
      });
    }
  }

  bool get hasChildScrollOffsetEstimation =>
      _childScrollOffsetEstimation != null;

  String get _logIdentifier =>
      identityHashCode(this).toRadixString(16).padLeft(8, "0");

  double _trailingPaddingExtent() {
    var extent = 0.0;
    RenderObject child = this;
    for (var object = parent; object is RenderSliver; object = object.parent) {
      if (object is RenderSliverMainAxisGroup) {
        // Outer padding belongs to this list's end only if no sibling follows
        // its branch in the group's growth direction. Still include padding
        // inside that branch, and cross groups where the branch is last.
        final trailingChild =
            object.constraints.growthDirection == GrowthDirection.forward
            ? object.lastChild
            : object.firstChild;
        if (child != trailingChild) break;
      }
      if (object is RenderSliverEdgeInsetsPadding) {
        extent += object.afterPadding;
      }
      child = object;
    }
    return extent;
  }

  double _initialEndCorrection(double extent) {
    final viewportExtent = constraints.viewportMainAxisExtent;
    if (!viewportExtent.isFinite || viewportExtent <= 0) return 0;
    if (constraints.growthDirection == GrowthDirection.reverse) {
      // Preserve positioning at the center for slivers before the viewport's
      // center. This is distinct from a list with reverse: true.
      // The local target is zero here: padding clamping to zero already
      // satisfies it, so it cannot repeat the positive correction that caused
      // the forward-growth padding loop. This preserves the existing policy;
      // it does not try to consume the padding on the center side.
      return -constraints.scrollOffset;
    }

    final viewport = getViewport()!;

    // SliverPadding clamps the child's scrollOffset to zero while its leading
    // padding is visible. Compare viewport coordinates instead, so a small
    // overflow consumes that padding in one correction. precedingScrollExtent
    // already includes leading padding and preceding slivers, but not trailing
    // padding. Neither scroll extent is available on ScrollPosition yet.
    final centerOrigin = viewport is RenderViewport
        ? viewportExtent * viewport.anchor -
              viewport.center!.centerOffsetAdjustment
        : 0.0;
    final targetOffset = math.max(
      0.0,
      centerOrigin +
          constraints.precedingScrollExtent +
          extent +
          _trailingPaddingExtent() -
          viewportExtent,
    );
    return targetOffset - viewport.offset.pixels;
  }

  bool _applyInitialEndCorrection(double extent, LayoutPass pass) {
    final correction = _initialEndCorrection(extent);
    if (correction.abs() > precisionErrorTolerance) {
      // TODO: enforce a shared correction budget with a valid-layout fallback
      // that preserves pending initial positioning, rather than dropping it.
      ++pass.correctionCount;
      geometry = SliverGeometry(scrollOffsetCorrection: correction);
      childManager.didFinishLayout();
      return true;
    }
    return false;
  }

  void _invalidateItemLayout(RenderBox item) {
    // Fixed-size boundaries can otherwise lay out after the target is measured.
    invokeLayoutCallback<SliverConstraints>((_) {
      void invalidate(RenderObject object) {
        object.visitChildren(invalidate);
        object.markNeedsLayout();
      }

      invalidate(item);
    });
  }

  void _performLayoutInner() {
    if (_childScrollOffsetEstimation?.owner != _extentManager.revealOwner) {
      _childScrollOffsetEstimation = null;
    }
    if (_pendingTarget != null &&
        !identical(_pendingTarget!.owner, _extentManager.revealOwner)) {
      _completePendingTarget();
    }
    final anchoredHeader = _header;
    final headerItem = anchoredHeader == null
        ? null
        : _headerItem(anchoredHeader);
    if (anchoredHeader != null && headerItem == null) {
      _headerAnchorHandle?.cancel();
    }
    final hasHeaderAnchor = headerItem != null;
    final layoutPass = getLayoutPass(this)!;
    if (layoutPass.isNew) {
      layoutPass.isNew = false;
    }

    // State for this sliver (will be same instance for all layout attempts).
    final layoutState = layoutPass.getLayoutState(this);

    final SliverConstraints constraints = this.constraints;
    final BoxConstraints childConstraints = constraints.asBoxConstraints();
    final totalChildCount = childManager.childCount;

    if (_initialScrollPosition == InitialScrollPosition.end &&
        totalChildCount == 0) {
      _didResolveInitialScrollPosition = false;
    }

    layoutState.extentRevision ??= _extentManager.extentRevision;
    _extentManager.resize(totalChildCount);

    if (previousConstraints != null &&
        previousConstraints!.crossAxisExtent != constraints.crossAxisExtent) {
      _extentManager.markAllDirty();
      layoutState.crossAxisResizing = true;
    }
    final crossAxisResizing = layoutState.crossAxisResizing;

    // Layout can be called multiple times, make sure we don't overwrite
    // previousConstraints during same layout pass.
    if (!layoutState.didSetPreviousConstraint) {
      layoutState.didSetPreviousConstraint = true;
      previousConstraints = constraints;
    }

    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    if (_extentManager.hasPendingEstimateUpdates) {
      final child = firstChild;
      final oldOffset = child == null
          ? null
          : _parentDataOf(child).layoutOffset;
      _extentManager.applyPendingEstimateUpdates();
      for (var c = child; c != null; c = childAfter(c)) {
        if (c.hasSize) _extentManager.setExtent(_indexOf(c), paintExtentOf(c));
      }
      if (child != null && oldOffset != null) {
        final delta =
            _extentManager.offsetForIndex(_indexOf(child)) - oldOffset;
        _shiftLayoutOffsets(child, delta);
        if (constraints.scrollOffset > 0 &&
            _pendingTarget == null &&
            _header == null &&
            delta.abs() > precisionErrorTolerance) {
          geometry = SliverGeometry(scrollOffsetCorrection: delta);
          childManager.didFinishLayout();
          return;
        }
      }
    }

    // This is also the last extent that this sliver list reported.
    final initialExtent = _totalExtent();

    if (!_didResolveInitialScrollPosition &&
        _initialScrollPosition == InitialScrollPosition.end &&
        totalChildCount > 0 &&
        _applyInitialEndCorrection(initialExtent, layoutPass)) {
      return;
    }

    if (_pendingTarget != null &&
        (totalChildCount == 0 ||
            constraints.growthDirection != GrowthDirection.forward)) {
      if (totalChildCount > 0) {
        _log.warning(
          "jumpToIndex is not supported for a sliver before the center "
          "of its viewport; the jump was dropped.",
        );
      }
      _completePendingTarget();
    }
    final pendingTarget = _pendingTarget;
    final pendingIndex = pendingTarget?.index.clamp(0, totalChildCount - 1);
    if (headerItem != null) _invalidateItemLayout(headerItem);
    if (pendingTarget?.targetRectResolver != null) {
      final targetChild = _liveChildForIndex(pendingIndex!);
      if (targetChild != null) {
        _invalidateItemLayout(targetChild);
      }
    }
    // Move to the target's estimated position first, so that only the items
    // around it are built.
    if (pendingTarget != null &&
        _liveChildForIndex(pendingIndex!) == null &&
        layoutPass.correctionCount < layoutPass.maxCorrectionCount) {
      final pixels = _targetPixels(
        _extentManager.offsetForIndex(pendingIndex),
        pendingTarget,
      );
      final correction = pixels == null
          ? 0.0
          : pixels - getViewport()!.offset.pixels;
      if (correction.abs() > _kTargetTolerance) {
        ++layoutPass.correctionCount;
        geometry = SliverGeometry(scrollOffsetCorrection: correction);
        childManager.didFinishLayout();
        return;
      }
      if (_leadingSpaceChanged) {
        _relayoutWithNewLeadingSpace();
        return;
      }
    }

    // Viewport is not at the beginning.
    final viewportIsScrolled =
        (constraints.viewportMainAxisExtent -
                constraints.remainingPaintExtent) <
            constraints.precedingScrollExtent ||
        constraints.scrollOffset > 0;

    // This sliver ends in visible area of viewport and viewport is scrolled.
    // When this is true the SuperSliverList will try to keep the bottom of the
    // list at the same position when updating the extents by adjusting the scroll
    // offset.
    final anchoredAtEnd =
        !hasHeaderAnchor &&
        pendingTarget == null &&
        _trailingSpace == 0 &&
        _pinnedIndex == null &&
        viewportIsScrolled &&
        (constraints.scrollOffset + constraints.remainingPaintExtent) +
                precisionErrorTolerance >=
            initialExtent &&
        (layoutPass.childScrollOffsetEstimation == false ||
            layoutPass.sliverIsBeforeSliverWithOffsetEstimation(this));

    if (_log.isLoggable(Level.FINE)) {
      _log.fine(
        "Laying out $_logIdentifier "
        "("
        "anchored at end: $anchoredAtEnd, "
        "initial extent: ${initialExtent.format()}, "
        "scroll offset: ${constraints.scrollOffset.format()}, "
        "overlap: ${constraints.overlap}, "
        "remaining paint extent: ${constraints.remainingPaintExtent.format()}, "
        "cache: ${constraints.cacheOrigin.format()} - "
        "${constraints.remainingCacheExtent.format()}, "
        "preceding: ${constraints.precedingScrollExtent.format()}"
        ")",
      );
    }

    // Scroll offset including cache area.
    var startOffset = constraints.scrollOffset + constraints.cacheOrigin;
    var remainingExtent = constraints.remainingCacheExtent;

    if (pendingIndex != null && _liveChildForIndex(pendingIndex) == null) {
      var count = 0;
      for (var child = firstChild; child != null; child = childAfter(child)) {
        count++;
      }
      collectGarbage(count, 0);
      layoutState.didRemoveChildren |= count > 0;
    }

    // First go through all children, remove those that are no longer
    // in cache area and layout those that are in the cache area.
    int leadingGarbage = 0;
    int trailingGarbage = 0;
    RenderBox? lastChildWithScrollOffset;

    // The item at the viewport's leading edge keeps its on-screen position
    // when items before it change extent; on width change the scrolled-past
    // fraction of it is kept as well.
    final keepsTrailingEdge =
        anchoredAtEnd &&
        (crossAxisResizing ||
            layoutState.didAddInitialChild ||
            _extentManager.stickTarget != null);
    // While blank space exists, the item a jump placed stays where it is.
    final pinned = _pinnedIndex != null && pendingTarget == null
        ? _liveChildForIndex(_pinnedIndex!)
        : null;
    final anchor =
        !hasHeaderAnchor &&
            pendingTarget == null &&
            _childScrollOffsetEstimation == null &&
            !layoutPass.childScrollOffsetEstimation &&
            !keepsTrailingEdge &&
            (pinned != null || constraints.scrollOffset > 0)
        ? (pinned ?? _leadingEdgeChild())
        : null;
    final anchorLayoutOffset = anchor != null
        ? _parentDataOf(anchor).layoutOffset!
        : 0.0;
    final anchorExtent = anchor != null ? paintExtentOf(anchor) : 0.0;
    // Captured before garbage collection, which may drop the anchor when the
    // items before it grew a lot.
    double? anchorNewLayoutOffset;
    double? anchorNewExtent;

    if (headerItem != null && _parentDataOf(headerItem).layoutOffset == null) {
      // Keyed moves clear offsets. Correct from the retained header before
      // filling gaps, which may contain an arbitrarily large inserted group.
      var prefixCount = 0;
      for (
        var child = firstChild;
        child != null && !identical(child, headerItem);
        child = childAfter(child)
      ) {
        ++prefixCount;
      }
      collectGarbage(prefixCount, 0);
      layoutState.didRemoveChildren |= prefixCount > 0;
      _parentDataOf(headerItem).layoutOffset = _extentManager.offsetForIndex(
        _indexOf(headerItem),
      );
      layoutChild(headerItem, childConstraints);
      final correction = _headerCorrection() ?? 0;
      if (correction.abs() > precisionErrorTolerance) {
        ++layoutPass.correctionCount;
        geometry = SliverGeometry(scrollOffsetCorrection: correction);
        childManager.didFinishLayout();
        return;
      }
    }

    RenderBox? previousChild;
    int index = firstChild != null ? _indexOf(firstChild!) : 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      // all items after first trailing garbage are automatically garbage
      if (trailingGarbage > 0 &&
          (headerItem == null || _indexOf(child) > _indexOf(headerItem))) {
        ++trailingGarbage;
        // Keep measuring up to the anchor to learn how far it moved.
        if (anchor != null &&
            anchorNewLayoutOffset == null &&
            _indexOf(child) == index) {
          final offset = layoutChild(
            child,
            childConstraints,
            lastChildWithScrollOffset: lastChildWithScrollOffset,
          );
          if (offset != null) {
            lastChildWithScrollOffset = child;
            if (identical(child, anchor)) {
              anchorNewLayoutOffset = offset;
              anchorNewExtent = paintExtentOf(child);
            }
          }
        }
      } else {
        if (_indexOf(child) != index) {
          final newChild = insertAndLayoutChild(
            childConstraints,
            after: previousChild,
          );
          // This should not normally happen. If there is GAP between children we should be
          // able to fill it, otherwise it would be an inconsistency in childManager.
          assert(newChild != null, "Unexpected trailing child.");
          if (newChild == null) {
            ++trailingGarbage;
            continue;
          } else {
            child = newChild;
          }
        }
        final offset = layoutChild(
          child,
          childConstraints,
          lastChildWithScrollOffset: lastChildWithScrollOffset,
        );
        if (identical(child, anchor) && offset != null) {
          anchorNewLayoutOffset = offset;
          anchorNewExtent = paintExtentOf(child);
        }

        if (offset == null) {
          // Could not determine scroll offset, treat as leading garbage.
          ++leadingGarbage;
        } else {
          lastChildWithScrollOffset = child;
          final endOffset = offset + paintExtentOf(child);
          if (offset > startOffset + remainingExtent &&
              (headerItem == null || _indexOf(child) > _indexOf(headerItem))) {
            ++trailingGarbage;
          } else if (endOffset < startOffset) {
            ++leadingGarbage;
          }
        }
      }
      previousChild = child;
      ++index;
    }

    if (leadingGarbage > 0 || trailingGarbage > 0) {
      layoutState.didRemoveChildren |= true;

      _log.finer(
        () =>
            "Garbage collection: $leadingGarbage leading, $trailingGarbage trailing",
      );
    }
    if (headerItem != null) {
      // Retain only the contiguous live range needed to keep the anchor alive
      // until the correction. An instant collapse can move it out of cache.
      var count = 0;
      var headerOrdinal = -1;
      for (var c = firstChild; c != null; c = childAfter(c)) {
        if (identical(c, headerItem)) headerOrdinal = count;
        count++;
      }
      if (headerOrdinal >= 0) {
        leadingGarbage = math.min(leadingGarbage, headerOrdinal);
        trailingGarbage = math.min(trailingGarbage, count - headerOrdinal - 1);
      }
    }
    collectGarbage(leadingGarbage, trailingGarbage);

    var didDelayPopulatingCacheArea = false;

    if (firstChild == null) {
      layoutState.didAddInitialChild |= true;
      final int firstChildInCacheAreaIndex =
          indexForOffset(startOffset) ?? totalChildCount;
      if (_childScrollOffsetEstimation == null &&
          pendingTarget == null &&
          (firstChildInCacheAreaIndex >= totalChildCount ||
              constraints.remainingCacheExtent == 0)) {
        // The user either did not reach this sliver or scrolled past it.
        final extentBefore = _totalExtent();
        // The stopwatch exists purely for the FINER log below; avoid creating
        // and starting it on every layout of every invisible sliver.
        final Stopwatch? stopwatch =
            (!SuperSliverListPerfFlags.guardInvisibleLayoutLogging ||
                _log.isLoggable(Level.FINER))
            ? (Stopwatch()..start())
            : null;
        if (_extentManager.hasDirtyItems &&
            _shouldPrecalculateExtents(layoutPass)) {
          if (_shouldSkipExtentPrecalculationForInvisibleList(layoutPass)) {
            _log.finer(
              () =>
                  "Want to precalculate extents but there is visibile that has higher priority.",
            );
            _markNeedsLayoutDelayed(layoutPass);
          } else if (layoutPass.correctionCount > 3) {
            _log.finer(
              () =>
                  "Want to precalculate extents but correction count is too high "
                  "high (${layoutPass.correctionCount}). Scheduling layout pass.",
            );
            _markNeedsLayoutDelayed(layoutPass);
          } else {
            _calculatePendingLayout(
              layoutPass: layoutPass,
              allowScrollOffsetCorrection: true,
              precalculateExtents: true,
            );
          }
        }
        _layoutKeptAliveChildren();
        final extentDelta = _totalExtent() - extentBefore;
        if (stopwatch != null &&
            (stopwatch.elapsed > const Duration(microseconds: 50) ||
                extentDelta.abs() > precisionErrorTolerance)) {
          _log.finer(
            () =>
                "Spent ${stopwatch.elapsed} calculating layout info (extent delta: ${extentDelta.format()}).",
          );
        }
        if (extentDelta.abs() > precisionErrorTolerance &&
            constraints.remainingPaintExtent > 0) {
          ++layoutPass.correctionCount;
          _log.fine(
            () =>
                "Scroll offset correction: ${extentDelta.format()} "
                "(reason: async layout of scrolled-away slivers, correction count ${layoutPass.correctionCount})",
          );
          geometry = SliverGeometry(scrollOffsetCorrection: extentDelta);
          childManager.didFinishLayout();
          return;
        }
        if (constraints.remainingCacheExtent == 0) {
          _log.finer(
            () =>
                "Did not reach this sliver, reporting extent ${_totalExtent().format()} "
                "(has dirty items: ${_extentManager.hasDirtyItems})",
          );
        } else {
          _log.finer(
            () =>
                "Scrolled past this sliver, reporting extent ${_totalExtent().format()} "
                "(has dirty items: ${_extentManager.hasDirtyItems})",
          );
        }
        // This would be normally done by addInitialChild, but layout terminates
        // before that.
        if (totalChildCount == 0) {
          childManager.setDidUnderflow(true);
        }
        geometry = SliverGeometry(
          paintExtent: 0,
          maxPaintExtent: _totalExtent() + _trailingSpace,
          scrollExtent: _totalExtent() + _trailingSpace,
        );
        childManager.didFinishLayout();
        return;
      }

      // Put first child at the scroll offset, not the beginning of cache area
      final firstChildScrollOffset = constraints.scrollOffset;
      final firstChildIndex =
          pendingIndex ??
          (anchoredAtEnd
              ? totalChildCount - 1
              : indexForOffset(firstChildScrollOffset) ?? totalChildCount - 1);

      if (_log.isLoggable(Level.FINE)) {
        _log.fine("Adding initial child with index $firstChildIndex");
      }

      if (!addInitialChild(
        index: firstChildIndex,
        layoutOffset: offsetForIndex(firstChildIndex),
      )) {
        return _zeroGeometry();
      }

      final reducedStartOffset = constraints.scrollOffset;
      final reducedRemainingExtent = constraints.remainingPaintExtent;

      // If children were removed during this pass and new children are added
      // from empty assume fast scrolling, in which case only the visible area
      // is populated (ignoring cache area) and then in next layout pass the
      // cache area is populated.
      if (delayPopulatingCacheArea &&
          layoutState.didRemoveChildren &&
          (startOffset != reducedStartOffset ||
              remainingExtent != reducedRemainingExtent)) {
        startOffset = reducedStartOffset;
        remainingExtent = reducedRemainingExtent;
        didDelayPopulatingCacheArea = true;
        _markNeedsLayoutDelayed(layoutPass);
      }
    }

    firstChild!.layout(childConstraints, parentUsesSize: true);
    _extentManager.setExtent(_indexOf(firstChild!), paintExtentOf(firstChild!));

    // At this point there is at least one child.
    // First we need to create children before current child all the way to the
    // beginning of cached area

    double scrollCorrection = 0; // Accumulated scroll offset correction.

    if (anchorNewLayoutOffset != null && anchorNewExtent != null) {
      final scrolledPast = constraints.scrollOffset - anchorLayoutOffset;
      final newScrolledPast =
          crossAxisResizing && anchorExtent > 0 && pinned == null
          ? scrolledPast / anchorExtent * anchorNewExtent
          : scrolledPast;
      scrollCorrection =
          anchorNewLayoutOffset + newScrolledPast - constraints.scrollOffset;
    }

    // Start offset with applied scroll correction.
    var correctedStartOffset = startOffset + scrollCorrection;

    // Adding preceding children.
    if (SuperSliverListPerfFlags.batchLeadingChildShift) {
      // Deferred-shift variant: instead of shifting every subsequent child
      // once per inserted leading child (O(k*n)), children are positioned
      // top-down from the current first child using their *actual* extents
      // and the accumulated correction is applied to all children in a
      // single O(n) pass afterwards. Stored offsets lag the "real" offsets
      // by [pendingShift] while the loop runs, which is compensated for in
      // the loop condition.
      double pendingShift = 0;
      while ((_indexOf(firstChild!) > 0 &&
              childScrollOffset(firstChild!)! + pendingShift >
                  correctedStartOffset) ||
          (_childScrollOffsetEstimation != null &&
              _indexOf(firstChild!) > _childScrollOffsetEstimation!.index) ||
          (pendingIndex != null && _indexOf(firstChild!) > pendingIndex)) {
        final prevOffset = childScrollOffset(firstChild!)!;
        final previousExtent = _extentManager.getExtent(
          _indexOf(firstChild!) - 1,
        );
        final box = insertAndLayoutLeadingChild(
          childConstraints,
          parentUsesSize: true,
        );
        if (box == null) {
          break;
        }
        final extent = paintExtentOf(box);
        final data = box.parentData! as SliverMultiBoxAdaptorParentData;
        data.layoutOffset = prevOffset - extent;
        final correction = extent - previousExtent;
        _log.finest(
          () =>
              "Adding preceding child with index ${_indexOf(box)} "
              "extent: $extent "
              "(${correction.format()} correction)",
        );
        pendingShift += correction;
        // Do not correct when anchored at end and started from nothing.
        // And only correct when there are no other slivers visible.
        if ((!anchoredAtEnd || !layoutState.didAddInitialChild) &&
            constraints.remainingPaintExtent ==
                constraints.viewportMainAxisExtent) {
          scrollCorrection += correction;
        }

        // If start offset is 0, we must end up at initial item, so do not correct the
        // start offset.
        // If start offset > 0 we care about filling up the cache area, so correct the
        // offset depending on the extent of the child. TODO(knopp): It might be enough
        // to just ensure that we have a single completely hidden child in the cache
        // area. See https://github.com/flutter/flutter/issues/128601
        if (startOffset > 0) {
          correctedStartOffset += correction;
        }
      }
      if (pendingShift != 0) {
        _shiftLayoutOffsets(firstChild, pendingShift);
      }
    } else {
      while ((_indexOf(firstChild!) > 0 &&
              childScrollOffset(firstChild!)! > correctedStartOffset) ||
          (_childScrollOffsetEstimation != null &&
              _indexOf(firstChild!) > _childScrollOffsetEstimation!.index) ||
          (pendingIndex != null && _indexOf(firstChild!) > pendingIndex)) {
        final prevOffset = childScrollOffset(firstChild!)!;
        final previousExtent = _extentManager.getExtent(
          _indexOf(firstChild!) - 1,
        );
        final box = insertAndLayoutLeadingChild(
          childConstraints,
          parentUsesSize: true,
        );
        if (box == null) {
          break;
        }
        final data = box.parentData! as SliverMultiBoxAdaptorParentData;
        data.layoutOffset = prevOffset - previousExtent;
        final correction = paintExtentOf(box) - previousExtent;
        _log.finest(
          () =>
              "Adding preceding child with index ${_indexOf(box)} "
              "extent: ${paintExtentOf(box)} "
              "(${correction.format()} correction)",
        );
        _shiftLayoutOffsets(childAfter(box), correction);
        // Do not correct when anchored at end and started from nothing.
        // And only correct when there are no other slivers visible.
        if ((!anchoredAtEnd || !layoutState.didAddInitialChild) &&
            constraints.remainingPaintExtent ==
                constraints.viewportMainAxisExtent) {
          scrollCorrection += correction;
        }

        // If start offset is 0, we must end up at initial item, so do not correct the
        // start offset.
        // If start offset > 0 we care about filling up the cache area, so correct the
        // offset depending on the extent of the child. TODO(knopp): It might be enough
        // to just ensure that we have a single completely hidden child in the cache
        // area. See https://github.com/flutter/flutter/issues/128601
        if (startOffset > 0) {
          correctedStartOffset += correction;
        }
      }
    }

    // Additional correction: first child is not at the very beginning
    if (_indexOf(firstChild!) == 0 && childScrollOffset(firstChild!)! != 0) {
      final correction = -childScrollOffset(firstChild!)!;
      _shiftLayoutOffsets(firstChild, correction);
      scrollCorrection += correction;
    }

    bool addTrailingChild() {
      final lastChildIndex = _indexOf(lastChild!);
      if (lastChildIndex >= totalChildCount - 1) {
        return false;
      }

      if (SuperSliverListPerfFlags.hoistTrailingChildValues) {
        // Compute the last child's trailing edge once; the baseline below
        // computes childScrollOffset + paintExtentOf twice per call.
        final lastChildEnd =
            childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);
        if (lastChildEnd >= startOffset + remainingExtent) {
          // If there is child scroll offset estimation active produce as many children
          // as necessary. These will be removed after correcting scroll offset during
          // garbage collection.
          if (pendingIndex != null) {
            if (pendingIndex <= lastChildIndex) {
              return false;
            }
          } else {
            if (_childScrollOffsetEstimation != null &&
                _childScrollOffsetEstimation!.index < lastChildIndex) {
              return false;
            }
            if (layoutPass.childScrollOffsetEstimation == false) {
              return false;
            }
            if (_childScrollOffsetEstimation == null &&
                !layoutPass.sliverIsBeforeSliverWithOffsetEstimation(this)) {
              return false;
            }
          }
        }

        final box = insertAndLayoutChild(
          childConstraints,
          after: lastChild,
          parentUsesSize: true,
        );
        if (box == null) {
          return false;
        }
        _extentManager.setExtent(_indexOf(box), paintExtentOf(box));
        final data = box.parentData! as SliverMultiBoxAdaptorParentData;
        data.layoutOffset = lastChildEnd;
        return true;
      }

      if (childScrollOffset(lastChild!)! + paintExtentOf(lastChild!) >=
          startOffset + remainingExtent) {
        // If there is child scroll offset estimation active produce as many children
        // as necessary. These will be removed after correcting scroll offset during
        // garbage collection.
        if (pendingIndex != null) {
          if (pendingIndex <= lastChildIndex) {
            return false;
          }
        } else if (_childScrollOffsetEstimation != null &&
            _childScrollOffsetEstimation!.index < lastChildIndex) {
          return false;
        } else if (layoutPass.childScrollOffsetEstimation == false) {
          return false;
        } else if (_childScrollOffsetEstimation == null &&
            !layoutPass.sliverIsBeforeSliverWithOffsetEstimation(this)) {
          return false;
        }
      }

      final newLayoutOffset =
          childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);

      final box = insertAndLayoutChild(
        childConstraints,
        after: lastChild,
        parentUsesSize: true,
      );
      if (box == null) {
        return false;
      }
      _extentManager.setExtent(_indexOf(box), paintExtentOf(box));
      final data = box.parentData! as SliverMultiBoxAdaptorParentData;
      data.layoutOffset = newLayoutOffset;
      return true;
    }

    // Add remaining children to fill the cache area.
    while (addTrailingChild()) {}

    if (pendingTarget != null) {
      final child = _liveChildForIndex(pendingIndex!);
      if (child != null) {
        final pixels = _targetPixels(
          childScrollOffset(child)!,
          pendingTarget,
          child: child,
        );
        final correction = pixels == null
            ? 0.0
            : pixels - getViewport()!.offset.pixels;
        if (correction.abs() > _kTargetTolerance) {
          if (layoutPass.correctionCount < layoutPass.maxCorrectionCount) {
            ++layoutPass.correctionCount;
            geometry = SliverGeometry(scrollOffsetCorrection: correction);
            childManager.didFinishLayout();
            return;
          }
          _markNeedsLayoutDelayed(layoutPass);
        } else if (_leadingSpaceChanged) {
          _relayoutWithNewLeadingSpace();
          return;
        } else {
          _pinnedIndex =
              _overscrollToTarget == OverscrollToTarget.always &&
                  (_leadingSpace > 0 || _trailingSpace > 0)
              ? pendingIndex
              : null;
          _completePendingTarget();
        }
      } else {
        _markNeedsLayoutDelayed(layoutPass);
      }
      // The target already accounts for extents measured in this pass.
      scrollCorrection = 0;
    }

    // Assume this is viewport trying to reveal particular child that was out of
    // cache area originally. We provided estimated offset for the child, but
    // the actual one might be different. If that's the case, correct the
    // position now.
    final estimation = _childScrollOffsetEstimation;
    if (estimation != null) {
      for (var c = firstChild; c != null; c = childAfter(c)) {
        if (estimation.index == _indexOf(c)) {
          _childScrollOffsetEstimation = null;
          final childScrollOffset = this.childScrollOffset(c)!;

          var correction = childScrollOffset - estimation.offset;
          correction +=
              constraints.precedingScrollExtent -
              estimation.precedingScrollExtent;

          final currentScrollPosition = getViewport()?.offset.pixels ?? 0.0;
          correction +=
              layoutPass.initialScrollPosition - currentScrollPosition;

          if (!estimation.revealingRect) {
            final childAlignmentWithinViewport = estimation.alignment;

            // Depending on child alignment within viewport the scroll offset correction
            // needs to account for extent difference. When child is aligned at the start
            // of viewport, the correction is 0. When child is aligned at the end of viewport,
            // the correction is equal to extent difference.
            final extentDifference = paintExtentOf(c) - estimation.extent;
            correction += extentDifference * childAlignmentWithinViewport;

            // Obstruction extent on this sliver might have been outdated during the estimation
            // so account of the difference.
            final obstructionExtentDifference =
                c.getParentChildObstructionExtent() -
                estimation.childObstructionExtent;
            correction -=
                obstructionExtentDifference.leading *
                (1.0 - childAlignmentWithinViewport);
            correction +=
                obstructionExtentDifference.trailing *
                childAlignmentWithinViewport;
          }

          final position = getViewport()!.offset as ScrollPosition;

          // Max scroll extent with applied corrections for this layout pass.
          final maxScrollExtent =
              position.maxScrollExtent -
              initialExtent +
              _totalExtent() +
              constraints.precedingScrollExtent -
              estimation.precedingScrollExtent;

          // Try to prevent overscroll.
          final target = position.pixels + correction;
          if (target < 0) {
            correction -= target;
          } else if (target > maxScrollExtent) {
            correction -= target - maxScrollExtent;
          }

          if (correction.abs() > precisionErrorTolerance) {
            _log.fine(
              () =>
                  "Scroll offset correction: ${correction.format()} "
                  "(reason: jumping to estimated offset, index ${estimation.index})",
            );

            geometry = SliverGeometry(scrollOffsetCorrection: correction);
            childManager.didFinishLayout();
            return;
          } else {
            // When jumping to item ignore cache area scroll correction.
            scrollCorrection = 0;
          }
        }
      }
    }

    // When extent changes during resizing while anchored at the end, keep the
    // trailing edge in place. Also when anchored at the end while adding initial
    // child. Note that it may take multiple layout tries to reach the final layout
    // so didAddInitialChild must be tracked through entire layout pass.
    if (anchoredAtEnd &&
        (crossAxisResizing ||
            layoutState.didAddInitialChild ||
            _extentManager.stickTarget != null) &&
        _totalExtent() != initialExtent) {
      final target = _extentManager.stickTarget;
      final delta = _totalExtent() - initialExtent;

      if (target == null || target.isBottom) {
        // Bottom target (or cross-axis / initial-child cases): pin the
        // trailing edge by correcting for the full extent change.
        scrollCorrection += delta;

        // InitialScrollPosition.end first jumps using estimated extents. If
        // measuring the children reveals that the entire list fits in the
        // viewport, applying the full extent delta would move the viewport
        // past its leading boundary. For example: an estimated 800px list in
        // a 600px viewport starts at 200px; if its real extent is 160px, the
        // raw -640px delta would leave pixels at -440px. Bouncing physics then
        // visibly springs the content to zero after the first frame.
        //
        // The leading boundary is stable during this initial resolution, so
        // cap the correction there. The final initial-position block below
        // will still resolve against the now-accurate total extent.
        if (!_didResolveInitialScrollPosition &&
            _initialScrollPosition == InitialScrollPosition.end) {
          final position = getViewport()!.offset;
          scrollCorrection = math.max(scrollCorrection, -position.pixels);
        }
      } else {
        // Item target: pin trailing edge only while the target's desired
        // scroll offset would be clamped to maxScrollExtent (i.e. the item
        // can't yet be placed at its alignment position because there isn't
        // enough content above it).  Once the target is reachable, correct
        // just enough to reach it, then stop — the item's top stays put
        // naturally as it grows.
        final desiredSliverOffset = _desiredSliverOffsetForTarget(target);
        final currentSliverOffset = constraints.scrollOffset + scrollCorrection;
        final newMaxSliverOffset =
            _totalExtent() - constraints.remainingPaintExtent;

        if (desiredSliverOffset >=
            newMaxSliverOffset - precisionErrorTolerance) {
          // Still clamped: full trailing-edge correction.
          scrollCorrection += delta;
        } else {
          // Target is reachable: correct only to the desired position.
          final needed = desiredSliverOffset - currentSliverOffset;
          if (needed > precisionErrorTolerance) {
            scrollCorrection += needed;
          }
        }
      }

      if (_log.isLoggable(Level.FINE)) {
        _log.fine(
          "Adjusting correction for extent change by ${_totalExtent() - initialExtent}",
        );
      }
    }

    // Fallback: ensure content doesn't overflow past the visible area when
    // anchoredAtEnd is false.  This covers the transition from content fitting
    // inside the viewport to overflowing it — viewportIsScrolled is false
    // (scrollOffset == 0) so anchoredAtEnd doesn't fire, but we still need a
    // correction to keep the bottom visible.
    //
    // For item targets the correction is capped at the desired item position
    // so we don't overshoot past it to the trailing edge.
    if (!hasHeaderAnchor && _extentManager.stickTarget != null) {
      final target = _extentManager.stickTarget!;
      final currentOffset = constraints.scrollOffset + scrollCorrection;
      final visibleEnd = currentOffset + constraints.remainingPaintExtent;
      final overshoot = _totalExtent() - visibleEnd;

      if (overshoot > precisionErrorTolerance) {
        if (target.isBottom) {
          scrollCorrection += overshoot;
        } else {
          // Item target: only correct the actual overflow, capped so we
          // never scroll past the desired item position.
          final desiredSliverOffset = _desiredSliverOffsetForTarget(target);
          final maxCorrection = math.max(
            0.0,
            desiredSliverOffset - currentOffset,
          );
          final cappedCorrection = math.min(overshoot, maxCorrection);
          if (cappedCorrection > precisionErrorTolerance) {
            scrollCorrection += cappedCorrection;
          }
        }
      }
    }

    // All child offsets and extents above are now current. Replace the default
    // position policy, not its extent bookkeeping, with the header constraint.
    scrollCorrection = _headerCorrection() ?? scrollCorrection;
    if (pinned != null && _allowOverscrollToTarget) {
      // Keeping the pinned item in place would scroll before the content:
      // grow the leading space instead.
      final outerScroll = super.constraints.scrollOffset + scrollCorrection;
      if (outerScroll < -_kTargetTolerance) {
        _leadingSpace -= outerScroll;
        scrollCorrection -= outerScroll;
        if (scrollCorrection.abs() <= precisionErrorTolerance) {
          _relayoutWithNewLeadingSpace();
          return;
        }
      }
    }
    if (scrollCorrection.abs() > precisionErrorTolerance) {
      if (layoutPass.correctionCount >= layoutPass.maxCorrectionCount) {
        _log.fine(
          () =>
              "Dropping accumulated scroll correction "
              "${scrollCorrection.format()} — reached correction limit "
              "(${layoutPass.correctionCount}). Will settle next frame.",
        );
        _markNeedsLayoutDelayed(layoutPass);
      } else {
        _log.fine(
          () =>
              "Scroll offset correction: ${scrollCorrection.format()} "
              "(reason: accumulated while laying out cache area)",
        );
        ++layoutPass.correctionCount;
        geometry = SliverGeometry(scrollOffsetCorrection: scrollCorrection);
        childManager.didFinishLayout();
        return;
      }
    }

    var correction = _calculatePendingLayout(
      layoutPass: layoutPass,
      allowScrollOffsetCorrection: layoutPass.correctionCount < 3,
      precalculateExtents:
          !hasHeaderAnchor && _shouldPrecalculateExtents(layoutPass),
    );
    final keptAliveCorrection = _layoutKeptAliveChildren();
    if (keptAliveCorrection != 0) {
      _log.finer(
        () =>
            "Correction due to kept alive children: ${keptAliveCorrection.format()}",
      );
      correction += keptAliveCorrection;
    }

    if (correction.abs() > precisionErrorTolerance) {
      if (layoutPass.correctionCount >= layoutPass.maxCorrectionCount) {
        _log.fine(
          () =>
              "Dropping invisible/kept-alive correction "
              "${correction.format()} — reached correction limit "
              "(${layoutPass.correctionCount}). Will settle next frame.",
        );
        _markNeedsLayoutDelayed(layoutPass);
      } else {
        ++layoutPass.correctionCount;
        _shiftLayoutOffsets(firstChild, correction);
        _log.fine(
          () =>
              "Scroll offset correction: ${correction.format()} "
              "(reason: layout correction of invisible items or kept alive children)",
        );
        geometry = SliverGeometry(scrollOffsetCorrection: correction);
        childManager.didFinishLayout();
        return;
      }
    }

    if (_overscrollToTarget ==
            OverscrollToTarget.matchScrollablePositionedList &&
        _leadingSpace > 0) {
      // Measured content that no longer fits pulls the content back up.
      final outer = super.constraints;
      final allowed = math.max(
        0.0,
        outer.viewportMainAxisExtent -
            outer.precedingScrollExtent -
            _totalExtent() -
            _trailingPaddingExtent(),
      );
      if (_leadingSpace > allowed + _kTargetTolerance) {
        _leadingSpace = allowed;
        _relayoutWithNewLeadingSpace();
        return;
      }
    }
    if (_trailingSpace > 0 && !holdOverscrollSpace) {
      final needed = _trailingSpaceNeeded();
      final contentChanged =
          layoutState.extentRevision != _extentManager.extentRevision;
      // Scrolling only ever shrinks it; content changes recompute it so the
      // pinned item stays put and appended items use it up.
      _trailingSpace = contentChanged && _pinnedIndex != null
          ? needed
          : math.min(_trailingSpace, needed);
      if (_trailingSpace < _kTargetTolerance) {
        _trailingSpace = 0.0;
      }
    }
    final endScrollOffset = _totalExtent() + _trailingSpace;

    if (!_didResolveInitialScrollPosition &&
        _initialScrollPosition == InitialScrollPosition.end &&
        totalChildCount > 0) {
      if (_applyInitialEndCorrection(_totalExtent(), layoutPass)) return;
      _didResolveInitialScrollPosition = true;
    }
    final cacheStart = constraints.scrollOffset + constraints.cacheOrigin;
    final lastChildEnd =
        childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);
    var cacheConsumed = (lastChildEnd - cacheStart).clamp(
      0.0,
      constraints.remainingCacheExtent,
    );
    var paintExtent = calculatePaintOffset(
      constraints,
      from: childScrollOffset(firstChild!)!,
      to: endScrollOffset,
    );

    // If remaining paint extent is consumed, make sure to use the *exact* value.
    // Otherwise, even if the delta is extremely small, Flutter will consider
    // next sliver visible, which means that our layoutOffset will be used
    // determine paint position of render boxes inside next sliver (even if
    // invisible these affects directional focus for example). That leads
    // to incorrect results if we're in the middle of sliver.
    if ((constraints.remainingPaintExtent - paintExtent).abs() <
        precisionErrorTolerance) {
      paintExtent = constraints.remainingPaintExtent;
    }

    if (paintExtent == constraints.remainingPaintExtent &&
        didDelayPopulatingCacheArea) {
      cacheConsumed = constraints.remainingCacheExtent;
    }

    _updateVisibleChildren(paintExtent: paintExtent);

    geometry = SliverGeometry(
      scrollExtent: endScrollOffset,
      paintExtent: paintExtent,
      maxPaintExtent: endScrollOffset,
      cacheExtent: cacheConsumed,
      hasVisualOverflow:
          endScrollOffset > constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0.0,
    );
    if (_log.isLoggable(Level.FINE)) {
      _log.fine(
        "Have geometry for $_logIdentifier (scroll extent: $endScrollOffset, paint extent: $paintExtent, cache consumed: $cacheConsumed, dirty extents: ${_extentManager.hasDirtyItems})",
      );
    }

    if (paintExtent < constraints.remainingPaintExtent) {
      childManager.setDidUnderflow(true);
    }

    childManager.didFinishLayout();
  }

  /// The laid out child that contains the leading edge of the visible area.
  RenderBox? _leadingEdgeChild() {
    final scrollOffset = constraints.scrollOffset;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final layoutOffset = _parentDataOf(child).layoutOffset;
      if (layoutOffset == null || !child.hasSize) {
        return null;
      }
      if (layoutOffset > scrollOffset) {
        return null;
      }
      if (layoutOffset + paintExtentOf(child) > scrollOffset) {
        return child;
      }
    }
    return null;
  }

  void _updateVisibleChildren({required double paintExtent}) {
    if (paintExtent == 0) {
      return;
    }

    final minStart = constraints.scrollOffset;
    final maxStart = minStart + paintExtent;

    final unobstructedMinStart = minStart + constraints.overlap;
    final unobstructedMaxStart = maxStart;

    int min = -1;
    int max = -1;
    int unobstructedMin = -1;
    int unobstructedMax = -1;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      final start = data.layoutOffset!;
      final end = start + paintExtentOf(child);
      final index = _indexOf(child);
      if (end > minStart && min == -1) {
        min = index;
        max = index;
      } else if (start < maxStart) {
        max = index;
      }
      if (end > unobstructedMinStart && unobstructedMin == -1) {
        unobstructedMin = index;
        unobstructedMax = index;
      } else if (start < unobstructedMaxStart) {
        unobstructedMax = index;
      }
    }
    if (min != -1) {
      assert(max != -1);
      _extentManager.reportVisibleChildrenRange(min, max);
    }

    if (unobstructedMin != -1) {
      assert(unobstructedMax != -1);
      _extentManager.reportUnobstructedVisibleChildrenRange(
        unobstructedMin,
        unobstructedMax,
      );
    }
  }

  void _zeroGeometry() {
    geometry = SliverGeometry.zero;
    childManager.didFinishLayout();
  }

  int? indexForOffset(double offset) {
    return _extentManager.indexForOffset(offset);
  }

  double offsetForIndex(int index) {
    return _extentManager.offsetForIndex(index);
  }

  double _totalExtent() {
    return _extentManager.totalExtent;
  }

  /// Approximates the sliver-local scroll offset that would place [target]'s
  /// reveal rect at the requested viewport alignment.
  ///
  /// This is an inexpensive approximation of what [getOffsetToReveal] computes
  /// (which requires a full viewport traversal and can't safely run mid-layout).
  /// It's accurate for the common single-sliver case and close enough for
  /// multi-sliver viewports to drive the clamped-vs-reachable decision.
  double _desiredSliverOffsetForTarget(StickTarget target) {
    final itemOffset = _extentManager.offsetForIndex(target.index);
    final rectTop = target.rect?.top ?? 0;
    final rectHeight = target.rect?.height ?? 0;
    return itemOffset +
        rectTop -
        (constraints.viewportMainAxisExtent - rectHeight) * target.alignment;
  }

  @override
  @protected
  RenderBox? insertAndLayoutLeadingChild(
    BoxConstraints childConstraints, {
    bool parentUsesSize = false,
  }) {
    final res = super.insertAndLayoutLeadingChild(
      childConstraints,
      parentUsesSize: parentUsesSize,
    );
    if (res != null) {
      _extentManager.setExtent(_indexOf(res), paintExtentOf(res));
    }
    return res;
  }

  double getOffsetToReveal(
    int index,
    double alignment, {
    required bool estimationOnly,
    Rect? rect,
  }) {
    final renderObject = _FakeRenderObject(
      parent: this,
      index: index,
      extent: _extentManager.getExtent(index),
      layoutOffset: _extentManager.offsetForIndex(index),
    );
    try {
      final viewport = getViewport()!;
      return viewport
          .getOffsetToRevealExt(
            renderObject,
            alignment,
            esimationOnly: estimationOnly,
            rect: rect,
          )
          .offset;
    } finally {
      renderObject.dispose();
    }
  }

  @override
  void valueDidChange() {
    markNeedsLayout();
  }

  @override
  void applyPaintTransform(covariant RenderBox child, Matrix4 transform) {
    // We actually lay out kept alive children, and as such we can provide valid
    // paint transform.
    final parentData = child.parentData! as SliverMultiBoxAdaptorParentData;
    if (layoutKeptAliveChildren &&
        parentData.keptAlive &&
        parentData.layoutOffset != null) {
      applyPaintTransformForBoxChild(child, transform);
    } else {
      super.applyPaintTransform(child, transform);
    }
  }
}

// This is little bit hacky way to reuse logic of RenderViewport.getOffsetToReveal in case
// where we don't really have a render object.
class _FakeRenderObject extends RenderBox {
  @override
  final RenderObject parent;
  final double extent;
  final double layoutOffset;

  _FakeRenderObject({
    required this.parent,
    required int index,
    required this.extent,
    required this.layoutOffset,
  }) {
    parentData = SliverMultiBoxAdaptorParentData()
      ..index = index
      ..layoutOffset = layoutOffset;
  }

  @override
  Size get size => Size(extent, extent);

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) {
    return Matrix4.identity();
  }
}

extension on double {
  String format() {
    final res = toStringAsFixed(5);
    var len = res.length;
    while (len > 1 && res[len - 1] == "0") {
      --len;
    }
    if (len > 1 && res[len - 1] == ".") {
      ++len; // leave one zero
    }
    return res.substring(0, len);
  }
}

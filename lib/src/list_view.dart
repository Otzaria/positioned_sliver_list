import "dart:math" as math;

import "package:flutter/widgets.dart";

import "super_sliver_list.dart";

/// A [ListView] backed by [SuperSliverList], with index-based navigation.
/// Extent lookups and measured updates are logarithmic in the item count;
/// metadata and full estimate refreshes are linear in that count.
class SuperListView extends BoxScrollView {
  SuperListView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    super.scrollCacheExtent,
    List<Widget> children = const <Widget>[],
    int? semanticChildCount,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.listController,
    this.extentEstimation,
    this.estimationKey,
    this.crossAxisLayoutKey,
    this.extentPrecalculationPolicy,
    this.delayPopulatingCacheArea = false,
    this.initialScrollPosition = InitialScrollPosition.start,
    this.initialIndex,
    this.initialAlignment = 0.0,
    this.initialOffset = 0.0,
    this.initialTargetRectResolver,
    this.overscrollToTarget = OverscrollToTarget.none,
  }) : childrenDelegate = SliverChildListDelegate(
         children,
         addAutomaticKeepAlives: addAutomaticKeepAlives,
         addRepaintBoundaries: addRepaintBoundaries,
         addSemanticIndexes: addSemanticIndexes,
       ),
       super(semanticChildCount: semanticChildCount ?? children.length);

  /// Creates a new [SuperListView] that builds its children dynamically.
  ///
  /// See [ListView.builder] for details.
  SuperListView.builder({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    required NullableIndexedWidgetBuilder itemBuilder,
    ChildIndexGetter? findChildIndexCallback,
    int? itemCount,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    super.scrollCacheExtent,
    int? semanticChildCount,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.listController,
    this.extentEstimation,
    this.estimationKey,
    this.crossAxisLayoutKey,
    this.extentPrecalculationPolicy,
    this.delayPopulatingCacheArea = false,
    this.initialScrollPosition = InitialScrollPosition.start,
    this.initialIndex,
    this.initialAlignment = 0.0,
    this.initialOffset = 0.0,
    this.initialTargetRectResolver,
    this.overscrollToTarget = OverscrollToTarget.none,
  }) : assert(itemCount == null || itemCount >= 0),
       assert(semanticChildCount == null || semanticChildCount <= itemCount!),
       childrenDelegate = SliverChildBuilderDelegate(
         itemBuilder,
         findChildIndexCallback: findChildIndexCallback,
         childCount: itemCount,
         addAutomaticKeepAlives: addAutomaticKeepAlives,
         addRepaintBoundaries: addRepaintBoundaries,
         addSemanticIndexes: addSemanticIndexes,
       ),
       super(semanticChildCount: semanticChildCount ?? itemCount);

  /// Creates a [SuperListView] with "items" separated by list item "separators".
  ///
  /// See [ListView.separated] for details.
  SuperListView.separated({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    required NullableIndexedWidgetBuilder itemBuilder,
    ChildIndexGetter? findChildIndexCallback,
    required IndexedWidgetBuilder separatorBuilder,
    required int itemCount,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    super.scrollCacheExtent,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.listController,
    this.extentEstimation,
    this.estimationKey,
    this.crossAxisLayoutKey,
    this.extentPrecalculationPolicy,
    this.delayPopulatingCacheArea = false,
    this.initialScrollPosition = InitialScrollPosition.start,
    this.initialIndex,
    this.initialAlignment = 0.0,
    this.initialOffset = 0.0,
    this.initialTargetRectResolver,
    this.overscrollToTarget = OverscrollToTarget.none,
  }) : assert(itemCount >= 0),
       childrenDelegate = SliverChildBuilderDelegate(
         (BuildContext context, int index) {
           final int itemIndex = index ~/ 2;
           if (index.isEven) {
             return itemBuilder(context, itemIndex);
           }
           return separatorBuilder(context, itemIndex);
         },
         findChildIndexCallback: findChildIndexCallback,
         childCount: _computeActualChildCount(itemCount),
         addAutomaticKeepAlives: addAutomaticKeepAlives,
         addRepaintBoundaries: addRepaintBoundaries,
         addSemanticIndexes: addSemanticIndexes,
         semanticIndexCallback: (Widget widget, int index) {
           return index.isEven ? index ~/ 2 : null;
         },
       ),
       super(semanticChildCount: itemCount);

  /// Creates [SuperListView] with a custom child model.
  ///
  /// See [ListView.custom] for details.
  const SuperListView.custom({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    required this.childrenDelegate,
    super.scrollCacheExtent,
    super.semanticChildCount,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.listController,
    this.extentEstimation,
    this.estimationKey,
    this.crossAxisLayoutKey,
    this.extentPrecalculationPolicy,
    this.delayPopulatingCacheArea = false,
    this.initialScrollPosition = InitialScrollPosition.start,
    this.initialIndex,
    this.initialAlignment = 0.0,
    this.initialOffset = 0.0,
    this.initialTargetRectResolver,
    this.overscrollToTarget = OverscrollToTarget.none,
  });

  /// A delegate that provides the children for the [ListView].
  ///
  /// The [ListView.custom] constructor lets you specify this delegate
  /// explicitly. The [ListView] and [ListView.builder] constructors create a
  /// [childrenDelegate] that wraps the given [List] and [IndexedWidgetBuilder],
  /// respectively.
  final SliverChildDelegate childrenDelegate;

  /// When set provides access to extents of individual children.
  /// [ListController] can also be used to jump to a specific item in the list.
  final ListController? listController;

  /// Optional method that can be used to override default estimated extent for
  /// each item. Initially all extents are estimated and then as the items are laid
  /// out, either through scrolling or [extentPrecalculationPolicy], the actual
  /// extents are calculated and the scroll offset is adjusted to account for
  /// the difference between estimated and actual extents.
  final ExtentEstimationProvider? extentEstimation;

  /// Changes when the meaning of [extentEstimation] changes.
  /// Callback identity alone never invalidates cached estimates.
  final Object? estimationKey;

  /// See [SuperSliverList.crossAxisLayoutKey].
  final CrossAxisLayoutKey? crossAxisLayoutKey;

  /// Optional policy that can be used to asynchronously precalculate the extents
  /// of the items in the list. This can be useful allow precise scrolling on small
  /// lists where the difference between estimated and actual extents may be noticeable
  /// when interacting with the scrollbar. For larger lists precalculating extent
  /// has diminishing benefits since the error for each item does not impact the
  /// overall scroll position as much.
  final ExtentPrecalculationPolicy? extentPrecalculationPolicy;

  /// Whether the items in cache area should be built delayed.
  /// This is an optimization that kicks in during fast scrolling, when
  /// all items are being replaced on every frame.
  /// With [delayPopulatingCacheArea] set to `true`, the items in cache area
  /// are only built after the scrolling slows down.
  final bool delayPopulatingCacheArea;

  /// Where the list should begin when it is laid out for the first time.
  final InitialScrollPosition initialScrollPosition;

  /// Index of the item whose leading edge is placed at [initialAlignment] of
  /// the viewport plus [initialOffset] pixels when the list is laid out for
  /// the first time. Applied before the first paint; later changes are
  /// ignored. Takes precedence over [initialScrollPosition].
  final int? initialIndex;

  /// Fraction of the viewport where the leading edge of the item at
  /// [initialIndex] is placed. 0 is the leading edge, 1 the trailing edge.
  final double initialAlignment;

  /// Pixels added to [initialAlignment].
  final double initialOffset;

  /// Resolves the initial target inside the item before the first paint.
  final TargetRectResolver? initialTargetRectResolver;

  /// See [SuperSliverList.overscrollToTarget].
  final OverscrollToTarget overscrollToTarget;

  @override
  Widget buildChildLayout(BuildContext context) {
    return SuperSliverList(
      delegate: childrenDelegate,
      listController: listController,
      delayPopulatingCacheArea: delayPopulatingCacheArea,
      extentEstimation: extentEstimation,
      estimationKey: estimationKey,
      crossAxisLayoutKey: crossAxisLayoutKey,
      extentPrecalculationPolicy: extentPrecalculationPolicy,
      initialScrollPosition: initialScrollPosition,
      initialIndex: initialIndex,
      initialAlignment: initialAlignment,
      initialOffset: initialOffset,
      initialTargetRectResolver: initialTargetRectResolver,
      overscrollToTarget: overscrollToTarget,
    );
  }

  // Helper method to compute the actual child count for the separated constructor.
  static int _computeActualChildCount(int itemCount) {
    return math.max(0, itemCount * 2 - 1);
  }
}

// Stand-ins for internals of scrollable_positioned_list that its tests use,
// mapped onto the compatibility widget.

import "package:flutter/widgets.dart";
import "package:positioned_sliver_list/positioned_list.dart";

typedef ItemPositionsNotifier = ItemPositionsListener;

typedef UnboundedCustomScrollView = CustomScrollView;

/// The single list of the original, with [positionedIndex] at [alignment].
class PositionedList extends StatelessWidget {
  const PositionedList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.controller,
    this.itemPositionsNotifier,
    this.positionedIndex = 0,
    this.alignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.cacheExtent,
    this.semanticChildCount,
    this.addSemanticIndexes = true,
    this.addRepaintBoundaries = true,
    this.addAutomaticKeepAlives = true,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final ScrollController? controller;
  final ItemPositionsNotifier? itemPositionsNotifier;
  final int positionedIndex;
  final double alignment;
  final Axis scrollDirection;
  final bool reverse;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  final double? cacheExtent;
  final int? semanticChildCount;
  final bool addSemanticIndexes;
  final bool addRepaintBoundaries;
  final bool addAutomaticKeepAlives;

  @override
  Widget build(BuildContext context) {
    final separatorBuilder = this.separatorBuilder;
    final cacheExtentScreens = cacheExtent == null ? 2.0 : 0.0;
    if (separatorBuilder != null) {
      return ScrollablePositionedList.separated(
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: separatorBuilder,
        scrollController: controller,
        itemPositionsListener: itemPositionsNotifier,
        initialScrollIndex: positionedIndex,
        initialAlignment: alignment,
        scrollDirection: scrollDirection,
        reverse: reverse,
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: padding,
        minCacheExtent: cacheExtent,
        cacheExtentScreens: cacheExtentScreens,
        semanticChildCount: semanticChildCount,
        addSemanticIndexes: addSemanticIndexes,
        addRepaintBoundaries: addRepaintBoundaries,
        addAutomaticKeepAlives: addAutomaticKeepAlives,
      );
    }
    return ScrollablePositionedList.builder(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      scrollController: controller,
      itemPositionsListener: itemPositionsNotifier,
      initialScrollIndex: positionedIndex,
      initialAlignment: alignment,
      scrollDirection: scrollDirection,
      reverse: reverse,
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: padding,
      minCacheExtent: cacheExtent,
      cacheExtentScreens: cacheExtentScreens,
      semanticChildCount: semanticChildCount,
      addSemanticIndexes: addSemanticIndexes,
      addRepaintBoundaries: addRepaintBoundaries,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
    );
  }
}

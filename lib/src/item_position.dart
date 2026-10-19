import "package:flutter/foundation.dart";

/// Position of a laid out item relative to the viewport.
///
/// Edges are fractions of the viewport's main axis extent, measured from the
/// viewport's leading edge (the top of a vertical list, or the bottom when the
/// list is reversed).
@immutable
class ItemPosition {
  const ItemPosition({
    required this.index,
    required this.itemLeadingEdge,
    required this.itemTrailingEdge,
  });

  /// Index of the item.
  final int index;

  /// Distance from the viewport's leading edge to the item's leading edge,
  /// as a fraction of the viewport extent. Negative when the item starts
  /// before the viewport.
  final double itemLeadingEdge;

  /// Distance from the viewport's leading edge to the item's trailing edge,
  /// as a fraction of the viewport extent. Greater than one when the item ends
  /// after the viewport.
  final double itemTrailingEdge;

  @override
  bool operator ==(Object other) {
    return other is ItemPosition &&
        other.runtimeType == runtimeType &&
        other.index == index &&
        other.itemLeadingEdge == itemLeadingEdge &&
        other.itemTrailingEdge == itemTrailingEdge;
  }

  @override
  int get hashCode => Object.hash(index, itemLeadingEdge, itemTrailingEdge);

  @override
  String toString() =>
      "ItemPosition(index: $index, "
      "itemLeadingEdge: $itemLeadingEdge, itemTrailingEdge: $itemTrailingEdge)";
}

/// The item at the leading edge of the viewport and how far the viewport
/// edge is inside it.
@immutable
class ListAnchor {
  const ListAnchor({
    required this.index,
    required this.offsetInItem,
    required this.itemExtent,
  });

  /// Index of the first item that is at least partially visible.
  final int index;

  /// Pixels from the item's leading edge to the viewport's leading edge.
  final double offsetInItem;

  /// Main axis extent of the item.
  final double itemExtent;

  /// [offsetInItem] as a fraction of [itemExtent].
  double get fraction => itemExtent > 0 ? offsetInItem / itemExtent : 0.0;

  @override
  bool operator ==(Object other) {
    return other is ListAnchor &&
        other.index == index &&
        other.offsetInItem == offsetInItem &&
        other.itemExtent == itemExtent;
  }

  @override
  int get hashCode => Object.hash(index, offsetInItem, itemExtent);

  @override
  String toString() =>
      "ListAnchor(index: $index, "
      "offsetInItem: $offsetInItem, itemExtent: $itemExtent)";
}

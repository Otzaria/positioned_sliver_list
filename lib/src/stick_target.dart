import "dart:ui";

/// Describes what the scroll view should stick to.
///
/// Used by [StickToTarget] and communicated to the render object via
/// [ListController.stickTarget] for zero-lag corrections during layout.
class StickTarget {
  /// Pin a specific item at a specific viewport position.
  const StickTarget({
    required this.index,
    required this.alignment,
    this.rect,
  });

  /// Stick to the trailing edge of the list.
  ///
  /// The render object applies scroll offset corrections during layout
  /// to keep the bottom pinned — zero lag, no post-frame callback needed.
  const StickTarget.bottom()
      : index = -1,
        alignment = 1.0,
        rect = null;

  /// Whether this target represents simple stick-to-bottom behavior.
  bool get isBottom => index == -1;

  /// The item index to pin, or -1 for [bottom].
  final int index;

  /// Where in the viewport to pin it.
  /// 0.0 = leading edge, 0.5 = center, 1.0 = trailing edge.
  final double alignment;

  /// Optional: a sub-rect of the item to target.
  final Rect? rect;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StickTarget &&
          other.index == index &&
          other.alignment == alignment &&
          other.rect == rect;

  @override
  int get hashCode => Object.hash(index, alignment, rect);
}

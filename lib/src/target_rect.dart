import "package:flutter/rendering.dart";

/// Resolves a target area in a laid-out item's local coordinates.
///
/// The leading edge is aligned with the viewport. Return null to target the
/// whole item. The callback may run more than once and must not change layout.
typedef TargetRectResolver = Rect? Function(int index, RenderBox box);

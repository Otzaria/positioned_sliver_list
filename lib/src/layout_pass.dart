import "dart:math" as math;

import "package:collection/collection.dart";
import "package:flutter/rendering.dart";

import "render_object.dart";

class SliverLayoutState {
  bool didAddInitialChild = false;
  bool didRemoveChildren = false;
  bool didSetPreviousConstraint = false;
  bool crossAxisResizing = false;
  bool layoutRelevantResize = false;
  int? extentRevision;
  bool? precalculateExtents;

  /// First appearance in the viewport's layout pass; null until laid out.
  int? firstLayoutOrder;
}

class LayoutPass {
  LayoutPass({
    required this.slivers,
    required this.initialScrollPosition,
    required this.childScrollOffsetEstimation,
    required this.sliverWithOffsetEstimation,
    required this.maxCorrectionCount,
  });

  bool isNew = true;

  final List<RenderSuperSliverList> slivers;
  final double initialScrollPosition;
  final bool childScrollOffsetEstimation;
  final RenderSuperSliverList? sliverWithOffsetEstimation;

  final sliversDuringLayout = <RenderSuperSliverList>[];

  /// Records the first appearance of a sliver in this layout pass.
  ///
  /// Reuse the existing per-sliver state map rather than allocating a second
  /// map every frame. This avoids an O(n) indexOf scan for each delayed sliver.
  void recordLaidOutSliver(RenderSuperSliverList sliver) {
    final state = getLayoutState(sliver);
    if (state.firstLayoutOrder != null) return;
    state.firstLayoutOrder = sliversDuringLayout.length;
    sliversDuringLayout.add(sliver);
  }

  /// The first-layout order, or -1 when this sliver has not laid out.
  int layoutOrderOf(RenderSuperSliverList sliver) =>
      _sliverLayoutState[sliver]?.firstLayoutOrder ?? -1;

  /// Returns whether provided sliver is laid out before a sliver with active
  /// scroll offset estimation. If there is no sliver with active scroll offset
  /// estimation, returns false.
  bool sliverIsBeforeSliverWithOffsetEstimation(RenderSuperSliverList s) {
    assert(layoutOrderOf(s) >= 0);
    if (sliverWithOffsetEstimation == null) {
      return false;
    }
    final index = layoutOrderOf(sliverWithOffsetEstimation!);
    return index == -1 || index > layoutOrderOf(s);
  }

  SliverLayoutState getLayoutState(RenderSuperSliverList sliver) {
    return _sliverLayoutState.putIfAbsent(sliver, () => SliverLayoutState());
  }

  final _sliverLayoutState = <RenderSuperSliverList, SliverLayoutState>{};

  int correctionCount = 0;

  /// Scroll offset corrections allowed in this pass; further ones wait for the
  /// next frame. A viewport throws after 10 layout cycles per child sliver.
  final int maxCorrectionCount;
}

final _viewportToLayoutPass = Expando<LayoutPass>();

extension RenderSliverLayoutPass on RenderSliver {
  RenderViewportBase? getViewport() {
    RenderObject? parent = this.parent;
    while (parent != null) {
      if (parent is RenderViewportBase) {
        return parent;
      }
      parent = parent.parent;
    }
    return null;
  }

  static void _gatherSliverList(
    List<RenderSuperSliverList> slivers,
    RenderObject sliver,
  ) {
    if (sliver is RenderSuperSliverList) {
      slivers.add(sliver);
    } else {
      sliver.visitChildren((child) {
        if (child is RenderSliver) {
          _gatherSliverList(slivers, child);
        }
      });
    }
  }

  List<RenderSuperSliverList> getSuperSliverLists() {
    final slivers = <RenderSuperSliverList>[];
    final viewport = getViewport();
    if (viewport != null) {
      _gatherSliverList(slivers, viewport);
    }
    return slivers;
  }

  LayoutPass? getLayoutPass(RenderSuperSliverList self) {
    final viewport = getViewport();
    if (viewport == null) {
      return null;
    }
    var pass = _viewportToLayoutPass[viewport];
    if (pass == null) {
      final slivers = getSuperSliverLists();
      var sliverWithOffsetEstimation = slivers.firstWhereOrNull(
        (element) => element.hasChildScrollOffsetEstimation,
      );
      if (sliverWithOffsetEstimation != null) {
        sliverWithOffsetEstimation.sanitizeChildScrollOffsetEstimation(
          viewport,
        );
        if (!sliverWithOffsetEstimation.hasChildScrollOffsetEstimation) {
          sliverWithOffsetEstimation = null;
        }
      }
      pass = LayoutPass(
        slivers: slivers,
        // Note: This only works if there are no other sliver being laid out
        // first that do scroll offset correction. Unfortunately there isn't any
        // way in Flutter to get the original (uncorrected) scroll position.
        initialScrollPosition: viewport.offset.pixels,
        childScrollOffsetEstimation: sliverWithOffsetEstimation != null,
        sliverWithOffsetEstimation: sliverWithOffsetEstimation,
        maxCorrectionCount: math.max(7, 10 * viewport.childCount - 3),
      );
      _viewportToLayoutPass[viewport] = pass;
      Future.microtask(() {
        _viewportToLayoutPass[viewport] = null;
      });
    }
    pass.recordLaidOutSliver(self);
    return pass;
  }
}

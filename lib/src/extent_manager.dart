import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart" show ScrollPosition;
import "estimate_refresh_stats.dart";
import "extent_list.dart";
import "header_anchor.dart";
import "item_position.dart";
import "stick_target.dart";
import "target_rect.dart";

abstract class ExtentManagerDelegate {
  const ExtentManagerDelegate();

  void onMarkNeedsLayout();
  HeaderAnchorHandle? preserveHeader(RenderBox header) => null;
  Future<void> jumpToIndex(
    int index,
    double alignment,
    double offset, {
    TargetRectResolver? targetRectResolver,
  }) => Future<void>.value();
  double? pixelsForIndex(
    int index,
    double alignment,
    double offset, {
    TargetRectResolver? targetRectResolver,
  }) => null;
  int? indexForScrollOffset(double pixels) => null;
  ListAnchor? get currentAnchor => null;
  List<ItemPosition>? computeItemPositions() => null;
  void requestItemPositions() {}
  bool get hasPendingTarget => false;
  ScrollPosition? get scrollPosition => null;
  void reserveOverscrollSpace(
    int index,
    double alignment,
    double offset, {
    TargetRectResolver? targetRectResolver,
  }) {}
  set holdOverscrollSpace(bool value) {}
  ({double leading, double trailing}) get overscrollSpace =>
      (leading: 0.0, trailing: 0.0);
  double estimateExtentForItem(int? index);
  double getOffsetToReveal(
    int index,
    double alignment, {
    required bool estimationOnly,
    Rect? rect,
  });
}

@immutable
class ItemRange {
  const ItemRange(this.first, this.last)
    : assert(first >= 0),
      assert(last >= first);

  final int first;
  final int last;

  @override
  bool operator ==(Object other) {
    return other is ItemRange && other.first == first && other.last == last;
  }

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => "ItemRange($first, $last)";
}

/// Receives item positions published after layout.
abstract class ItemPositionsSink {
  /// Whether anyone listens; positions are only computed when true.
  bool get wantsItemPositions;

  void updateItemPositions(List<ItemPosition> positions);
}

class _ExtentsChangedNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class ExtentManager with ChangeNotifier {
  ExtentManager({required this.delegate});

  final _extentsChangedNotifier = _ExtentsChangedNotifier();

  /// Notifies only when item extents or item count change - unlike the
  /// [ExtentManager] itself, which also notifies on pure visible-range
  /// changes (i.e. on every scroll frame). Listeners that only care about
  /// content geometry (such as [StickToTarget]) should prefer this channel.
  Listenable get extentsChangedListenable => _extentsChangedNotifier;

  bool _extentsModified = false;

  @override
  void dispose() {
    for (final completer in [
      ..._pendingEstimateCompleters,
      ..._appliedEstimateCompleters,
    ]) {
      completer.complete();
    }
    _pendingEstimateCompleters.clear();
    _appliedEstimateCompleters.clear();
    _extentsChangedNotifier.dispose();
    super.dispose();
  }

  double _beforeCorrection = 0.0;
  double _afterCorrection = 0.0;

  final ExtentManagerDelegate delegate;

  /// The current stick target, if any.
  ///
  /// When [StickTarget.isBottom] is `true`, the render object applies scroll
  /// offset corrections during layout to keep the trailing edge pinned.
  StickTarget? stickTarget;

  Object? revealOwner;

  /// Destination for item positions computed after each layout.
  ItemPositionsSink? itemPositionsSink;

  Object beginReveal() => revealOwner = Object();

  void cancelReveal([Object? owner]) {
    if (owner == null || identical(owner, revealOwner)) revealOwner = null;
  }

  double get correctionPercentage {
    // Handle edge cases to avoid division by zero and invalid results
    if (_beforeCorrection.abs() < precisionErrorTolerance) {
      return 1.0;
    }

    final result = _afterCorrection / _beforeCorrection;

    // Sanity check: if result is NaN or infinite, something went wrong
    // Return 1.0 (no correction) as a safe fallback
    if (!result.isFinite) {
      assert(
        false,
        "correctionPercentage resulted in non-finite value: "
        "beforeCorrection=$_beforeCorrection, afterCorrection=$_afterCorrection",
      );
      return 1.0;
    }

    return result;
  }

  void setExtent(int index, double extent, {bool isEstimation = false}) {
    final oldExtent = _extentList[index];
    // Use tolerance for comparison to avoid spurious notifications from
    // floating-point precision errors
    final extentChanged = (oldExtent - extent).abs() > precisionErrorTolerance;
    bool wasDirty = false;

    if (!extentChanged &&
        !isEstimation &&
        (!_isModified || !_extentsModified)) {
      wasDirty = _extentList.isDirty(index);
    }

    if (!isEstimation) {
      _beforeCorrection += oldExtent;
      _afterCorrection += extent;
    }

    _extentList.setExtent(index, extent, isEstimation: isEstimation);

    if (extentChanged) {
      ++extentRevision;
    }
    if (extentChanged || (!isEstimation && wasDirty)) {
      _isModified = true;
      _extentsModified = true;
    }
  }

  /// Incremented whenever an extent value or the item count changes.
  int extentRevision = 0;

  void markAllDirty() {
    _refreshAllEstimates = true;
  }

  bool _refreshAllEstimates = false;
  final _invalidatedEstimates = <int>{};
  final _pendingEstimates = <int, double>{};
  final _pendingEstimateCompleters = <Completer<void>>[];
  final _appliedEstimateCompleters = <Completer<void>>[];
  bool _estimateCompletionScheduled = false;
  bool _batchedListChanged = false;
  bool _batchedExtentsChanged = false;

  bool get hasPendingEstimateUpdates =>
      _refreshAllEstimates ||
      _invalidatedEstimates.isNotEmpty ||
      _pendingEstimates.isNotEmpty;

  void _checkUnlocked() {
    if (isLocked) {
      throw StateError("Item extents cannot be changed during layout.");
    }
  }

  Future<void> updateEstimatedExtents(Map<int, double> extents) {
    _checkUnlocked();
    for (final entry in extents.entries) {
      RangeError.checkValidIndex(
        entry.key,
        _extentList,
        "index",
        numberOfItems,
      );
      if (!entry.value.isFinite || entry.value < 0) {
        throw ArgumentError.value(
          entry.value,
          "extent",
          "Must be finite and nonnegative.",
        );
      }
    }
    if (extents.isEmpty) return Future<void>.value();
    _pendingEstimates.addAll(extents);
    _invalidatedEstimates.removeAll(extents.keys);
    final completer = Completer<void>();
    _pendingEstimateCompleters.add(completer);
    delegate.onMarkNeedsLayout();
    return completer.future;
  }

  void applyPendingEstimateUpdates() {
    assert(isLocked);
    if (!kReleaseMode) {
      FlutterTimeline.startSync(
        "PositionedSliverList.applyPendingEstimateUpdates",
        arguments: {
          "refresh": _refreshAllEstimates ? "all" : "none",
          "invalidated": _invalidatedEstimates.length,
          "pending": _pendingEstimates.length,
        },
      );
    }
    try {
      _applyPendingEstimateUpdates();
    } finally {
      if (!kReleaseMode) FlutterTimeline.finishSync();
    }
  }

  void _applyPendingEstimateUpdates() {
    if (_refreshAllEstimates) {
      _extentList.refreshEstimates(delegate.estimateExtentForItem);
      _refreshAllEstimates = false;
    }
    for (final index in _invalidatedEstimates) {
      if (index < numberOfItems) {
        _extentList.setExtent(
          index,
          delegate.estimateExtentForItem(index),
          isEstimation: true,
        );
        _extentList.markDirty(index);
      }
    }
    for (final entry in _pendingEstimates.entries) {
      if (entry.key < numberOfItems) {
        _extentList.setExtent(entry.key, entry.value, isEstimation: true);
        _extentList.markDirty(entry.key);
      }
    }
    _invalidatedEstimates.clear();
    _pendingEstimates.clear();
    _appliedEstimateCompleters.addAll(_pendingEstimateCompleters);
    _pendingEstimateCompleters.clear();
    ++extentRevision;
    _isModified = true;
    _extentsModified = true;
  }

  void completeEstimateUpdates() {
    if (_appliedEstimateCompleters.isEmpty || _estimateCompletionScheduled) {
      return;
    }
    _estimateCompletionScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _estimateCompletionScheduled = false;
      final completers = List<Completer<void>>.of(_appliedEstimateCompleters);
      _appliedEstimateCompleters.clear();
      if (completers.isEmpty) return;
      final listChanged = _batchedListChanged;
      final extentsChanged = _batchedExtentsChanged;
      _batchedListChanged = false;
      _batchedExtentsChanged = false;
      if (listChanged) notifyListeners();
      if (extentsChanged) _extentsChangedNotifier.notify();
      for (final completer in completers) {
        completer.complete();
      }
    });
  }

  bool get hasDirtyItems => _extentList.hasDirtyItems;

  double get totalExtent => _extentList.totalExtent;

  int? get cleanRangeStart => _extentList.cleanRangeStart;
  int? get cleanRangeEnd => _extentList.cleanRangeEnd;

  @pragma("vm:prefer-inline")
  double getExtent(int index) => _extentList[index];

  void resize(int newSize) {
    if (newSize == _extentList.length) {
      return;
    }
    _isModified = true;
    _extentsModified = true;
    ++extentRevision;
    _extentList.resize(newSize, delegate.estimateExtentForItem);
  }

  final _extentList = ExtentList();

  /// Counters for O(n) estimate refreshes and offset index rebuilds; the
  /// extent list records its own operations here.
  EstimateRefreshCounters get _refreshCounters => _extentList.counters;

  EstimateRefreshStats get estimateRefreshStats => _refreshCounters.snapshot();

  int? indexForOffset(double offset) {
    return _extentList.indexForOffset(offset);
  }

  double offsetForIndex(int index) {
    assert(index >= 0 && index < _extentList.length);
    return _extentList.offsetForIndex(index);
  }

  (double, bool) extentForIndex(int index) {
    return (_extentList[index], _extentList.isDirty(index));
  }

  bool _layoutInProgress = false;
  bool _isModified = false;

  bool _didReportVisibleChildren = false;
  bool _didReportUnobstructedVisibleChildren = false;

  void performLayout(VoidCallback layout) {
    assert(!_layoutInProgress);
    _layoutInProgress = true;
    _isModified = false;
    _extentsModified = false;
    _didReportVisibleChildren = false;
    _didReportUnobstructedVisibleChildren = false;
    _beforeCorrection = 0.0;
    _afterCorrection = 0.0;

    try {
      layout();
    } finally {
      assert(_layoutInProgress);
      // Not reporting children means there are no visible children - set the
      // visible range to null.
      if (!_didReportVisibleChildren) {
        reportVisibleChildrenRange(null, null);
      }
      if (!_didReportUnobstructedVisibleChildren) {
        reportUnobstructedVisibleChildrenRange(null, null);
      }
      _layoutInProgress = false;
      if (_pendingEstimateCompleters.isNotEmpty ||
          _appliedEstimateCompleters.isNotEmpty) {
        _batchedListChanged |= _isModified;
        _batchedExtentsChanged |= _extentsModified;
      } else {
        if (_isModified) notifyListeners();
        if (_extentsModified) _extentsChangedNotifier.notify();
      }
    }
  }

  void reportVisibleChildrenRange(int? start, int? end) {
    assert(_layoutInProgress);
    final current = _visibleRange;
    if (start == null || end == null) {
      if (current != null) {
        _visibleRange = null;
        _isModified = true;
      }
      _didReportVisibleChildren = true;
      return;
    }

    if (current != null && current.first == start && current.last == end) {
      _didReportVisibleChildren = true;
      return;
    }

    _visibleRange = ItemRange(start, end);
    _isModified = true;
    _didReportVisibleChildren = true;
  }

  @Deprecated("Use reportVisibleChildrenRange")
  void reportVisibleChildren((int, int)? range) {
    if (range == null) {
      reportVisibleChildrenRange(null, null);
    } else {
      reportVisibleChildrenRange(range.$1, range.$2);
    }
  }

  void reportUnobstructedVisibleChildrenRange(int? start, int? end) {
    assert(_layoutInProgress);
    final current = _unobstructedVisibleRange;
    if (start == null || end == null) {
      if (current != null) {
        _unobstructedVisibleRange = null;
        _isModified = true;
      }
      _didReportUnobstructedVisibleChildren = true;
      return;
    }

    if (current != null && current.first == start && current.last == end) {
      _didReportUnobstructedVisibleChildren = true;
      return;
    }

    _unobstructedVisibleRange = ItemRange(start, end);
    _isModified = true;
    _didReportUnobstructedVisibleChildren = true;
  }

  ItemRange? get visibleRange => _visibleRange;
  ItemRange? _visibleRange;

  ItemRange? get unobstructedVisibleRange => _unobstructedVisibleRange;
  ItemRange? _unobstructedVisibleRange;

  int get numberOfItems => _extentList.length;

  int get numberOfItemsWithEstimatedExtent => _extentList.dirtyItemCount;

  void addItem(int index) {
    _extentList.insertAt(index, delegate.estimateExtentForItem);
    delegate.onMarkNeedsLayout();
  }

  void removeItem(int index) {
    _extentList.removeAt(index);
    delegate.onMarkNeedsLayout();
  }

  void invalidateExtent(int index) {
    _checkUnlocked();
    RangeError.checkValidIndex(index, _extentList, "index", numberOfItems);
    _invalidatedEstimates.add(index);
    _pendingEstimates.remove(index);
    delegate.onMarkNeedsLayout();
  }

  void invalidateAllExtents() {
    _checkUnlocked();
    markAllDirty();
    delegate.onMarkNeedsLayout();
  }

  bool get isLocked => _layoutInProgress;

  double getOffsetToReveal(
    int index,
    double alignment, {
    Rect? rect,
    required bool estimationOnly,
    Object? owner,
  }) {
    if (!estimationOnly) {
      if (owner == null) {
        beginReveal();
      } else if (!identical(owner, revealOwner)) {
        return double.nan;
      }
    }
    return delegate.getOffsetToReveal(
      index,
      alignment,
      rect: rect,
      estimationOnly: estimationOnly,
    );
  }

  @override
  String toString() {
    return "ExtentManager ${identityHashCode(this).toRadixString(16)}";
  }
}

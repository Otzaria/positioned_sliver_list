import "dart:ui";

import "package:flutter/foundation.dart";

import "extent_list.dart";

abstract class ExtentManagerDelegate {
  const ExtentManagerDelegate();

  void onMarkNeedsLayout();
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

class ExtentManager with ChangeNotifier {
  ExtentManager({required this.delegate});

  double _beforeCorrection = 0.0;
  double _afterCorrection = 0.0;

  final ExtentManagerDelegate delegate;

  double get correctionPercentage {
    if (_beforeCorrection.abs() < precisionErrorTolerance) {
      return 1.0;
    }
    return _afterCorrection / _beforeCorrection;
  }

  void setExtent(int index, double extent, {bool isEstimation = false}) {
    final oldExtent = _extentList[index];
    final extentChanged = oldExtent != extent;
    bool wasDirty = false;

    if (!extentChanged && !isEstimation && !_isModified) {
      wasDirty = _extentList.isDirty(index);
    }

    if (!isEstimation) {
      _beforeCorrection += oldExtent;
      _afterCorrection += extent;
    }

    _extentList.setExtent(index, extent, isEstimation: isEstimation);

    if (!_isModified) {
      if (extentChanged) {
        _isModified = true;
      } else if (!isEstimation && wasDirty) {
        _isModified = true;
      }
    }
  }

  void markAllDirty() {
    _afterCorrection = 0.0;
    _beforeCorrection = 0.0;
    _isModified = true;
    _extentList.markAllDirty();
  }

  bool get hasDirtyItems => _extentList.hasDirtyItems;

  double get totalExtent => _extentList.totalExtent;

  int? get cleanRangeStart => _extentList.cleanRangeStart;
  int? get cleanRangeEnd => _extentList.cleanRangeEnd;

  @pragma("vm:prefer-inline")
  double getExtent(int index) => _extentList[index];

  void resize(
    int newSize,
  ) {
    if (newSize == _extentList.length) {
      return;
    }
    _isModified = true;
    _extentList.resize(newSize, delegate.estimateExtentForItem);
  }

  final _extentList = ExtentList();

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
      if (_isModified) {
        notifyListeners();
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
    _extentList.markDirty(index);
    delegate.onMarkNeedsLayout();
  }

  void invalidateAllExtents() {
    _extentList.markAllDirty();
    delegate.onMarkNeedsLayout();
  }

  bool get isLocked => _layoutInProgress;

  double getOffsetToReveal(
    int index,
    double alignment, {
    Rect? rect,
    required bool estimationOnly,
  }) {
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

// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// Modifications Copyright 2026 The Otzaria contributors.

import "dart:async";
import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";

import "../animate_to_item.dart";
import "../item_position.dart";
import "../super_sliver_list.dart";

/// Estimates the main axis extent of the item at [index] before it is laid
/// out, for a list whose cross axis extent is [crossAxisExtent]. Called for
/// every item that has not been measured yet, so it must be cheap.
typedef ItemExtentEstimator =
    double Function(int index, double crossAxisExtent);

const double _defaultCacheExtentScreens = 2;
const double _defaultItemExtentEstimate = 100.0;

enum _PageStorageSlot { anchor }

/// A scrollable list that can jump or animate to an item by index and reports
/// which items are visible, with the API of `scrollable_positioned_list`.
///
/// It is a single [CustomScrollView] around a [SuperSliverList]: the list has
/// a real [ScrollController] (so a [Scrollbar] works), jumps are resolved
/// exactly during layout before paint, and only the items around a target are
/// built.
class ScrollablePositionedList extends StatefulWidget {
  /// Same as [ScrollablePositionedList.builder].
  const ScrollablePositionedList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    this.itemScrollController,
    this.shrinkWrap = false,
    this.itemPositionsListener,
    this.scrollOffsetController,
    this.scrollOffsetListener,
    this.initialScrollIndex = 0,
    this.initialAlignment = 0,
    this.initialOffset = 0,
    this.initialTargetRectResolver,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.semanticChildCount,
    this.padding,
    this.addSemanticIndexes = true,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.minCacheExtent,
    this.cacheExtentScreens = _defaultCacheExtentScreens,
    this.jumpToDistantItems = false,
    this.scrollController,
    this.listController,
    this.estimateExtent,
    this.estimationKey,
    this.restorePosition = false,
    this.overscrollToTarget = OverscrollToTarget.matchScrollablePositionedList,
  }) : assert(cacheExtentScreens >= 0),
       separatorBuilder = null,
       estimatedSeparatorExtent = 0;

  /// Creates a list whose items are built by [itemBuilder].
  const ScrollablePositionedList.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    this.itemScrollController,
    this.shrinkWrap = false,
    this.itemPositionsListener,
    this.scrollOffsetController,
    this.scrollOffsetListener,
    this.initialScrollIndex = 0,
    this.initialAlignment = 0,
    this.initialOffset = 0,
    this.initialTargetRectResolver,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.semanticChildCount,
    this.padding,
    this.addSemanticIndexes = true,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.minCacheExtent,
    this.cacheExtentScreens = _defaultCacheExtentScreens,
    this.jumpToDistantItems = false,
    this.scrollController,
    this.listController,
    this.estimateExtent,
    this.estimationKey,
    this.restorePosition = false,
    this.overscrollToTarget = OverscrollToTarget.matchScrollablePositionedList,
  }) : assert(cacheExtentScreens >= 0),
       separatorBuilder = null,
       estimatedSeparatorExtent = 0;

  /// Creates a list whose items are built by [itemBuilder], with a separator
  /// built by [separatorBuilder] between consecutive items.
  const ScrollablePositionedList.separated({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    required IndexedWidgetBuilder this.separatorBuilder,
    this.itemScrollController,
    this.shrinkWrap = false,
    this.itemPositionsListener,
    this.scrollOffsetController,
    this.scrollOffsetListener,
    this.initialScrollIndex = 0,
    this.initialAlignment = 0,
    this.initialOffset = 0,
    this.initialTargetRectResolver,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.semanticChildCount,
    this.padding,
    this.addSemanticIndexes = true,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.minCacheExtent,
    this.cacheExtentScreens = _defaultCacheExtentScreens,
    this.jumpToDistantItems = false,
    this.scrollController,
    this.listController,
    this.estimateExtent,
    this.estimationKey,
    this.estimatedSeparatorExtent = 0,
    this.restorePosition = false,
    this.overscrollToTarget = OverscrollToTarget.matchScrollablePositionedList,
  }) : assert(cacheExtentScreens >= 0);

  /// Number of items [itemBuilder] can build.
  final int itemCount;

  /// Builds the item at `0 <= index < itemCount`.
  final IndexedWidgetBuilder itemBuilder;

  /// מאתר את האינדקס החדש של פריט לפי מפתחו ושומר את מצבו בסידור מחדש.
  /// גם ברשימה מופרדת מחזירים אינדקס פריט, ללא המפרידים שביניהם.
  final ChildIndexGetter? findChildIndexCallback;

  /// Builds the separator after the item at `0 <= index < itemCount - 1`.
  final IndexedWidgetBuilder? separatorBuilder;

  /// Jumps or scrolls to items.
  final ItemScrollController? itemScrollController;

  /// Receives the positions of the visible items after every frame in which
  /// they changed.
  final ItemPositionsListener? itemPositionsListener;

  /// Scrolls by a number of pixels.
  final ScrollOffsetController? scrollOffsetController;

  /// Receives scroll offset changes.
  final ScrollOffsetListener? scrollOffsetListener;

  /// Index of the item shown first, placed at [initialAlignment].
  final int initialScrollIndex;

  /// Fraction of the viewport where the leading edge of the item at
  /// [initialScrollIndex] is placed. See [ItemScrollController.jumpTo].
  final double initialAlignment;

  /// Pixels added to [initialAlignment].
  final double initialOffset;

  /// מיישר אזור בתוך הפריט לפני הציור הראשון, לפי חוזה [ItemScrollController.jumpTo].
  /// שחזור מ־PageStorage מקבל קדימות על פני היעד ההתחלתי הזה.
  final TargetRectResolver? initialTargetRectResolver;

  /// See [ScrollView.scrollDirection].
  final Axis scrollDirection;

  /// See [ScrollView.reverse].
  final bool reverse;

  /// See [ScrollView.shrinkWrap].
  final bool shrinkWrap;

  /// See [ScrollView.physics].
  final ScrollPhysics? physics;

  /// See [ScrollView.semanticChildCount]. Defaults to [itemCount].
  final int? semanticChildCount;

  /// Space around the items.
  final EdgeInsets? padding;

  /// See [SliverChildBuilderDelegate.addSemanticIndexes].
  final bool addSemanticIndexes;

  /// See [SliverChildBuilderDelegate.addAutomaticKeepAlives].
  final bool addAutomaticKeepAlives;

  /// See [SliverChildBuilderDelegate.addRepaintBoundaries].
  final bool addRepaintBoundaries;

  /// Lower bound for the cache extent in pixels.
  final double? minCacheExtent;

  /// Cache extent before and after the viewport, in viewport lengths.
  final double cacheExtentScreens;

  /// Accepted for compatibility and ignored: distant items are always reached
  /// by a jump to near the item followed by a short animation.
  final bool jumpToDistantItems;

  /// Scroll controller of the list. When null the list creates one, which is
  /// available as [ItemScrollController.scrollController].
  ///
  /// Pass one to drive a [Scrollbar] or to listen to scroll metrics.
  final ScrollController? scrollController;

  /// בקר ליבת הרשימה; בקרה על מחזור חייו נשארת בידי מי שסיפק אותו.
  /// בלעדיו הרשימה יוצרת בקר פנימי ומשחררת אותו בפירוקה.
  final ListController? listController;

  /// Estimates item extents before they are laid out. Good estimates make the
  /// scrollbar steadier; jumps are exact either way.
  /// החלפת ה-callback אינה מרעננת הערכות: לשינוי הנתונים עדכנו [estimationKey].
  final ItemExtentEstimator? estimateExtent;

  /// שינוי המפתח מרענן הערכות שטרם נמדדו, בלי לאבד מדידות קיימות.
  /// רוחב חדש ורענון מפורש של [ListController] מרעננים אותן גם בלעדיו.
  final Object? estimationKey;

  /// Estimated extent of a separator in a [ScrollablePositionedList.separated]
  /// list.
  final double estimatedSeparatorExtent;

  /// Whether the visible item is saved to [PageStorage] and restored when the
  /// list is recreated. Off by default; [initialScrollIndex] is used then.
  final bool restorePosition;

  /// Whether [ItemScrollController.jumpTo], [ItemScrollController.scrollTo]
  /// and the initial position may leave blank space where the content does
  /// not reach. The default reproduces `scrollable_positioned_list`;
  /// [OverscrollToTarget.always] lets every target land exactly, for example
  /// the last item at the top of the viewport.
  final OverscrollToTarget overscrollToTarget;

  bool get _separated => separatorBuilder != null;

  @override
  State<ScrollablePositionedList> createState() =>
      _ScrollablePositionedListState();
}

/// Jumps or scrolls a [ScrollablePositionedList] to an item.
///
/// A controller can be attached to one list at a time; when it is briefly
/// attached to two (for example during a route transition), the newest wins.
class ItemScrollController {
  final _clients = <_ScrollablePositionedListState>[];

  _ScrollablePositionedListState? get _client =>
      _clients.isEmpty ? null : _clients.last;

  /// Whether a list is attached. [jumpTo] and [scrollTo] require it.
  bool get isAttached => _clients.isNotEmpty;

  /// The scroll controller of the attached list.
  ScrollController? get scrollController => _client?._scrollController;

  /// The [ListController] of the attached list's [SuperSliverList]. Its
  /// indices are child indices, which differ from item indices in a separated
  /// list.
  ListController? get listController => _client?._listController;

  /// מחזיר אינדקס פריט לפי היסט הפיקסלים של הרשימה, או null מחוץ לתוכן.
  /// היסט שבתוך מפריד ממופה לפריט שלפניו.
  int? indexForScrollOffset(double pixels) {
    final client = _client;
    if (client == null || !client._listController.isAttached) return null;
    final index = client._listController.indexForScrollOffset(pixels);
    return index == null ? null : client._itemIndex(index);
  }

  /// מעדכן הערכות לפי אינדקסי פריטים ומשלים לאחר הפריסה שמיישמת את האצווה.
  /// ברשימה מופרדת גובהי המפרידים נשארים ללא שינוי.
  Future<void> updateEstimatedExtents(Map<int, double> extents) {
    assert(isAttached, "ItemScrollController is not attached.");
    final client = _client!;
    return client._listController.updateEstimatedExtents({
      for (final entry in extents.entries)
        client._childIndex(entry.key): entry.value,
    });
  }

  /// הפריט הראשון שנראה והמרחק מקצהו לתחילת התצוגה.
  /// [restoreAnchor] משחזר אותו, כולל ריפוד שנראה לפני הפריט הראשון.
  ListAnchor? get anchor => _client?._anchor;

  /// Places the leading edge of the item at [index] at [alignment] of the
  /// viewport plus [offset] pixels, before the next paint.
  ///
  /// [alignment] is a fraction of the viewport's main axis: 0 is the leading
  /// edge (the top of a vertical list, the bottom when reversed), 0.5 the
  /// center, 1 the trailing edge. Values outside 0..1 are allowed. The
  /// resulting position is clamped to the scroll range, so the last items
  /// cannot be moved to the top of the viewport.
  /// [targetRectResolver] מיישר אזור בתוך הפריט; האינדקס שהוא מקבל הוא
  /// אינדקס פריט גם ברשימה מופרדת. עצם אספקתו מבטלת הוספת ריפוד לפריט 0,
  /// גם כשהוא מחזיר null, כך ש-[offset] נשאר היסט מדויק מהתצוגה.
  void jumpTo({
    required int index,
    double alignment = 0,
    double offset = 0,
    TargetRectResolver? targetRectResolver,
  }) {
    assert(isAttached, "ItemScrollController is not attached.");
    unawaited(
      jumpToAsync(
        index: index,
        alignment: alignment,
        offset: offset,
        targetRectResolver: targetRectResolver,
      ),
    );
  }

  /// כמו [jumpTo], ומשלים אחרי הפריסה שמיישמת את הקפיצה או ביטולה.
  Future<void> jumpToAsync({
    required int index,
    double alignment = 0,
    double offset = 0,
    TargetRectResolver? targetRectResolver,
  }) {
    assert(isAttached, "ItemScrollController is not attached.");
    return _client!._jumpTo(
      index: index,
      alignment: alignment,
      offset: offset,
      targetRectResolver: targetRectResolver,
    );
  }

  /// משחזר עוגן בלי להוסיף את הריפוד של [jumpTo] לפריט הראשון.
  void restoreAnchor(ListAnchor anchor) {
    unawaited(restoreAnchorAsync(anchor));
  }

  /// כמו [restoreAnchor], ומשלים אחרי הפריסה שמיישמת את השחזור או ביטולו.
  Future<void> restoreAnchorAsync(ListAnchor anchor) {
    assert(isAttached, "ItemScrollController is not attached.");
    return _client!._jumpTo(
      index: anchor.index,
      alignment: 0,
      offset: -anchor.offsetInItem,
      includeLeadingPadding: false,
    );
  }

  /// Animates until the item at [index] is at [alignment]; see [jumpTo].
  ///
  /// A distant item is first jumped to about one viewport away, so long
  /// scrolls take [duration] without building the items in between. User
  /// input stops the animation. The future completes when the list has landed
  /// or the animation was interrupted.
  ///
  /// [opacityAnimationWeights] is accepted for compatibility and ignored.
  Future<void> scrollTo({
    required int index,
    double alignment = 0,
    double offset = 0,
    required Duration duration,
    Curve curve = Curves.linear,
    List<double> opacityAnimationWeights = const [40, 20, 40],
    TargetRectResolver? targetRectResolver,
  }) {
    assert(isAttached, "ItemScrollController is not attached.");
    return _client!._scrollTo(
      index: index,
      alignment: alignment,
      offset: offset,
      duration: duration,
      curve: curve,
      targetRectResolver: targetRectResolver,
    );
  }

  void _attach(_ScrollablePositionedListState client) {
    _clients
      ..remove(client)
      ..add(client);
  }

  void _detach(_ScrollablePositionedListState client) {
    _clients.remove(client);
  }
}

/// Scrolls a [ScrollablePositionedList] by a number of pixels.
class ScrollOffsetController {
  final _clients = <_ScrollablePositionedListState>[];

  _ScrollablePositionedListState? get _client =>
      _clients.isEmpty ? null : _clients.last;

  /// Whether a list is attached.
  bool get isAttached => _clients.isNotEmpty;

  /// Animates the scroll offset by [offset] pixels (negative scrolls back).
  Future<void> animateScroll({
    required double offset,
    required Duration duration,
    Curve curve = Curves.linear,
  }) {
    assert(isAttached, "ScrollOffsetController is not attached.");
    return _client!._animateScroll(offset, duration, curve);
  }

  /// Moves the scroll offset by [offset] pixels without animation.
  void jumpBy(double offset) {
    assert(isAttached, "ScrollOffsetController is not attached.");
    _client!._jumpBy(offset);
  }

  void _attach(_ScrollablePositionedListState client) {
    _clients
      ..remove(client)
      ..add(client);
  }

  void _detach(_ScrollablePositionedListState client) {
    _clients.remove(client);
  }
}

/// Reports the positions of the visible items of a [ScrollablePositionedList].
abstract class ItemPositionsListener {
  /// Creates a listener to pass to [ScrollablePositionedList].
  factory ItemPositionsListener.create() => _ItemPositionsNotifier();

  /// Positions of the items that are at least partially visible.
  ValueListenable<Iterable<ItemPosition>> get itemPositions;
}

class _ItemPositionsNotifier implements ItemPositionsListener {
  @override
  final ValueNotifier<Iterable<ItemPosition>> itemPositions =
      ValueNotifier<Iterable<ItemPosition>>(const []);
}

/// Reports scroll offset changes of a [ScrollablePositionedList].
abstract class ScrollOffsetListener {
  /// Creates a listener to pass to [ScrollablePositionedList].
  ///
  /// With [recordProgrammaticScrolls] false, changes made by
  /// [ItemScrollController] and [ScrollOffsetController] are not reported.
  factory ScrollOffsetListener.create({
    bool recordProgrammaticScrolls = true,
  }) => _ScrollOffsetNotifier(
    recordProgrammaticScrolls: recordProgrammaticScrolls,
  );

  /// Stream of scroll offset deltas in pixels.
  Stream<double> get changes;
}

class _ScrollOffsetNotifier implements ScrollOffsetListener {
  _ScrollOffsetNotifier({required this.recordProgrammaticScrolls});

  final bool recordProgrammaticScrolls;
  final _controller = StreamController<double>();

  @override
  Stream<double> get changes => _controller.stream;
}

class _ScrollablePositionedListState extends State<ScrollablePositionedList> {
  ListController? _ownListController;
  ScrollController? _ownScrollController;
  late int _initialIndex;
  late double _initialAlignment;
  late double _initialOffset;
  (int, double)? _restoredPosition;
  Object? _storageIdentifier;
  int _programmaticOperations = 0;
  AnimationHandle? _itemAnimation;
  TargetScrollAnimation? _offsetAnimation;
  List<ItemPosition> _lastPositions = const [];

  ListController get _listController =>
      widget.listController ?? (_ownListController ??= ListController());

  ScrollController get _scrollController =>
      widget.scrollController ??
      (_ownScrollController ??= ScrollController(keepScrollOffset: false));

  int _childIndex(int itemIndex) =>
      widget._separated ? itemIndex * 2 : itemIndex;

  int _itemIndex(int childIndex) =>
      widget._separated ? childIndex ~/ 2 : childIndex;

  int get _childCount => widget._separated
      ? math.max(0, widget.itemCount * 2 - 1)
      : widget.itemCount;

  double get _leadingPadding {
    final padding = widget.padding;
    if (padding == null) {
      return 0;
    }
    if (widget.scrollDirection == Axis.vertical) {
      return widget.reverse ? padding.bottom : padding.top;
    }
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return (widget.reverse != rtl) ? padding.right : padding.left;
  }

  // The first item keeps the leading padding in view, as in the original.
  double _itemOffset(int itemIndex, double offset) =>
      itemIndex == 0 ? offset + _leadingPadding : offset;

  Object? _computeStorageIdentifier() {
    Object? keys;
    bool collect(BuildContext node) {
      final key = node.widget.key;
      if (key is PageStorageKey) keys = (keys, key);
      return node.widget is! PageStorage;
    }

    if (collect(context)) context.visitAncestorElements(collect);
    return keys == null ? null : (_PageStorageSlot.anchor, keys);
  }

  @override
  void initState() {
    super.initState();
    _storageIdentifier = _computeStorageIdentifier();
    _initialIndex = widget.initialScrollIndex;
    _initialAlignment = widget.initialAlignment;
    _initialOffset = widget.initialOffset;
    if (widget.restorePosition) {
      final identifier = _storageIdentifier;
      final saved = identifier == null
          ? null
          : PageStorage.maybeOf(
              context,
            )?.readState(context, identifier: identifier);
      if (saved is (int, double)) {
        _restoredPosition = saved;
        _initialIndex = saved.$1;
        _initialAlignment = 0;
        _initialOffset = -saved.$2;
      }
    }
    if (widget.itemCount > 0) {
      _initialIndex = _initialIndex.clamp(0, widget.itemCount - 1);
    } else {
      _initialIndex = 0;
    }
    widget.itemScrollController?._attach(this);
    widget.scrollOffsetController?._attach(this);
    _syncPositionsListener();
  }

  @override
  void activate() {
    super.activate();
    _storageIdentifier = _computeStorageIdentifier();
    widget.itemScrollController?._attach(this);
    widget.scrollOffsetController?._attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storageIdentifier = _computeStorageIdentifier();
  }

  @override
  void deactivate() {
    widget.itemScrollController?._detach(this);
    widget.scrollOffsetController?._detach(this);
    super.deactivate();
  }

  @override
  void didUpdateWidget(ScrollablePositionedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listController != widget.listController) {
      _cancelAnimations();
      _lastPositions = const [];
    }
    _syncPositionsListener();
    if (oldWidget.listController != widget.listController &&
        widget.listController != null) {
      _ownListController?.dispose();
      _ownListController = null;
    }
    if (oldWidget.itemScrollController != widget.itemScrollController) {
      oldWidget.itemScrollController?._detach(this);
      widget.itemScrollController?._attach(this);
    }
    if (oldWidget.scrollOffsetController != widget.scrollOffsetController) {
      oldWidget.scrollOffsetController?._detach(this);
      widget.scrollOffsetController?._attach(this);
    }
    if (oldWidget.scrollController != widget.scrollController &&
        widget.scrollController != null) {
      _ownScrollController?.dispose();
      _ownScrollController = null;
    }
    // Listeners are told about a rebuild even when nothing moved.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _listeningToPositions) {
        _updatePositions(force: true);
      }
    });
  }

  @override
  void dispose() {
    _itemAnimation?.cancel();
    _offsetAnimation?.cancel();
    _positionsController?.itemPositions.removeListener(_updatePositions);
    _ownScrollController?.dispose();
    _ownListController?.dispose();
    super.dispose();
  }

  ListController? _positionsController;

  bool get _listeningToPositions => _positionsController != null;

  // Positions are computed after every layout only while someone needs them.
  void _syncPositionsListener() {
    final needed =
        widget.itemPositionsListener != null || widget.restorePosition;
    final controller = needed ? _listController : null;
    if (identical(controller, _positionsController)) return;
    _positionsController?.itemPositions.removeListener(_updatePositions);
    _positionsController = controller;
    controller?.itemPositions.addListener(_updatePositions);
  }

  /// Runs [start] and counts it as programmatic scrolling until it is done.
  Future<T> _programmatic<T>(Future<T> Function() start) {
    ++_programmaticOperations;
    final Future<T> operation;
    try {
      operation = start();
    } catch (_) {
      --_programmaticOperations;
      rethrow;
    }
    return operation.whenComplete(() => --_programmaticOperations);
  }

  // Layout corrections (anchoring, exact landing) do not send scroll
  // notifications, so only real scrolling is reported.
  bool _onScrollUpdate(ScrollUpdateNotification notification) {
    final listener = widget.scrollOffsetListener;
    final delta = notification.scrollDelta;
    if (notification.depth != 0 ||
        listener is! _ScrollOffsetNotifier ||
        delta == null ||
        delta == 0) {
      return false;
    }
    if (_programmaticOperations > 0 && !listener.recordProgrammaticScrolls) {
      return false;
    }
    if (!listener._controller.isClosed) {
      listener._controller.add(delta);
    }
    return false;
  }

  void _updatePositions({bool force = false}) {
    final controller = _scrollController;
    if (!controller.hasClients) {
      return;
    }
    final viewport = controller.position.viewportDimension;
    if (viewport <= 0) {
      return;
    }
    // A forced update reads the current layout: the published value may
    // predate it, and a stale one would overwrite fresher positions.
    final current = force
        ? _listController.computeItemPositions()
        : _listController.itemPositions.value;
    if (current == null) {
      return;
    }
    final separated = widget._separated;
    final positions = <ItemPosition>[];
    for (final position in current) {
      var index = position.index;
      if (separated) {
        if (index.isOdd) {
          continue;
        }
        index ~/= 2;
      }
      // Whole pixels, as in the original; sub-pixel scrolling then does not
      // notify on every frame.
      final leading = (position.itemLeadingEdge * viewport).round() / viewport;
      final trailing =
          (position.itemTrailingEdge * viewport).round() / viewport;
      if (leading >= 1 || trailing <= 0) {
        continue;
      }
      positions.add(
        ItemPosition(
          index: index,
          itemLeadingEdge: leading,
          itemTrailingEdge: trailing,
        ),
      );
    }
    if (!force && listEquals(positions, _lastPositions)) {
      return;
    }
    _lastPositions = positions;
    if (widget.restorePosition) {
      final anchor = _anchor;
      final identifier = _storageIdentifier;
      if (anchor != null && identifier != null) {
        PageStorage.maybeOf(context)?.writeState(context, (
          anchor.index,
          anchor.offsetInItem,
        ), identifier: identifier);
      }
    }
    final listener = widget.itemPositionsListener;
    if (listener is _ItemPositionsNotifier) {
      listener.itemPositions.value = List.unmodifiable(positions);
    }
  }

  ListAnchor? get _anchor {
    final anchor = _listController.isAttached ? _listController.anchor : null;
    if (anchor == null || !widget._separated) {
      return anchor == null ? null : _withVisiblePadding(anchor);
    }
    if (anchor.index.isEven) {
      return _withVisiblePadding(
        ListAnchor(
          index: anchor.index ~/ 2,
          offsetInItem: anchor.offsetInItem,
          itemExtent: anchor.itemExtent,
        ),
      );
    }
    // A separator: anchor to the item before it.
    final itemIndex = anchor.index ~/ 2;
    final (extent, _) = _listController.extentForIndex(anchor.index - 1);
    return _withVisiblePadding(
      ListAnchor(
        index: itemIndex,
        offsetInItem: anchor.offsetInItem + extent,
        itemExtent: extent,
      ),
    );
  }

  ListAnchor _withVisiblePadding(ListAnchor anchor) {
    if (anchor.index != 0 || !_scrollController.hasClients) return anchor;
    final padding = math.max(
      0.0,
      _leadingPadding - _scrollController.position.pixels,
    );
    if (padding == 0) return anchor;
    return ListAnchor(
      index: anchor.index,
      offsetInItem: anchor.offsetInItem - padding,
      itemExtent: anchor.itemExtent,
    );
  }

  int? _clampIndex(int index) {
    if (widget.itemCount == 0) {
      return null;
    }
    return index.clamp(0, widget.itemCount - 1);
  }

  void _cancelAnimations() {
    _itemAnimation?.cancel();
    _itemAnimation = null;
    _offsetAnimation?.cancel();
    _offsetAnimation = null;
  }

  Future<void> _jumpTo({
    required int index,
    required double alignment,
    required double offset,
    bool includeLeadingPadding = true,
    TargetRectResolver? targetRectResolver,
  }) {
    final itemIndex = _clampIndex(index);
    if (itemIndex == null || !_listController.isAttached) {
      return Future<void>.value();
    }
    _cancelAnimations();
    return _programmatic(
      () => _listController.jumpToIndex(
        _childIndex(itemIndex),
        alignment: alignment,
        offset: includeLeadingPadding && targetRectResolver == null
            ? _itemOffset(itemIndex, offset)
            : offset,
        targetRectResolver: _targetRectResolver(targetRectResolver),
      ),
    );
  }

  Future<void> _scrollTo({
    required int index,
    required double alignment,
    required double offset,
    required Duration duration,
    required Curve curve,
    TargetRectResolver? targetRectResolver,
  }) {
    final itemIndex = _clampIndex(index);
    if (itemIndex == null || !_listController.isAttached) {
      return Future<void>.value();
    }
    _cancelAnimations();
    return _programmatic<void>(() {
      final handle = _listController.scrollToIndex(
        _childIndex(itemIndex),
        alignment: alignment,
        offset: targetRectResolver == null
            ? _itemOffset(itemIndex, offset)
            : offset,
        duration: duration,
        curve: curve,
        targetRectResolver: _targetRectResolver(targetRectResolver),
      );
      _itemAnimation = handle;
      return handle;
    });
  }

  TargetRectResolver? _targetRectResolver(TargetRectResolver? resolver) {
    if (resolver == null || !widget._separated) return resolver;
    return (index, child) => resolver(_itemIndex(index), child);
  }

  Future<void> _animateScroll(double offset, Duration duration, Curve curve) {
    final controller = _scrollController;
    if (!controller.hasClients) {
      return Future<void>.value();
    }
    _cancelAnimations();
    final position = controller.position;
    final start = position.pixels;
    return _programmatic(() {
      TargetScrollAnimation? animation;
      animation = TargetScrollAnimation.start(
        position: position,
        target: () => start + offset + (animation?.drift ?? 0.0),
        duration: duration,
        curve: curve,
        farDistance: double.infinity,
      );
      _offsetAnimation = animation;
      return animation.done;
    });
  }

  void _jumpBy(double offset) {
    final controller = _scrollController;
    if (!controller.hasClients) {
      return;
    }
    _cancelAnimations();
    final position = controller.position;
    ++_programmaticOperations;
    try {
      position.jumpTo(position.pixels + offset);
    } finally {
      --_programmaticOperations;
    }
  }

  double _estimate(int? childIndex, double crossAxisExtent) {
    final estimate = widget.estimateExtent;
    if (childIndex == null) {
      // A uniform estimate lets the list skip per-item calls.
      return estimate == null && !widget._separated
          ? _defaultItemExtentEstimate
          : 0;
    }
    if (widget._separated && childIndex.isOdd) {
      return widget.estimatedSeparatorExtent;
    }
    final itemIndex = widget._separated ? childIndex ~/ 2 : childIndex;
    return estimate?.call(itemIndex, crossAxisExtent) ??
        _defaultItemExtentEstimate;
  }

  int? _findChildIndex(Key key) {
    final itemIndex = widget.findChildIndexCallback!(key);
    return itemIndex == null ? null : _childIndex(itemIndex);
  }

  Widget? _buildChild(BuildContext context, int childIndex) {
    if (!widget._separated) {
      return widget.itemBuilder(context, childIndex);
    }
    final itemIndex = childIndex ~/ 2;
    return childIndex.isEven
        ? widget.itemBuilder(context, itemIndex)
        : widget.separatorBuilder!(context, itemIndex);
  }

  ScrollCacheExtent _cacheExtent(BoxConstraints constraints) {
    final minCacheExtent = widget.minCacheExtent;
    if (minCacheExtent == null) {
      return ScrollCacheExtent.viewport(widget.cacheExtentScreens);
    }
    final extent = widget.scrollDirection == Axis.vertical
        ? constraints.maxHeight
        : constraints.maxWidth;
    final screens = extent.isFinite ? extent * widget.cacheExtentScreens : 0.0;
    return ScrollCacheExtent.pixels(math.max(screens, minCacheExtent));
  }

  Widget _buildScrollView(ScrollCacheExtent cacheExtent) {
    final separated = widget._separated;
    final initialResolver = _restoredPosition == null
        ? _targetRectResolver(widget.initialTargetRectResolver)
        : null;
    final list = SuperSliverList(
      delegate: SliverChildBuilderDelegate(
        _buildChild,
        childCount: _childCount,
        findChildIndexCallback: widget.findChildIndexCallback == null
            ? null
            : _findChildIndex,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        addSemanticIndexes: widget.addSemanticIndexes,
        semanticIndexCallback: separated
            ? (_, index) => index.isEven ? index ~/ 2 : null
            : (_, index) => index,
      ),
      listController: _listController,
      extentEstimation: _estimate,
      estimationKey: (
        widget.estimationKey,
        widget._separated,
        widget.estimatedSeparatorExtent,
        widget.estimateExtent == null,
      ),
      initialIndex: _childIndex(_initialIndex),
      initialAlignment: _initialAlignment,
      initialOffset: _restoredPosition == null && initialResolver == null
          ? _itemOffset(_initialIndex, _initialOffset)
          : _initialOffset,
      initialTargetRectResolver: initialResolver,
      overscrollToTarget: widget.overscrollToTarget,
    );
    return Listener(
      onPointerDown: (_) => _cancelAnimations(),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: _onScrollUpdate,
        child: CustomScrollView(
          controller: _scrollController,
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          semanticChildCount: widget.semanticChildCount ?? widget.itemCount,
          scrollCacheExtent: cacheExtent,
          slivers: [
            SliverPadding(
              padding: widget.padding ?? EdgeInsets.zero,
              sliver: list,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.minCacheExtent == null) {
      return _buildScrollView(
        ScrollCacheExtent.viewport(widget.cacheExtentScreens),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildScrollView(_cacheExtent(constraints)),
    );
  }
}

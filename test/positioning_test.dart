import "dart:async";
import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

const _viewportHeight = 600.0;
const _width = 400.0;
const _itemCount = 50000;

/// Deterministic extents between 20 and 319 px, uncorrelated with the
/// estimate below.
double _extent(int index) => 20.0 + (index * 7919) % 300;

// Deliberately poor estimate: the real average is about 170.
double _badEstimate(int? index, double crossAxisExtent) => 50.0;

class _Harness {
  _Harness() {
    // Positions are only computed while someone listens.
    listController.itemPositions.addListener(() {});
  }

  final listController = ListController();
  final scrollController = ScrollController();
  final built = <int>[];

  void dispose() {
    listController.dispose();
    scrollController.dispose();
  }

  Widget build({
    double width = _width,
    int itemCount = _itemCount,
    double Function(int index, double width)? extent,
    int? initialIndex,
    double initialAlignment = 0,
    double initialOffset = 0,
    Axis axis = Axis.vertical,
    bool reverse = false,
    TextDirection textDirection = TextDirection.ltr,
    ExtentEstimationProvider estimate = _badEstimate,
  }) {
    final vertical = axis == Axis.vertical;
    return Directionality(
      textDirection: textDirection,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(800, 800)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: vertical ? width : _viewportHeight,
            height: vertical ? _viewportHeight : width,
            child: CustomScrollView(
              controller: scrollController,
              scrollDirection: axis,
              reverse: reverse,
              slivers: [
                SuperSliverList.builder(
                  listController: listController,
                  itemCount: itemCount,
                  extentEstimation: estimate,
                  initialIndex: initialIndex,
                  initialAlignment: initialAlignment,
                  initialOffset: initialOffset,
                  itemBuilder: (context, index) {
                    built.add(index);
                    final size = extent?.call(index, width) ?? _extent(index);
                    return SizedBox(
                      key: ValueKey(index),
                      height: vertical ? size : null,
                      width: vertical ? null : size,
                      child: Text("Item $index"),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Finder _item(int index) => find.byKey(ValueKey(index), skipOffstage: false);

/// Distance of the item's leading edge from the viewport's leading edge.
double _leading(
  WidgetTester tester,
  int index, {
  Axis axis = Axis.vertical,
  bool reverse = false,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final rect = tester.getRect(_item(index));
  if (axis == Axis.vertical) {
    return reverse ? _viewportHeight - rect.bottom : rect.top;
  }
  final fromRight = (textDirection == TextDirection.rtl) != reverse;
  return fromRight ? _viewportHeight - rect.right : rect.left;
}

/// Every reported position matches the rendered rect of its item, and every
/// visible item is reported.
void _expectPositionsMatchLayout(
  WidgetTester tester,
  List<ItemPosition> positions, {
  Axis axis = Axis.vertical,
  bool reverse = false,
  TextDirection textDirection = TextDirection.ltr,
}) {
  expect(positions, isNotEmpty);
  for (final p in positions) {
    final leading = _leading(
      tester,
      p.index,
      axis: axis,
      reverse: reverse,
      textDirection: textDirection,
    );
    final rect = tester.getRect(_item(p.index));
    final extent = axis == Axis.vertical ? rect.height : rect.width;
    expect(
      p.itemLeadingEdge * _viewportHeight,
      closeTo(leading, 0.01),
      reason: "leading edge of ${p.index}",
    );
    expect(
      p.itemTrailingEdge * _viewportHeight,
      closeTo(leading + extent, 0.01),
      reason: "trailing edge of ${p.index}",
    );
  }
  final indices = positions.map((p) => p.index).toList();
  for (var i = 1; i < indices.length; ++i) {
    expect(indices[i], indices[i - 1] + 1, reason: "positions are contiguous");
  }
  final first = indices.first;
  final last = indices.last;
  if (first > 0 && _item(first - 1).evaluate().isNotEmpty) {
    final leading = _leading(
      tester,
      first - 1,
      axis: axis,
      reverse: reverse,
      textDirection: textDirection,
    );
    final rect = tester.getRect(_item(first - 1));
    final extent = axis == Axis.vertical ? rect.height : rect.width;
    expect(leading + extent, lessThanOrEqualTo(0.01));
  }
  if (_item(last + 1).evaluate().isNotEmpty) {
    expect(
      _leading(
        tester,
        last + 1,
        axis: axis,
        reverse: reverse,
        textDirection: textDirection,
      ),
      greaterThanOrEqualTo(_viewportHeight - 0.01),
    );
  }
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group("jumpToIndex", () {
    testWidgets("lands exactly with bad estimates and builds only around it", (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      final random = math.Random(7);
      final cases = <(int, double, double)>[
        (25000, 0, 0),
        (49999, 0, 0),
        (12345, 0.5, 0),
        (40000, 1.0, 0),
        (777, -0.3, 0),
        (30000, 0.25, 17.5),
        (0, 0, 0),
        for (var i = 0; i < 20; ++i)
          (random.nextInt(_itemCount - 100), random.nextDouble(), 0.0),
      ];
      for (final (index, alignment, offset) in cases) {
        h.built.clear();
        unawaited(
          h.listController.jumpToIndex(
            index,
            alignment: alignment,
            offset: offset,
          ),
        );
        await tester.pump();
        final position = h.scrollController.position;
        final expected = alignment * _viewportHeight + offset;
        final atEnd = position.pixels >= position.maxScrollExtent - 0.01;
        if (!atEnd) {
          expect(
            _leading(tester, index),
            closeTo(expected, 0.01),
            reason: "index $index alignment $alignment offset $offset",
          );
        } else {
          final last = tester.getRect(_item(_itemCount - 1));
          expect(last.bottom, closeTo(_viewportHeight, 0.01));
        }
        // Visible items plus a cache area, never the items in between.
        expect(h.built.length, lessThan(40), reason: "built for $index");
        await tester.pump();
      }
    });

    testWidgets("future completes after the frame that lands", (tester) async {
      await tester.pumpWidget(h.build());
      var done = false;
      unawaited(h.listController.jumpToIndex(30000).then((_) => done = true));
      expect(done, isFalse);
      await tester.pump();
      expect(done, isTrue);
      expect(_leading(tester, 30000), closeTo(0, 0.01));
    });

    testWidgets("negative alignment places the item before the viewport edge", (
      tester,
    ) async {
      await tester.pumpWidget(h.build(extent: (index, width) => 100));
      unawaited(h.listController.jumpToIndex(500, alignment: -0.25));
      await tester.pump();
      expect(_leading(tester, 500), closeTo(-150, 0.01));
    });

    testWidgets("clamps to the scroll range near the end", (tester) async {
      await tester.pumpWidget(
        h.build(itemCount: 100, extent: (index, width) => 50),
      );
      unawaited(h.listController.jumpToIndex(99));
      await tester.pump();
      expect(tester.getRect(_item(99)).bottom, closeTo(_viewportHeight, 0.01));
      expect(
        h.scrollController.offset,
        h.scrollController.position.maxScrollExtent,
      );
    });
  });

  group("initial index", () {
    testWidgets("is applied before the first paint", (tester) async {
      await tester.pumpWidget(
        h.build(initialIndex: 20000, initialAlignment: 0.5, initialOffset: -10),
      );
      expect(_leading(tester, 20000), closeTo(290, 0.01));
      expect(h.built.where((i) => i < 19900), isEmpty);
      expect(h.built.length, lessThan(40));
    });

    testWidgets("is ignored after the first layout", (tester) async {
      await tester.pumpWidget(h.build(initialIndex: 100));
      await tester.pumpWidget(h.build(initialIndex: 200));
      expect(_leading(tester, 100), closeTo(0, 0.01));
    });
  });

  group("item positions", () {
    testWidgets("match the layout after jumps and scrolling", (tester) async {
      final updates = <List<ItemPosition>>[];
      h.listController.itemPositions.addListener(
        () => updates.add(h.listController.itemPositions.value),
      );
      await tester.pumpWidget(h.build());
      _expectPositionsMatchLayout(tester, h.listController.itemPositions.value);
      for (final index in [100, 40000, 3, 25001]) {
        unawaited(h.listController.jumpToIndex(index, alignment: 0.3));
        await tester.pump();
        _expectPositionsMatchLayout(
          tester,
          h.listController.itemPositions.value,
        );
      }
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pump();
      _expectPositionsMatchLayout(tester, h.listController.itemPositions.value);
      final count = updates.length;
      // A frame where nothing moved does not notify.
      await tester.pump();
      expect(updates.length, count);
    });

    testWidgets("reversed list measures from the bottom", (tester) async {
      await tester.pumpWidget(h.build(reverse: true));
      unawaited(h.listController.jumpToIndex(500, alignment: 0.2));
      await tester.pump();
      expect(_leading(tester, 500, reverse: true), closeTo(120, 0.01));
      _expectPositionsMatchLayout(
        tester,
        h.listController.itemPositions.value,
        reverse: true,
      );
    });

    testWidgets("horizontal RTL list measures from the right", (tester) async {
      await tester.pumpWidget(
        h.build(axis: Axis.horizontal, textDirection: TextDirection.rtl),
      );
      unawaited(h.listController.jumpToIndex(800, alignment: 0.1));
      await tester.pump();
      expect(
        _leading(
          tester,
          800,
          axis: Axis.horizontal,
          textDirection: TextDirection.rtl,
        ),
        closeTo(60, 0.01),
      );
      final rect = tester.getRect(_item(800));
      expect(rect.right, closeTo(_viewportHeight - 60, 0.01));
      _expectPositionsMatchLayout(
        tester,
        h.listController.itemPositions.value,
        axis: Axis.horizontal,
        textDirection: TextDirection.rtl,
      );
    });

    testWidgets("ItemPosition equality", (tester) async {
      const a = ItemPosition(index: 1, itemLeadingEdge: 0, itemTrailingEdge: 1);
      const b = ItemPosition(index: 1, itemLeadingEdge: 0, itemTrailingEdge: 1);
      const c = ItemPosition(index: 2, itemLeadingEdge: 0, itemTrailingEdge: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group("anchoring", () {
    // Items whose height depends on the width, like wrapped text.
    double reflowing(int index, double width) =>
        (20.0 + (index % 9) * 30) * _width / width;

    testWidgets("keeps the leading item and its fraction on width change", (
      tester,
    ) async {
      await tester.pumpWidget(h.build(extent: reflowing));
      unawaited(h.listController.jumpToIndex(10000, offset: -37));
      await tester.pump();
      final before = h.listController.anchor!;
      expect(before.index, 10000);
      expect(before.offsetInItem, closeTo(37, 0.01));
      for (final width in [300.0, 250.0, 520.0, 400.0]) {
        await tester.pumpWidget(h.build(width: width, extent: reflowing));
        final anchor = h.listController.anchor!;
        expect(anchor.index, 10000, reason: "width $width");
        expect(
          anchor.fraction,
          closeTo(before.fraction, 1e-6),
          reason: "width $width",
        );
        expect(
          _leading(tester, 10000),
          closeTo(-before.fraction * reflowing(10000, width), 0.01),
        );
      }
    });

    testWidgets("visible content stays when items above change extent", (
      tester,
    ) async {
      final grow = ValueNotifier<double>(0);
      addTearDown(grow.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<double>(
          valueListenable: grow,
          builder: (context, value, _) => h.build(
            extent: (index, width) =>
                index >= 4990 && index < 5000 ? 60 + value : 60,
          ),
        ),
      );
      unawaited(h.listController.jumpToIndex(5000, offset: -10));
      await tester.pump();
      // The cache area is filled one frame after a jump.
      await tester.pump();
      // Items above 5000 are in the cache area above the viewport.
      expect(_item(4999).evaluate(), isNotEmpty);
      final before = tester.getRect(_item(5003));
      for (final value in [40.0, -30.0, 100.0]) {
        grow.value = value;
        await tester.pump();
        expect(tester.getRect(_item(5003)), before, reason: "grow $value");
      }
    });

    testWidgets("measuring items while scrolling up does not move content", (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      unawaited(h.listController.jumpToIndex(20000));
      await tester.pump();
      for (var i = 0; i < 20; ++i) {
        final anchor = h.listController.anchor!;
        final top = _leading(tester, anchor.index);
        h.scrollController.jumpTo(h.scrollController.offset - 40);
        await tester.pump();
        // Items above were estimated at 50 px; measuring them must not
        // shift what is on screen beyond the 40 px scrolled.
        expect(_leading(tester, anchor.index), closeTo(top + 40, 0.01));
      }
    });
  });

  group("scrollToIndex", () {
    testWidgets("long scroll lands exactly and builds few items", (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      h.built.clear();
      var done = false;
      unawaited(
        h.listController
            .scrollToIndex(
              40000,
              alignment: 0.2,
              duration: const Duration(milliseconds: 500),
            )
            .then((_) => done = true),
      );
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(_leading(tester, 40000), closeTo(120, 0.01));
      expect(h.built.toSet().length, lessThan(120));
      expect(h.built.where((i) => i > 1000 && i < 39000), isEmpty);
    });

    testWidgets("never moves backwards on screen", (tester) async {
      await tester.pumpWidget(h.build());
      final firstVisible = <(int, double)>[];
      h.listController.itemPositions.addListener(() {
        final p = h.listController.itemPositions.value.first;
        firstVisible.add((p.index, p.itemLeadingEdge));
      });
      unawaited(
        h.listController.scrollToIndex(
          3000,
          duration: const Duration(milliseconds: 400),
        ),
      );
      // The first frame is the jump to about one viewport before the target.
      await tester.pump();
      await tester.pump();
      final start = firstVisible.length - 1;
      await tester.pumpAndSettle();
      for (var i = start + 1; i < firstVisible.length; ++i) {
        final (prevIndex, prevEdge) = firstVisible[i - 1];
        final (index, edge) = firstVisible[i];
        expect(
          index > prevIndex || (index == prevIndex && edge <= prevEdge),
          isTrue,
          reason:
              "frame $i moved backwards: "
              "${firstVisible[i - 1]} -> ${firstVisible[i]}",
        );
      }
      expect(_leading(tester, 3000), closeTo(0, 0.01));
    });

    testWidgets("drag cancels the animation and completes the future", (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      var done = false;
      final handle = h.listController.scrollToIndex(
        30000,
        duration: const Duration(seconds: 2),
      );
      unawaited(handle.then((_) => done = true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(handle.isAnimating, isTrue);
      final gesture = await tester.startGesture(const Offset(100, 300));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(handle.isAnimating, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(find.byKey(const ValueKey(30000)), findsNothing);
    });

    testWidgets("cancel stops in place", (tester) async {
      await tester.pumpWidget(h.build());
      final handle = h.listController.scrollToIndex(
        300,
        duration: const Duration(seconds: 1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      handle.cancel();
      final stopped = h.scrollController.offset;
      await tester.pumpAndSettle();
      expect(h.scrollController.offset, stopped);
      await handle;
    });

    testWidgets("a new jump replaces a running animation", (tester) async {
      await tester.pumpWidget(h.build());
      final handle = h.listController.scrollToIndex(
        300,
        duration: const Duration(seconds: 1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      unawaited(h.listController.jumpToIndex(9000));
      await tester.pumpAndSettle();
      expect(handle.isAnimating, isFalse);
      expect(_leading(tester, 9000), closeTo(0, 0.01));
    });

    testWidgets("animateToItem returns a future", (tester) async {
      await tester.pumpWidget(h.build());
      var done = false;
      unawaited(
        h.listController
            .animateToItem(
              index: () => 20000,
              scrollController: h.scrollController,
              alignment: 0,
              duration: (_) => const Duration(milliseconds: 300),
              curve: (_) => Curves.easeInOut,
            )
            .then((_) => done = true),
      );
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(_leading(tester, 20000), closeTo(0, 0.01));
    });
  });

  group("scroll controller", () {
    testWidgets("metrics stay sane with a scrollbar", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scrollbar(
            controller: h.scrollController,
            thumbVisibility: true,
            interactive: true,
            child: h.build(),
          ),
        ),
      );
      for (final index in [100, 49000, 25000, 0]) {
        unawaited(h.listController.jumpToIndex(index));
        await tester.pump();
        final position = h.scrollController.position;
        expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
        expect(position.maxScrollExtent, greaterThan(_itemCount * 20.0));
        expect(position.viewportDimension, _viewportHeight);
        expect(tester.takeException(), isNull);
      }
      // Moving the real controller moves the list consistently.
      final position = h.scrollController.position;
      h.scrollController.jumpTo(position.maxScrollExtent / 2);
      await tester.pump();
      expect(tester.takeException(), isNull);
      _expectPositionsMatchLayout(tester, h.listController.itemPositions.value);
    });
  });

  group("selection", () {
    // Selects by dragging a mouse from the middle of item 1002 to item 1006
    // (or back) and returns the selected text.
    Future<String?> select(
      WidgetTester tester, {
      required bool up,
      required bool superList,
    }) async {
      String? selected;
      final controller = ScrollController(initialScrollOffset: 40000);
      addTearDown(controller.dispose);
      Widget item(BuildContext context, int index) =>
          SizedBox(height: 40, child: Text("Item $index"));
      await tester.pumpWidget(
        MaterialApp(
          home: SelectionArea(
            onSelectionChanged: (content) => selected = content?.plainText,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _width,
                height: _viewportHeight,
                child: CustomScrollView(
                  controller: controller,
                  slivers: [
                    if (superList)
                      SuperSliverList.builder(
                        itemCount: 5000,
                        extentEstimation: (_, _) => 40,
                        itemBuilder: item,
                      )
                    else
                      SliverList.builder(itemCount: 5000, itemBuilder: item),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final from =
          tester.getTopLeft(find.text("Item 1002")) + const Offset(30, 8);
      final to =
          tester.getTopLeft(find.text("Item 1006")) + const Offset(30, 8);
      final gesture = await tester.startGesture(
        up ? to : from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(up ? from : to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await gesture.removePointer();
      return selected;
    }

    for (final up in [false, true]) {
      testWidgets("across items dragging ${up ? "up" : "down"} matches "
          "SliverList", (tester) async {
        final expected = await select(tester, up: up, superList: false);
        final actual = await select(tester, up: up, superList: true);
        expect(expected, isNotNull);
        expect(actual, expected);
      });
    }
  });
}

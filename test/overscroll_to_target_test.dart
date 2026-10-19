import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

const _viewport = 600.0;
const _count = 1000;

double _extent(int index, double width) =>
    (20.0 + (index * 7919) % 120) * 400 / width;

class _Harness {
  _Harness() {
    listController.itemPositions.addListener(() {});
  }

  final listController = ListController();
  final scrollController = ScrollController();
  final itemCount = ValueNotifier(_count);
  final width = ValueNotifier(400.0);

  void dispose() {
    listController.dispose();
    scrollController.dispose();
    itemCount.dispose();
    width.dispose();
  }

  ({double leading, double trailing}) get space =>
      listController.overscrollSpace;

  ScrollPosition get position => scrollController.position;

  Widget build({
    int? initialIndex,
    double initialAlignment = 0,
    bool scrollbar = false,
  }) {
    return MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: ListenableBuilder(
          listenable: Listenable.merge([itemCount, width]),
          builder: (context, _) {
            Widget list = CustomScrollView(
              controller: scrollController,
              slivers: [
                SuperSliverList.builder(
                  listController: listController,
                  itemCount: itemCount.value,
                  overscrollToTarget: OverscrollToTarget.always,
                  initialIndex: initialIndex,
                  initialAlignment: initialAlignment,
                  extentEstimation: (_, _) => 50,
                  itemBuilder: (context, index) => SizedBox(
                    key: ValueKey(index),
                    height: _extent(index, width.value),
                    child: Text("Item $index"),
                  ),
                ),
              ],
            );
            if (scrollbar) {
              list = Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: list,
              );
            }
            return SizedBox(width: width.value, height: _viewport, child: list);
          },
        ),
      ),
    );
  }
}

Finder _item(int index) => find.byKey(ValueKey(index), skipOffstage: false);

double _top(WidgetTester tester, int index) => tester.getRect(_item(index)).top;

void _expectPositionsMatchLayout(WidgetTester tester, ListController c) {
  final positions = c.itemPositions.value;
  expect(positions, isNotEmpty);
  for (final p in positions) {
    final rect = tester.getRect(_item(p.index));
    expect(p.itemLeadingEdge * _viewport, closeTo(rect.top, 0.01));
    expect(p.itemTrailingEdge * _viewport, closeTo(rect.bottom, 0.01));
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  testWidgets("last item at alignment 0 lands exactly", (tester) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(_count - 1));
    await tester.pump();
    expect(_top(tester, _count - 1), closeTo(0, 0.01));
    final extent = _extent(_count - 1, 400);
    expect(h.space.trailing, closeTo(_viewport - extent, 0.01));
    expect(h.space.leading, 0);
    expect(h.position.pixels, closeTo(h.position.maxScrollExtent, 0.01));
    _expectPositionsMatchLayout(tester, h.listController);
    // Stays there once settled.
    await tester.pumpAndSettle();
    expect(_top(tester, _count - 1), closeTo(0, 0.01));
  });

  testWidgets("item 0 at alignment 0.3 lands exactly", (tester) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(500));
    await tester.pump();
    unawaited(h.listController.jumpToIndex(0, alignment: 0.3));
    await tester.pump();
    expect(_top(tester, 0), closeTo(180, 0.01));
    expect(h.space.leading, closeTo(180, 0.01));
    expect(h.position.pixels, h.position.minScrollExtent);
    _expectPositionsMatchLayout(tester, h.listController);
    await tester.pumpAndSettle();
    expect(_top(tester, 0), closeTo(180, 0.01));
  });

  testWidgets("initial index may need leading space", (tester) async {
    await tester.pumpWidget(h.build(initialIndex: 1, initialAlignment: 0.5));
    expect(_top(tester, 1), closeTo(300, 0.01));
    expect(_top(tester, 0), closeTo(300 - _extent(0, 400), 0.01));
  });

  testWidgets("trailing space shrinks when dragging back and never regrows", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(_count - 1));
    await tester.pump();
    var previous = h.space.trailing;
    final gesture = await tester.startGesture(const Offset(100, 300));
    for (var i = 0; i < 20; ++i) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(h.space.trailing, lessThanOrEqualTo(previous + 1e-6));
      previous = h.space.trailing;
      expect(
        h.position.pixels,
        lessThanOrEqualTo(h.position.maxScrollExtent + 1e-6),
      );
      _expectPositionsMatchLayout(tester, h.listController);
    }
    expect(previous, 0);
    // Dragging towards the end again stops at the end of the content.
    for (var i = 0; i < 20; ++i) {
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(h.space.trailing, 0);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.space.trailing, 0);
    expect(tester.getRect(_item(_count - 1)).bottom, closeTo(_viewport, 0.01));
  });

  testWidgets("leading space shrinks when scrolling into the content", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(0, alignment: 0.5));
    await tester.pump();
    expect(h.space.leading, closeTo(300, 0.01));
    var previous = h.space.leading;
    var top = _top(tester, 0);
    final gesture = await tester.startGesture(const Offset(100, 300));
    for (var i = 0; i < 12; ++i) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(h.space.leading, lessThanOrEqualTo(previous + 1e-6));
      previous = h.space.leading;
      // The content follows the finger.
      expect(_top(tester, 0), lessThan(top));
      top = _top(tester, 0);
      _expectPositionsMatchLayout(tester, h.listController);
    }
    expect(previous, 0);
    // Dragging back does not bring the blank space back.
    for (var i = 0; i < 20; ++i) {
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(h.space.leading, 0);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_top(tester, 0), closeTo(0, 0.01));
  });

  testWidgets("a fling uses up the space and does not regrow it", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(_count - 1));
    await tester.pump();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 300),
      2000,
    );
    var previous = h.space.trailing;
    for (var i = 0; i < 60; ++i) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.space.trailing, lessThanOrEqualTo(previous + 1e-6));
      previous = h.space.trailing;
    }
    await tester.pumpAndSettle();
    expect(h.space.trailing, 0);
    // A fling towards the end stops at the end of the content.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      5000,
    );
    await tester.pumpAndSettle();
    expect(h.space.trailing, 0);
    expect(tester.getRect(_item(_count - 1)).bottom, closeTo(_viewport, 0.01));
  });

  testWidgets("appended items keep the target and use up the space", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(_count - 1));
    await tester.pump();
    final before = h.space.trailing;
    h.itemCount.value = _count + 3;
    await tester.pump();
    await tester.pump();
    expect(_top(tester, _count - 1), closeTo(0, 0.01));
    var appended = 0.0;
    for (var i = _count; i < _count + 3; ++i) {
      appended += _extent(i, 400);
    }
    expect(h.space.trailing, closeTo(before - appended, 0.01));
    h.itemCount.value = _count + 40;
    await tester.pump();
    await tester.pump();
    expect(_top(tester, _count - 1), closeTo(0, 0.01));
    expect(h.space.trailing, 0);
    _expectPositionsMatchLayout(tester, h.listController);
  });

  testWidgets("width change keeps the target in place", (tester) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(_count - 2, alignment: 0.2));
    await tester.pump();
    expect(_top(tester, _count - 2), closeTo(120, 0.01));
    for (final width in [300.0, 520.0, 400.0]) {
      h.width.value = width;
      await tester.pump();
      expect(_top(tester, _count - 2), closeTo(120, 0.01), reason: "$width");
      final rect = tester.getRect(_item(_count - 1));
      expect(
        h.space.trailing,
        closeTo(_viewport - rect.bottom, 0.01),
        reason: "only the space the viewport shows",
      );
      _expectPositionsMatchLayout(tester, h.listController);
    }

    unawaited(h.listController.jumpToIndex(1, alignment: 0.5));
    await tester.pump();
    expect(_top(tester, 1), closeTo(300, 0.01));
    for (final width in [300.0, 520.0]) {
      h.width.value = width;
      await tester.pump();
      expect(_top(tester, 1), closeTo(300, 0.01), reason: "$width");
      expect(_top(tester, 0), closeTo(300 - _extent(0, width), 0.01));
    }
  });

  testWidgets("scrollbar metrics include the space while it exists", (
    tester,
  ) async {
    await tester.pumpWidget(h.build(scrollbar: true));
    unawaited(h.listController.jumpToIndex(_count - 1));
    await tester.pump();
    final withSpace = h.position.maxScrollExtent;
    expect(h.position.pixels, closeTo(withSpace, 0.01));
    expect(h.position.extentAfter, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
    final gesture = await tester.startGesture(const Offset(100, 300));
    var previous = h.space.trailing;
    for (var i = 0; i < 25; ++i) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      // Measuring items above may change the total; the space only shrinks.
      expect(h.space.trailing, lessThanOrEqualTo(previous + 1e-6));
      previous = h.space.trailing;
      expect(
        h.position.pixels,
        inInclusiveRange(
          h.position.minScrollExtent,
          h.position.maxScrollExtent + 1e-6,
        ),
      );
      expect(
        h.position.maxScrollExtent,
        greaterThan(h.position.viewportDimension),
      );
      expect(tester.takeException(), isNull);
    }
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("scrollToIndex reaches a target that needs space", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    unawaited(h.listController.jumpToIndex(900));
    await tester.pump();
    var done = false;
    unawaited(
      h.listController
          .scrollToIndex(
            _count - 1,
            duration: const Duration(milliseconds: 300),
          )
          .then((_) => done = true),
    );
    final tops = <double>[];
    for (var i = 0; i < 40 && !done; ++i) {
      await tester.pump(const Duration(milliseconds: 16));
      if (_item(_count - 1).evaluate().isNotEmpty) {
        tops.add(_top(tester, _count - 1));
      }
    }
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(_top(tester, _count - 1), closeTo(0, 0.01));
    for (var i = 1; i < tops.length; ++i) {
      expect(
        tops[i],
        lessThanOrEqualTo(tops[i - 1] + 0.01),
        reason: "the target moves up monotonically",
      );
    }

    done = false;
    unawaited(
      h.listController
          .scrollToIndex(
            0,
            alignment: 0.4,
            duration: const Duration(milliseconds: 300),
          )
          .then((_) => done = true),
    );
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(_top(tester, 0), closeTo(240, 0.01));
  });

  testWidgets("disabled by default: positions are clamped", (tester) async {
    final controller = ListController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: _viewport,
            child: CustomScrollView(
              slivers: [
                SuperSliverList.builder(
                  listController: controller,
                  itemCount: _count,
                  itemBuilder: (context, index) => SizedBox(
                    key: ValueKey(index),
                    height: _extent(index, 400),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    unawaited(controller.jumpToIndex(_count - 1));
    await tester.pump();
    expect(tester.getRect(_item(_count - 1)).bottom, closeTo(_viewport, 0.01));
    expect(controller.overscrollSpace, (leading: 0.0, trailing: 0.0));
  });
}

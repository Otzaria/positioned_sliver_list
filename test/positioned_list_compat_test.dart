import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

const _viewport = 600.0;

double _extent(int index) => 20.0 + (index * 7919) % 300;

Widget _host(Widget child) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 400, height: _viewport, child: child),
  ),
);

Finder _text(String text) => find.text(text, skipOffstage: false);

void main() {
  testWidgets("separated list jumps to items, not to children", (tester) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    await tester.pumpWidget(
      _host(
        ScrollablePositionedList.separated(
          itemCount: 10000,
          itemScrollController: controller,
          itemPositionsListener: positions,
          itemBuilder: (context, index) =>
              SizedBox(height: _extent(index), child: Text("Item $index")),
          separatorBuilder: (context, index) =>
              SizedBox(height: 7, child: Text("Separator $index")),
          estimatedSeparatorExtent: 7,
        ),
      ),
    );
    controller.jumpTo(index: 5000, alignment: 0.5);
    await tester.pump();
    expect(tester.getTopLeft(_text("Item 5000")).dy, closeTo(300, 0.01));
    final reported = positions.itemPositions.value.toList();
    expect(reported.map((p) => p.index), contains(5000));
    final p = reported.firstWhere((p) => p.index == 5000);
    expect(p.itemLeadingEdge, 0.5);
    // Only items are reported, never separators.
    expect(reported.map((p) => p.index).toSet().length, reported.length);
    final anchor = controller.anchor!;
    expect(anchor.index, lessThan(5000));
  });

  testWidgets("the scroll controller is real and drives a scrollbar", (
    tester,
  ) async {
    final controller = ItemScrollController();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      _host(
        Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: ScrollablePositionedList.builder(
            itemCount: 50000,
            itemScrollController: controller,
            scrollController: scrollController,
            estimateExtent: (index, width) => 170,
            itemBuilder: (context, index) =>
                SizedBox(height: _extent(index), child: Text("Item $index")),
          ),
        ),
      ),
    );
    expect(controller.scrollController, same(scrollController));
    final position = scrollController.position;
    expect(position.maxScrollExtent, closeTo(50000 * 170 - _viewport, 5000));
    controller.jumpTo(index: 25000);
    await tester.pump();
    expect(position.pixels / position.maxScrollExtent, closeTo(0.5, 0.01));
    expect(tester.getTopLeft(_text("Item 25000")).dy, 0);
    scrollController.jumpTo(position.pixels + 123);
    await tester.pump();
    expect(tester.getTopLeft(_text("Item 25000")).dy, closeTo(-123, 0.01));
  });

  testWidgets("restorePosition saves to PageStorage only when enabled", (
    tester,
  ) async {
    for (final restore in [false, true]) {
      final controller = ItemScrollController();
      final bucket = PageStorageBucket();
      Widget list() => PageStorage(
        bucket: bucket,
        child: ScrollablePositionedList.builder(
          key: const PageStorageKey("list"),
          itemCount: 1000,
          itemScrollController: controller,
          itemPositionsListener: ItemPositionsListener.create(),
          restorePosition: restore,
          itemBuilder: (context, index) =>
              SizedBox(height: 50, child: Text("Item $index")),
        ),
      );
      await tester.pumpWidget(_host(list()));
      controller.jumpTo(index: 300, offset: -20);
      await tester.pump();
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pumpWidget(_host(list()));
      expect(_text("Item 300").evaluate(), restore ? isNotEmpty : isEmpty);
      if (restore) {
        expect(tester.getTopLeft(_text("Item 300")).dy, closeTo(-20, 0.01));
      }
      await tester.pumpWidget(_host(const SizedBox()));
    }
  });

  testWidgets("the newest list wins while a controller is shared", (
    tester,
  ) async {
    final controller = ItemScrollController();
    Widget list(String label) => Expanded(
      child: ScrollablePositionedList.builder(
        itemCount: 1000,
        itemScrollController: controller,
        itemBuilder: (context, index) =>
            SizedBox(height: 50, child: Text("$label $index")),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Column(children: [list("A")])));
    await tester.pumpWidget(
      MaterialApp(home: Column(children: [list("A"), list("B")])),
    );
    controller.jumpTo(index: 200);
    await tester.pump();
    expect(_text("B 200").evaluate(), isNotEmpty);
    expect(_text("A 200").evaluate(), isEmpty);
    await tester.pumpWidget(MaterialApp(home: Column(children: [list("A")])));
    expect(controller.isAttached, isTrue);
    controller.jumpTo(index: 400);
    await tester.pump();
    expect(_text("A 400").evaluate(), isNotEmpty);
  });

  testWidgets("scrollTo completes and lands with an offset", (tester) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(
      _host(
        ScrollablePositionedList.builder(
          itemCount: 50000,
          itemScrollController: controller,
          itemBuilder: (context, index) =>
              SizedBox(height: _extent(index), child: Text("Item $index")),
        ),
      ),
    );
    var done = false;
    unawaited(
      controller
          .scrollTo(
            index: 31000,
            alignment: 0.25,
            offset: 12,
            duration: const Duration(milliseconds: 300),
          )
          .then((_) => done = true),
    );
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(tester.getTopLeft(_text("Item 31000")).dy, closeTo(162, 0.01));
  });

  testWidgets("ScrollOffsetController animates and jumps by pixels", (
    tester,
  ) async {
    final controller = ScrollOffsetController();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      _host(
        ScrollablePositionedList.builder(
          itemCount: 1000,
          scrollOffsetController: controller,
          scrollController: scrollController,
          initialScrollIndex: 100,
          itemBuilder: (context, index) =>
              SizedBox(height: 50, child: Text("Item $index")),
        ),
      ),
    );
    expect(controller.isAttached, isTrue);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_text("Item 100")).dy, 0);
    final start = scrollController.offset;
    controller.jumpBy(30);
    expect(scrollController.offset, start + 30);
    await tester.pump();
    expect(tester.getTopLeft(_text("Item 100")).dy, -30);
    unawaited(
      controller.animateScroll(
        offset: -80,
        duration: const Duration(milliseconds: 200),
      ),
    );
    // Items above get measured while scrolling back; the animation follows
    // the resulting corrections and still moves by exactly 80 pixels.
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_text("Item 100")).dy, closeTo(50, 0.01));
  });
}

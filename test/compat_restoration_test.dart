import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

Widget _host(Widget child) => MaterialApp(home: child);

Widget _list({
  required PageStorageBucket bucket,
  required ItemScrollController controller,
  String parent = "page",
  ScrollController? scrollController,
  EdgeInsets padding = EdgeInsets.zero,
  Axis axis = Axis.vertical,
  bool reverse = false,
  double initialAlignment = 0,
  OverscrollToTarget overscrollToTarget =
      OverscrollToTarget.matchScrollablePositionedList,
}) => PageStorage(
  bucket: bucket,
  child: KeyedSubtree(
    key: PageStorageKey(parent),
    child: ScrollablePositionedList.builder(
      key: const PageStorageKey("list"),
      itemScrollController: controller,
      scrollController: scrollController,
      restorePosition: true,
      padding: padding,
      scrollDirection: axis,
      reverse: reverse,
      initialAlignment: initialAlignment,
      overscrollToTarget: overscrollToTarget,
      itemCount: 100,
      itemBuilder: (_, index) => SizedBox(
        key: ValueKey("item-$index"),
        width: 200,
        height: 200,
        child: Text("Item $index"),
      ),
    ),
  ),
);

void main() {
  for (final axis in Axis.values) {
    for (final reverse in [false, true]) {
      for (final direction in TextDirection.values) {
        testWidgets("padded anchor: $axis, reverse=$reverse, $direction", (
          tester,
        ) async {
          final controller = ItemScrollController();
          final bucket = PageStorageBucket();
          Widget list() => Directionality(
            textDirection: direction,
            child: _list(
              bucket: bucket,
              controller: controller,
              axis: axis,
              reverse: reverse,
              padding: const EdgeInsets.fromLTRB(50, 30, 60, 40),
            ),
          );
          await tester.pumpWidget(_host(list()));
          final size = tester.getSize(find.byType(ScrollablePositionedList));
          double leading() {
            final rect = tester.getRect(find.byKey(const ValueKey("item-0")));
            if (axis == Axis.vertical) {
              return reverse ? size.height - rect.bottom : rect.top;
            }
            return reverse != (direction == TextDirection.rtl)
                ? size.width - rect.right
                : rect.left;
          }

          final padding = leading();
          expect(padding, greaterThan(0));
          for (final pixels in [0.0, padding, padding + 20]) {
            controller.scrollController!.jumpTo(pixels);
            await tester.pumpAndSettle();
            final before = leading();
            final anchor = controller.anchor!;
            expect(anchor.offsetInItem, closeTo(-before, 0.01));
            controller.jumpTo(index: 20);
            await tester.pumpAndSettle();
            final restored = controller.restoreAnchorAsync(anchor);
            await tester.pump();
            await restored;
            expect(leading(), closeTo(before, 0.01));
            await tester.pumpWidget(_host(const SizedBox()));
            await tester.pumpWidget(_host(list()));
            expect(leading(), closeTo(before, 0.01));
          }
        });
      }
    }
  }

  testWidgets("restoration includes space before the first padded item", (
    tester,
  ) async {
    final controller = ItemScrollController();
    final bucket = PageStorageBucket();
    Widget list() => _list(
      bucket: bucket,
      controller: controller,
      padding: const EdgeInsets.only(top: 30),
      initialAlignment: 0.3,
      overscrollToTarget: OverscrollToTarget.always,
    );
    await tester.pumpWidget(_host(list()));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text("Item 0")).dy;
    final anchor = controller.anchor!;
    expect(before, greaterThan(30));
    expect(anchor.offsetInItem, closeTo(-before, 0.01));
    controller.jumpTo(index: 20);
    await tester.pumpAndSettle();
    final restored = controller.restoreAnchorAsync(anchor);
    await tester.pump();
    await restored;
    expect(tester.getTopLeft(find.text("Item 0")).dy, closeTo(before, 0.01));
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(_host(list()));
    expect(tester.getTopLeft(find.text("Item 0")).dy, closeTo(before, 0.01));
  });

  for (final pixels in [0.0, 10.0, 30.0, 50.0]) {
    testWidgets(
      "PageStorage restores the first padded item at $pixels pixels",
      (tester) async {
        final bucket = PageStorageBucket();
        final controller = ItemScrollController();
        Widget list() => _list(
          bucket: bucket,
          controller: controller,
          padding: const EdgeInsets.only(top: 30),
        );
        await tester.pumpWidget(_host(list()));
        controller.scrollController!.jumpTo(pixels);
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(find.text("Item 0")).dy;
        expect(controller.anchor!.offsetInItem, closeTo(-before, 0.01));
        await tester.pumpWidget(_host(const SizedBox()));
        await tester.pumpWidget(_host(list()));
        expect(
          tester.getTopLeft(find.text("Item 0")).dy,
          closeTo(before, 0.01),
        );
      },
    );

    testWidgets(
      "restoreAnchor restores the first padded item at $pixels pixels",
      (tester) async {
        final controller = ItemScrollController();
        await tester.pumpWidget(
          _host(
            _list(
              bucket: PageStorageBucket(),
              controller: controller,
              padding: const EdgeInsets.only(top: 30),
            ),
          ),
        );
        controller.scrollController!.jumpTo(pixels);
        await tester.pumpAndSettle();
        final anchor = controller.anchor!;
        final before = tester.getTopLeft(find.text("Item 0")).dy;
        controller.jumpTo(index: 20);
        await tester.pumpAndSettle();
        final restored = controller.restoreAnchorAsync(anchor);
        await tester.pump();
        await restored;
        expect(
          tester.getTopLeft(find.text("Item 0")).dy,
          closeTo(before, 0.01),
        );
        controller.jumpTo(index: 0);
        await tester.pump();
        expect(tester.getTopLeft(find.text("Item 0")).dy, 30);
      },
    );
  }

  testWidgets("jumpToAsync completes after the target layout", (tester) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(
      _host(_list(bucket: PageStorageBucket(), controller: controller)),
    );
    var completed = false;
    final jumped = controller.jumpToAsync(index: 70, offset: -25).then((_) {
      completed = true;
    });
    expect(completed, isFalse);
    await tester.pump();
    await jumped;
    expect(completed, isTrue);
    expect(tester.getTopLeft(find.text("Item 70")).dy, closeTo(-25, 0.01));
  });

  testWidgets(
    "restoration does not collide with an external scroll controller",
    (tester) async {
      final bucket = PageStorageBucket();
      final item = ItemScrollController();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Widget list() =>
          _list(bucket: bucket, controller: item, scrollController: scroll);
      await tester.pumpWidget(_host(list()));
      item.jumpTo(index: 23, offset: -25);
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pumpWidget(_host(list()));
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text("Item 23")).dy, closeTo(-25, 0.01));
    },
  );

  testWidgets("restoration respects the complete PageStorageKey chain", (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final controller = ItemScrollController();
    Widget list(String parent) =>
        _list(bucket: bucket, controller: controller, parent: parent);
    for (final (page, index) in [("first", 20), ("second", 40)]) {
      await tester.pumpWidget(_host(list(page)));
      controller.jumpTo(index: index, offset: -25);
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(const SizedBox()));
    }
    for (final (page, index) in [("first", 20), ("second", 40)]) {
      await tester.pumpWidget(_host(list(page)));
      expect(
        tester.getTopLeft(find.text("Item $index")).dy,
        closeTo(-25, 0.01),
      );
      await tester.pumpWidget(_host(const SizedBox()));
    }
  });
}

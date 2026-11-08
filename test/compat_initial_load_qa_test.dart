import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

Widget _list({
  required int count,
  required ItemScrollController controller,
  int initialIndex = 35,
  double alignment = 0.25,
  double offset = 6,
  Axis axis = Axis.vertical,
  TextDirection direction = TextDirection.ltr,
  bool reverse = false,
  PageStorageBucket? bucket,
  bool restorePosition = false,
  ListController? listController,
  ScrollController? scrollController,
  ScrollOffsetController? offsetController,
}) {
  final content = Directionality(
    textDirection: direction,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 400,
        child: ScrollablePositionedList.builder(
          key: restorePosition
              ? const PageStorageKey<String>("async-reader")
              : null,
          itemCount: count,
          itemScrollController: controller,
          listController: listController,
          scrollController: scrollController,
          scrollOffsetController: offsetController,
          initialScrollIndex: initialIndex,
          initialAlignment: alignment,
          initialOffset: offset,
          scrollDirection: axis,
          reverse: reverse,
          restorePosition: restorePosition,
          itemBuilder: (_, index) => SizedBox(
            width: axis == Axis.horizontal ? 50 : 400,
            height: axis == Axis.vertical ? 40 : 400,
            child: Text("Item $index", key: ValueKey(index)),
          ),
        ),
      ),
    ),
  );
  return MaterialApp(
    home: bucket == null
        ? content
        : PageStorage(bucket: bucket, child: content),
  );
}

void main() {
  testWidgets("empty-to-populated replaces only the inner sliver", (
    tester,
  ) async {
    final itemController = ItemScrollController();
    final offsetController = ScrollOffsetController();
    final listController = ListController();
    final scrollController = ScrollController(keepScrollOffset: false);
    Widget build(int count) => _list(
      count: count,
      controller: itemController,
      listController: listController,
      scrollController: scrollController,
      offsetController: offsetController,
    );

    await tester.pumpWidget(build(0));
    final outerState = tester.state(find.byType(ScrollablePositionedList));
    expect(itemController.isAttached, isTrue);
    expect(offsetController.isAttached, isTrue);
    expect(itemController.listController, same(listController));
    expect(itemController.scrollController, same(scrollController));

    await tester.pumpWidget(build(160));
    final populatedRenderObject = tester.renderObject(
      find.byType(SuperSliverList),
    );
    expect(
      tester.state(find.byType(ScrollablePositionedList)),
      same(outerState),
    );
    expect(itemController.listController, same(listController));
    expect(itemController.scrollController, same(scrollController));
    expect(listController.isAttached, isTrue);
    expect(listController.numberOfItems, 160);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(35))).dy,
      closeTo(106, 1),
    );
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(build(0));
    await tester.pumpWidget(build(160));
    expect(
      tester.renderObject(find.byType(SuperSliverList)),
      isNot(same(populatedRenderObject)),
    );
    expect(
      tester.state(find.byType(ScrollablePositionedList)),
      same(outerState),
    );
    expect(itemController.listController, same(listController));
    expect(itemController.scrollController, same(scrollController));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(listController.isAttached, isFalse);
    listController.dispose();
    scrollController.dispose();
  });

  testWidgets("restores a PageStorage anchor after loading through empty", (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final controller = ItemScrollController();
    Widget build(int count) => _list(
      count: count,
      controller: controller,
      initialIndex: 4,
      alignment: 0,
      offset: 0,
      restorePosition: true,
      bucket: bucket,
    );

    await tester.pumpWidget(build(160));
    final jump = controller.jumpToAsync(index: 71, offset: -12);
    await tester.pump();
    await jump;
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(71))).dy,
      closeTo(-12, 1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(build(0));
    expect(find.byKey(const ValueKey(71)), findsNothing);
    await tester.pumpWidget(build(160));

    expect(
      tester.getTopLeft(find.byKey(const ValueKey(71))).dy,
      closeTo(-12, 1),
    );
    expect(find.byKey(const ValueKey(4)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    for (final reverse in [false, true]) {
      testWidgets("horizontal $direction reverse=$reverse first-frame target", (
        tester,
      ) async {
        final controller = ItemScrollController();
        Widget build(int count) => _list(
          count: count,
          controller: controller,
          axis: Axis.horizontal,
          direction: direction,
          reverse: reverse,
        );
        await tester.pumpWidget(build(0));
        await tester.pumpWidget(build(180));

        final viewport = tester.getRect(find.byType(ScrollablePositionedList));
        final target = tester.getRect(find.byKey(const ValueKey(35)));
        final growsRight = (direction == TextDirection.ltr) != reverse;
        if (growsRight) {
          expect(target.left, closeTo(viewport.left + 106, 1));
        } else {
          expect(target.right, closeTo(viewport.right - 106, 1));
        }
        expect(find.byKey(const ValueKey(0)), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets("reverse vertical initial target is placed before first paint", (
    tester,
  ) async {
    final controller = ItemScrollController();
    Widget build(int count) => _list(
      count: count,
      controller: controller,
      axis: Axis.vertical,
      reverse: true,
      alignment: 0.4,
      offset: -8,
    );
    await tester.pumpWidget(build(0));
    await tester.pumpWidget(build(180));
    final viewport = tester.getRect(find.byType(ScrollablePositionedList));
    final target = tester.getRect(find.byKey(const ValueKey(35)));
    expect(target.bottom, closeTo(viewport.bottom - 152, 1));
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("pending jump future completes when keyed sliver goes empty", (
    tester,
  ) async {
    final controller = ItemScrollController();
    Widget build(int count) => _list(count: count, controller: controller);
    await tester.pumpWidget(build(0));
    await tester.pumpWidget(build(180));
    final pending = controller.jumpToAsync(index: 120);
    await tester.pumpWidget(build(0));
    await pending;
    expect(controller.isAttached, isTrue);
    await tester.pumpWidget(build(180));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(35))).dy,
      closeTo(106, 1),
    );
    expect(tester.takeException(), isNull);
  });
}

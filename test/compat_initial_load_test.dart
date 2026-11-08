import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

Widget _plainList(int count, ItemScrollController controller) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 400,
      height: 400,
      child: ScrollablePositionedList.builder(
        itemScrollController: controller,
        itemCount: count,
        initialScrollIndex: 47,
        initialAlignment: 0.25,
        itemBuilder: (_, index) => SizedBox(
          height: 40,
          child: Text("Item $index", key: ValueKey(index)),
        ),
      ),
    ),
  ),
);

Widget _separatedList(int count, ItemScrollController controller) =>
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 400,
          child: ScrollablePositionedList.separated(
            itemScrollController: controller,
            itemCount: count,
            initialScrollIndex: 65,
            initialAlignment: 0.4,
            initialOffset: -12,
            estimatedSeparatorExtent: 10,
            itemBuilder: (_, index) => SizedBox(
              height: 60,
              child: Text("Item $index", key: ValueKey(index)),
            ),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
          ),
        ),
      ),
    );

void main() {
  testWidgets("initial item lands before paint after initially empty data", (
    tester,
  ) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(_plainList(0, controller));
    expect(controller.isAttached, isTrue);
    expect(find.byKey(const ValueKey(47)), findsNothing);

    await tester.pumpWidget(_plainList(200, controller));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(47))).dy,
      closeTo(100, 0.01),
    );
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("separated list retains initial item index and pixel offset", (
    tester,
  ) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(_separatedList(0, controller));
    await tester.pumpWidget(_separatedList(120, controller));

    expect(
      tester.getTopLeft(find.byKey(const ValueKey(65))).dy,
      closeTo(148, 0.01),
    );
    expect(tester.takeException(), isNull);
  });
}

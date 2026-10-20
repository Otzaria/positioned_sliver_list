import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

void main() {
  testWidgets("a supplied rect resolver gives item zero exact geometry", (
    tester,
  ) async {
    final item = ItemScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ScrollablePositionedList.builder(
          itemScrollController: item,
          padding: const EdgeInsets.only(top: 30),
          overscrollToTarget: OverscrollToTarget.always,
          itemCount: 10,
          itemBuilder: (_, index) => SizedBox(
            key: ValueKey(index),
            height: 1000,
            child: Text("Item $index"),
          ),
        ),
      ),
    );
    final first = find.byKey(const ValueKey(0));
    expect(tester.getTopLeft(first).dy, 30);

    var jumped = item.jumpToAsync(index: 0);
    await tester.pump();
    await jumped;
    expect(tester.getTopLeft(first).dy, 30);

    jumped = item.jumpToAsync(index: 0, targetRectResolver: (_, child) => null);
    await tester.pump();
    await jumped;
    expect(tester.getTopLeft(first).dy, 0);

    jumped = item.jumpToAsync(
      index: 0,
      offset: 9,
      targetRectResolver: (_, child) => const Rect.fromLTWH(0, 40, 100, 20),
    );
    await tester.pump();
    await jumped;
    expect(tester.getTopLeft(first).dy + 40, 9);
  });

  for (final animate in [false, true]) {
    testWidgets(
      "rect resolvers receive logical separated indices: animate=$animate",
      (tester) async {
        final item = ItemScrollController();
        final resolvedIndices = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: ScrollablePositionedList.separated(
              itemScrollController: item,
              itemCount: 100,
              estimatedSeparatorExtent: 7,
              estimateExtent: (_, width) => 300,
              itemBuilder: (_, index) => SizedBox(
                key: ValueKey(index),
                height: 300,
                child: Text("Item $index"),
              ),
              separatorBuilder: (_, index) => const SizedBox(height: 7),
            ),
          ),
        );
        Rect? resolve(int index, RenderBox child) {
          resolvedIndices.add(index);
          expect(child.size.height, 300);
          return Rect.fromLTWH(0, 80, child.size.width, 40);
        }

        final Future<void> completed;
        if (animate) {
          completed = item.scrollTo(
            index: 40,
            alignment: 0.5,
            offset: 13,
            duration: const Duration(milliseconds: 100),
            targetRectResolver: resolve,
          );
        } else {
          completed = item.jumpToAsync(
            index: 40,
            alignment: 0.5,
            offset: 13,
            targetRectResolver: resolve,
          );
        }
        await tester.pumpAndSettle();
        await completed;
        expect(resolvedIndices, isNotEmpty);
        expect(resolvedIndices.toSet(), {40});
        expect(
          tester.getTopLeft(find.byKey(const ValueKey(40))).dy + 80,
          closeTo(600 / 2 + 13, 0.01),
        );
      },
    );
  }
}

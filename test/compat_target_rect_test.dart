import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

void main() {
  testWidgets(
    "the initial resolver aligns a logical separated item before paint",
    (tester) async {
      final resolved = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ScrollablePositionedList.separated(
            itemCount: 100,
            initialScrollIndex: 40,
            initialAlignment: 0.5,
            initialOffset: 13,
            initialTargetRectResolver: (index, child) {
              resolved.add(index);
              return Rect.fromLTWH(0, 80, child.size.width, 40);
            },
            estimatedSeparatorExtent: 7,
            estimateExtent: (_, width) => 300,
            itemBuilder: (_, index) =>
                SizedBox(key: ValueKey(index), height: 300),
            separatorBuilder: (_, index) => const SizedBox(height: 7),
          ),
        ),
      );
      expect(resolved, isNotEmpty);
      expect(resolved.toSet(), {40});
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(40))).dy + 80,
        closeTo(313, 0.01),
      );
    },
  );

  testWidgets("a null initial resolver preserves an exact item-zero offset", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScrollablePositionedList(
          itemCount: 10,
          padding: const EdgeInsets.only(top: 30),
          initialOffset: 9,
          initialTargetRectResolver: (_, child) => null,
          itemBuilder: (_, index) =>
              SizedBox(key: ValueKey(index), height: 1000),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey(0))).dy, 9);
  });

  testWidgets("PageStorage takes precedence over an initial rect resolver", (
    tester,
  ) async {
    final item = ItemScrollController();
    final bucket = PageStorageBucket();
    var resolutions = 0;
    Widget list() => MaterialApp(
      home: PageStorage(
        bucket: bucket,
        child: ScrollablePositionedList.builder(
          key: const PageStorageKey("list"),
          itemScrollController: item,
          itemCount: 100,
          restorePosition: true,
          initialScrollIndex: 40,
          initialTargetRectResolver: (_, child) {
            resolutions++;
            return const Rect.fromLTWH(0, 80, 100, 40);
          },
          itemBuilder: (_, index) =>
              SizedBox(key: ValueKey(index), height: 300),
        ),
      ),
    );
    await tester.pumpWidget(list());
    expect(resolutions, greaterThan(0));
    await tester.pumpAndSettle();
    final jumped = item.jumpToAsync(index: 50, offset: -23);
    await tester.pump();
    await jumped;
    final saved = item.anchor!;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    resolutions = 0;
    await tester.pumpWidget(list());
    expect(resolutions, 0);
    expect(item.anchor!.index, saved.index);
    expect(item.anchor!.offsetInItem, closeTo(saved.offsetInItem, 0.01));
  });

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

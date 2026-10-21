import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

const _itemExtent = 40.0;

Widget _host(Widget child) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 300, height: 400, child: child),
  ),
);

Widget _item(int index, int generation) =>
    SizedBox(height: _itemExtent, child: Text("$index $generation"));

class _Harness {
  final controller = ItemScrollController();
  ItemPositionsListener listener = ItemPositionsListener.create();
  int generation = 0;
  late StateSetter setState;
  int notifications = 0;

  Widget build({required bool notifyPositionsOnRebuild}) => _host(
    StatefulBuilder(
      builder: (context, set) {
        setState = set;
        return ScrollablePositionedList.builder(
          itemScrollController: controller,
          itemPositionsListener: listener,
          notifyPositionsOnRebuild: notifyPositionsOnRebuild,
          itemCount: 100,
          itemBuilder: (_, index) => _item(index, generation),
        );
      },
    ),
  );

  void count() => listener.itemPositions.addListener(() => ++notifications);

  void rebuild() => setState(() => ++generation);

  ItemPosition get first => listener.itemPositions.value.first;
}

void main() {
  testWidgets("rebuilds in one frame notify once", (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build(notifyPositionsOnRebuild: true));
    final before = harness.listener.itemPositions.value.toList();
    harness.count();

    // A build pass before the frame, then the frame's own: both rebuild the
    // list before the post-frame callbacks run.
    harness.rebuild();
    tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
    expect(find.text("0 1"), findsOneWidget);
    harness.rebuild();
    await tester.pump();

    expect(find.text("0 2"), findsOneWidget);
    expect(harness.notifications, 1);
    expect(harness.listener.itemPositions.value, before);
  });

  group("notifyPositionsOnRebuild false", () {
    testWidgets("does not notify a rebuild that moves nothing", (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build(notifyPositionsOnRebuild: false));
      final before = harness.listener.itemPositions.value.toList();
      expect(before, isNotEmpty);
      harness.count();

      for (var i = 0; i < 3; i++) {
        harness.rebuild();
        await tester.pump();
      }

      expect(harness.notifications, 0);
      expect(find.text("0 3"), findsOneWidget);
      expect(harness.listener.itemPositions.value, before);
    });

    testWidgets("still publishes to a replaced itemPositionsListener", (
      tester,
    ) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build(notifyPositionsOnRebuild: false));
      harness.controller.jumpTo(index: 7);
      await tester.pumpAndSettle();
      final before = harness.listener.itemPositions.value.toList();

      harness.listener = ItemPositionsListener.create();
      harness.count();
      await tester.pumpWidget(harness.build(notifyPositionsOnRebuild: false));

      expect(harness.notifications, 1);
      expect(harness.listener.itemPositions.value, before);
      expect(harness.first.index, 7);

      harness.rebuild();
      await tester.pump();
      expect(harness.notifications, 1);
    });

    testWidgets("publishes after a scroll", (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build(notifyPositionsOnRebuild: false));
      harness.count();

      harness.rebuild();
      harness.controller.scrollController!.jumpTo(100);
      await tester.pump();

      // 100 pixels are 2.5 items of 40 in a viewport of 400.
      expect(harness.notifications, 1);
      expect(harness.first.index, 2);
      expect(harness.first.itemLeadingEdge, closeTo(-0.05, 1e-9));
    });

    testWidgets("publishes after a jump", (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build(notifyPositionsOnRebuild: false));
      final published = <int>[];
      harness.listener.itemPositions.addListener(
        () => published.add(harness.first.index),
      );

      harness.rebuild();
      harness.controller.jumpTo(index: 30);
      await tester.pumpAndSettle();

      expect(published, [30]);
      expect(harness.first.itemLeadingEdge, 0);
    });
  });
}

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart"
    show SuperListView;

const _itemExtent = 40.0;

Widget _host(Widget child) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 300, height: 400, child: child),
  ),
);

Widget _item(int index, [String suffix = ""]) =>
    SizedBox(height: _itemExtent, child: Text("$index$suffix"));

Widget _compat(
  double padding,
  ItemScrollController controller,
  ItemPositionsListener listener, {
  int itemCount = 100,
}) => _host(
  ScrollablePositionedList.builder(
    itemScrollController: controller,
    itemPositionsListener: listener,
    itemCount: itemCount,
    padding: EdgeInsets.symmetric(vertical: padding),
    itemBuilder: (_, index) => _item(index),
  ),
);

Widget _listView(
  double padding,
  ScrollController scrollController,
  ListController listController,
) => _host(
  SuperListView.builder(
    controller: scrollController,
    listController: listController,
    itemCount: 100,
    padding: EdgeInsets.only(top: padding),
    itemBuilder: (_, index) => _item(index),
  ),
);

ItemPosition _position(ItemPositionsListener listener, int index) =>
    listener.itemPositions.value.firstWhere((p) => p.index == index);

void main() {
  group("leading padding change", () {
    for (final (from, to) in [(16.0, 20.0), (20.0, 16.0), (16.0, 80.0)]) {
      testWidgets("keeps the leading item in place, $from -> $to", (
        tester,
      ) async {
        final controller = ItemScrollController();
        final listener = ItemPositionsListener.create();
        await tester.pumpWidget(_compat(from, controller, listener));
        controller.jumpTo(index: 25);
        await tester.pumpAndSettle();
        expect(listener.itemPositions.value.first.index, 25);
        await tester.pumpWidget(_compat(to, controller, listener));
        await tester.pumpAndSettle();
        expect(_position(listener, 25).itemLeadingEdge, 0);
        expect(tester.getTopLeft(find.text("25")).dy, 0);
      });
    }

    testWidgets("keeps a partly scrolled item in place", (tester) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      await tester.pumpWidget(_compat(16, controller, listener));
      controller.jumpTo(index: 25, offset: -15);
      await tester.pumpAndSettle();
      await tester.pumpWidget(_compat(30, controller, listener));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text("25")).dy, -15);
    });

    testWidgets("moves the content when the list is at its start", (
      tester,
    ) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      await tester.pumpWidget(_compat(16, controller, listener));
      await tester.pumpWidget(_compat(30, controller, listener));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text("0")).dy, 30);
      expect(controller.scrollController!.position.pixels, 0);
    });

    testWidgets("keeps the leading item of a SuperListView in place", (
      tester,
    ) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      await tester.pumpWidget(_listView(10, scrollController, listController));
      listController.jumpToIndex(30);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text("30")).dy, 0);
      await tester.pumpWidget(_listView(50, scrollController, listController));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text("30")).dy, 0);
      await tester.pumpWidget(_listView(5, scrollController, listController));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text("30")).dy, 0);
    });

    testWidgets("a scroll in the same frame still moves the list", (
      tester,
    ) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      await tester.pumpWidget(_compat(16, controller, listener));
      controller.jumpTo(index: 25);
      await tester.pumpAndSettle();
      final position = controller.scrollController!.position;
      final pixels = position.pixels;
      await tester.pumpWidget(_compat(20, controller, listener));
      position.jumpTo(pixels + 100);
      await tester.pumpAndSettle();
      expect(position.pixels, pixels + 100);
    });
  });

  group("published positions", () {
    testWidgets("a rebuild never republishes positions older than a scroll", (
      tester,
    ) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      var generation = 0;
      late StateSetter setState;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, set) {
              setState = set;
              return ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: listener,
                itemCount: 100,
                itemBuilder: (_, index) => _item(index, " $generation"),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final published = <double>[];
      listener.itemPositions.addListener(() {
        final first = listener.itemPositions.value.first;
        published.add(first.index - first.itemLeadingEdge * 10);
      });
      tester.binding.addPostFrameCallback(
        (_) => controller.scrollController!.position.jumpTo(100),
      );
      setState(() => ++generation);
      await tester.pump();
      await tester.pump();
      // 100 pixels are 2.5 items; values are first index plus fraction.
      expect(published, isNotEmpty);
      expect(published.first, closeTo(2.5, 0.01), reason: "$published");
      expect(published.last, closeTo(2.5, 0.01), reason: "$published");
    });

    testWidgets("a rebuild without a scroll still notifies listeners", (
      tester,
    ) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      var generation = 0;
      late StateSetter setState;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, set) {
              setState = set;
              return ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: listener,
                itemCount: 100,
                itemBuilder: (_, index) => _item(index, " $generation"),
              );
            },
          ),
        ),
      );
      controller.jumpTo(index: 7);
      await tester.pumpAndSettle();
      var notifications = 0;
      listener.itemPositions.addListener(() => ++notifications);
      setState(() => ++generation);
      await tester.pump();
      expect(notifications, 1);
      expect(listener.itemPositions.value.first.index, 7);
    });

    testWidgets("ListController.itemPositions skips a stale layout", (
      tester,
    ) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      await tester.pumpWidget(_listView(0, scrollController, listController));
      final published = <int>[];
      listController.itemPositions.addListener(
        () => published.add(listController.itemPositions.value.first.index),
      );
      await tester.pump();
      published.clear();
      // A layout that changes positions, then a scroll before they publish.
      scrollController.jumpTo(40);
      tester.binding.addPostFrameCallback((_) => scrollController.jumpTo(200));
      await tester.pump();
      await tester.pump();
      expect(published, [5], reason: "$published");
      expect(listController.computeItemPositions()!.first.index, 5);
    });
  });
}

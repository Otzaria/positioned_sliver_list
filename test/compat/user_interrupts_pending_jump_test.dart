import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

Widget _list(ItemScrollController controller) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      height: 400,
      width: 400,
      child: ScrollablePositionedList.builder(
        itemScrollController: controller,
        initialScrollIndex: 5,
        itemCount: 2000,
        estimateExtent: (_, _) => 40,
        itemBuilder: (_, index) => SizedBox(
          height: 40,
          child: Text("Item $index", key: ValueKey(index)),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets("user drag cancels a jump pending in the same frame", (
    tester,
  ) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(_list(controller));
    final before = controller.scrollController!.offset;
    final pending = controller.jumpToAsync(index: 1500);
    // This gesture is delivered before the layout that would resolve the
    // distant jump; it must win rather than be overwritten in that layout.
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    await pending;
    expect(controller.scrollController!.offset, closeTo(before + 60, 0.1));
    expect(find.byKey(const ValueKey(1500)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("mouse wheel cancels a jump pending in the same frame", (
    tester,
  ) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(_list(controller));
    final before = controller.scrollController!.offset;
    final pending = controller.jumpToAsync(index: 1500);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, 80),
      ),
    );
    await tester.pumpAndSettle();
    await pending;
    expect(controller.scrollController!.offset, closeTo(before + 80, 0.1));
    expect(find.byKey(const ValueKey(1500)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("trackpad pan cancels a jump pending in the same frame", (
    tester,
  ) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(_list(controller));
    final before = controller.scrollController!.offset;
    final pending = controller.jumpToAsync(index: 1500);
    // Trackpads use PointerPanZoom events, not PointerDown/PointerScroll.
    final gesture = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomUpdate(
      const Offset(200, 200),
      pan: const Offset(0, -80),
    );
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    await pending;
    expect(controller.scrollController!.offset, closeTo(before + 80, 0.1));
    expect(find.byKey(const ValueKey(1500)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("tapping an item is not blocked by pending-jump cancellation", (
    tester,
  ) async {
    final controller = ItemScrollController();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 400,
            width: 400,
            child: ScrollablePositionedList.builder(
              itemScrollController: controller,
              initialScrollIndex: 5,
              itemCount: 2000,
              estimateExtent: (_, _) => 40,
              itemBuilder: (_, index) => SizedBox(
                height: 40,
                child: TextButton(
                  onPressed: () => taps++,
                  child: Text("Item $index"),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final before = controller.scrollController!.offset;
    final pending = controller.jumpToAsync(index: 1500);
    await tester.tap(find.text("Item 5"));
    await tester.pumpAndSettle();
    await pending;
    expect(taps, 1);
    expect(controller.scrollController!.offset, closeTo(before, 0.1));
    expect(find.text("Item 1500"), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

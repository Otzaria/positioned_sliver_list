import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

void main() {
  testWidgets("user drag remains observable during pending programmatic jump", (
    tester,
  ) async {
    final item = ItemScrollController();
    final offsetListener = ScrollOffsetListener.create(
      recordProgrammaticScrolls: false,
    );
    final received = <double>[];
    final sub = offsetListener.changes.listen(received.add);
    addTearDown(sub.cancel);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: ScrollablePositionedList.builder(
            itemScrollController: item,
            scrollOffsetListener: offsetListener,
            itemCount: 1000,
            estimateExtent: (_, _) => 40,
            itemBuilder: (_, index) => const SizedBox(height: 40),
          ),
        ),
      ),
    );

    final pendingJump = item.jumpToAsync(index: 700);
    final context = tester.element(find.byType(CustomScrollView));
    final metrics = item.scrollController!.position;
    // Programmatic updates are suppressed while the asynchronous operation
    // is outstanding.
    ScrollUpdateNotification(
      metrics: metrics,
      context: context,
      scrollDelta: 50,
    ).dispatch(context);

    // A real drag has dragDetails even if a previous navigation Future has
    // not yet completed. Do not suppress this user-driven delta.
    ScrollUpdateNotification(
      metrics: metrics,
      context: context,
      scrollDelta: 35,
      dragDetails: DragUpdateDetails(
        delta: const Offset(0, -35),
        globalPosition: const Offset(0, 100),
      ),
    ).dispatch(context);

    await tester.pump();
    await pendingJump;
    expect(received, [35]);
    expect(tester.takeException(), isNull);
  });
}

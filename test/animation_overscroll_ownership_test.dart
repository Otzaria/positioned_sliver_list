import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";
import "package:positioned_sliver_list/src/render_object.dart";

void main() {
  late ListController list;
  late ScrollController scroll;

  setUp(() {
    list = ListController();
    scroll = ScrollController();
  });
  tearDown(() {
    list.dispose();
    scroll.dispose();
  });

  Widget host() => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 600,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SuperSliverList.builder(
              listController: list,
              itemCount: 120,
              overscrollToTarget: OverscrollToTarget.always,
              extentEstimation: (_, _) => 60.0,
              itemBuilder: (_, index) => SizedBox(
                key: ValueKey(index),
                height: 60,
                child: Text("Item $index"),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets("old animation cannot clear replacement overscroll hold", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final render = tester.renderObject<RenderSuperSliverList>(
      find.byType(SuperSliverList),
    );
    final old = list.scrollToIndex(
      119,
      duration: const Duration(milliseconds: 500),
    );
    expect(render.holdOverscrollSpace, isTrue);

    final latest = list.scrollToIndex(
      0,
      alignment: 0.4,
      duration: const Duration(milliseconds: 500),
    );
    expect(render.holdOverscrollSpace, isTrue);

    // The old activity reports cancellation asynchronously. It must not
    // release the hold belonging to the current activity.
    await tester.pump();
    expect(latest.isAnimating, isTrue);
    expect(render.holdOverscrollSpace, isTrue);
    await tester.pump(const Duration(milliseconds: 150));
    expect(render.holdOverscrollSpace, isTrue);

    await tester.pumpAndSettle();
    await Future.wait([old, latest]);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(0))).dy,
      closeTo(240, 0.01),
    );
    expect(render.holdOverscrollSpace, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets("explicit cancellation releases overscroll hold immediately", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final render = tester.renderObject<RenderSuperSliverList>(
      find.byType(SuperSliverList),
    );
    final handle = list.scrollToIndex(
      119,
      duration: const Duration(seconds: 1),
    );
    expect(render.holdOverscrollSpace, isTrue);

    list.cancelPositioning();
    expect(render.holdOverscrollSpace, isFalse);
    await tester.pumpAndSettle();
    await handle;
    expect(render.holdOverscrollSpace, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets("canceling the handle revokes the current reveal", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final render = tester.renderObject<RenderSuperSliverList>(
      find.byType(SuperSliverList),
    );
    final handle = list.scrollToIndex(
      119,
      duration: const Duration(milliseconds: 300),
    );
    expect(render.holdOverscrollSpace, isTrue);

    handle.cancel();
    expect(render.holdOverscrollSpace, isFalse);
    final stoppedAt = scroll.offset;
    await tester.pumpAndSettle();
    await handle;
    expect(scroll.offset, closeTo(stoppedAt, 0.01));
    expect(render.holdOverscrollSpace, isFalse);
    expect(tester.takeException(), isNull);
  });
}

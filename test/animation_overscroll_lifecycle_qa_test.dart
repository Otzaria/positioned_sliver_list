import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";
import "package:positioned_sliver_list/src/element.dart";
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

  Widget host({
    Axis axis = Axis.vertical,
    bool reverse = false,
    TextDirection direction = TextDirection.ltr,
  }) => MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 600,
          child: CustomScrollView(
            controller: scroll,
            scrollDirection: axis,
            reverse: reverse,
            slivers: [
              SuperSliverList.builder(
                listController: list,
                itemCount: 120,
                overscrollToTarget: OverscrollToTarget.always,
                extentEstimation: (_, _) => 60.0,
                itemBuilder: (_, index) => SizedBox(
                  key: ValueKey(index),
                  width: axis == Axis.horizontal ? 60 : null,
                  height: axis == Axis.vertical ? 60 : null,
                  child: Text("Item $index"),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets("handle cancellation revokes final jump after ticker stops", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final render = tester.renderObject<RenderSuperSliverList>(
      find.byType(SuperSliverList),
    );
    final element =
        tester.element(find.byType(SuperSliverList))
            as SuperSliverMultiBoxAdaptorElement;
    final handle = list.scrollToIndex(
      119,
      duration: const Duration(milliseconds: 300),
    );

    // First tick initializes the clock; the next one finishes the ticker.
    await tester.pump();
    // Stop before layout so the ticker-completion microtask can schedule
    // its final jump without letting that jump settle in this same frame.
    await tester.pump(const Duration(milliseconds: 301), EnginePhase.build);
    expect(render.hasPendingTarget, isTrue);
    expect(handle.isAnimating, isTrue, reason: "final reveal still pending");
    expect(element.extentManager.revealOwner, isNotNull);

    handle.cancel();
    // The ticker's owner has already been replaced by jumpToIndex's owner.
    // Cancel must revoke that NEW owner, not merely stop the old ticker.
    expect(element.extentManager.revealOwner, isNull);
    expect(render.holdOverscrollSpace, isFalse);
    final stoppedAt = scroll.offset;

    await tester.pumpAndSettle();
    await handle;
    expect(render.hasPendingTarget, isFalse);
    expect(scroll.offset, closeTo(stoppedAt, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets("old handle cannot revoke a newer animation after final jump", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final render = tester.renderObject<RenderSuperSliverList>(
      find.byType(SuperSliverList),
    );
    final old = list.scrollToIndex(
      119,
      duration: const Duration(milliseconds: 300),
    );

    await tester.pump();
    // Stop before layout so the ticker-completion microtask can schedule
    // its final jump without letting that jump settle in this same frame.
    await tester.pump(const Duration(milliseconds: 301), EnginePhase.build);
    expect(render.hasPendingTarget, isTrue);

    final latest = list.scrollToIndex(
      0,
      alignment: 0.4,
      duration: const Duration(milliseconds: 300),
    );
    old.cancel();
    expect(render.holdOverscrollSpace, isTrue);
    expect(latest.isAnimating, isTrue);

    await tester.pumpAndSettle();
    await Future.wait([old, latest]);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(0))).dy,
      closeTo(240, 0.01),
    );
    expect(render.holdOverscrollSpace, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets("zero-duration handle cancels pending jump and resolves", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final render = tester.renderObject<RenderSuperSliverList>(
      find.byType(SuperSliverList),
    );
    final element =
        tester.element(find.byType(SuperSliverList))
            as SuperSliverMultiBoxAdaptorElement;
    final handle = list.scrollToIndex(119, duration: Duration.zero);
    expect(render.hasPendingTarget, isTrue);
    expect(element.extentManager.revealOwner, isNotNull);

    handle.cancel();
    expect(element.extentManager.revealOwner, isNull);
    await handle;
    await tester.pumpAndSettle();
    expect(render.hasPendingTarget, isFalse);
    expect(scroll.offset, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets("old zero-duration handle cannot cancel replacement jump", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final old = list.scrollToIndex(119, duration: Duration.zero);
    final latest = list.scrollToIndex(
      0,
      alignment: 0.4,
      duration: Duration.zero,
    );
    old.cancel();

    await tester.pumpAndSettle();
    await Future.wait([old, latest]);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(0))).dy,
      closeTo(240, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    for (final reverse in [false, true]) {
      testWidgets(
        "horizontal $direction reverse=$reverse keeps replacement owner",
        (tester) async {
          await tester.pumpWidget(
            host(axis: Axis.horizontal, reverse: reverse, direction: direction),
          );
          final render = tester.renderObject<RenderSuperSliverList>(
            find.byType(SuperSliverList),
          );
          final old = list.scrollToIndex(
            119,
            duration: const Duration(milliseconds: 500),
          );
          final latest = list.scrollToIndex(
            0,
            alignment: 0.4,
            duration: const Duration(milliseconds: 500),
          );
          await tester.pump();
          old.cancel();
          expect(render.holdOverscrollSpace, isTrue);

          await tester.pumpAndSettle();
          await Future.wait([old, latest]);
          final rect = tester.getRect(find.byKey(const ValueKey(0)));
          final fromRight = (direction == TextDirection.rtl) != reverse;
          final leading = fromRight ? 400 - rect.right : rect.left;
          expect(leading, closeTo(160, 0.01));
          expect(render.holdOverscrollSpace, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

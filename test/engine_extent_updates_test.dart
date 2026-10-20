import "dart:async";

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

class _Harness {
  final list = ListController();
  final scroll = ScrollController();
  int estimateCalls = 0;

  Widget build({
    double width = 400,
    double height = 100,
    double estimate = 100,
    Object? estimationKey,
    EdgeInsets padding = EdgeInsets.zero,
    OverscrollToTarget overscroll = OverscrollToTarget.none,
    VoidCallback? duringBuild,
  }) => Directionality(
    textDirection: TextDirection.rtl,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 600,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverPadding(
              padding: padding,
              sliver: SuperSliverList.builder(
                listController: list,
                itemCount: 10000,
                estimationKey: estimationKey,
                extentEstimation: (index, crossAxis) {
                  estimateCalls++;
                  return index == null ? 0 : estimate * 400 / crossAxis;
                },
                overscrollToTarget: overscroll,
                itemBuilder: (_, index) {
                  if (index == 0) duringBuild?.call();
                  return SizedBox(key: ValueKey(index), height: height);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> place(WidgetTester tester) async {
    unawaited(list.jumpToIndex(1000, offset: -37.5));
    await tester.pump();
    await tester.pump();
  }

  void dispose() {
    list.dispose();
    scroll.dispose();
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  testWidgets(
    "width refreshes distant estimates and preserves anchor fraction",
    (tester) async {
      await tester.pumpWidget(h.build());
      await h.place(tester);
      final callsBeforeResize = h.estimateCalls;
      await tester.pumpWidget(h.build(width: 200, height: 200));
      await tester.pump();
      expect(h.estimateCalls - callsBeforeResize, 10001);
      expect(h.list.extentForIndex(8000), (200.0, true));
      expect(h.list.anchor!.index, 1000);
      expect(h.list.anchor!.offsetInItem, closeTo(75, 0.01));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(1000))).dy,
        closeTo(-75, 0.01),
      );
    },
  );

  testWidgets(
    "estimation key refreshes while callback identity alone does not",
    (tester) async {
      await tester.pumpWidget(h.build(estimationKey: 1));
      await h.place(tester);
      final firstCalls = h.estimateCalls;
      await tester.pumpWidget(h.build(estimate: 200, estimationKey: 1));
      expect(h.estimateCalls, firstCalls);
      expect(h.list.extentForIndex(8000).$1, 100);
      await tester.pumpWidget(h.build(estimate: 200, estimationKey: 2));
      expect(h.estimateCalls, greaterThan(firstCalls));
      expect(h.list.extentForIndex(8000), (200.0, true));
      expect(h.list.anchor!.index, 1000);
      expect(h.list.anchor!.offsetInItem, closeTo(37.5, 0.01));
    },
  );

  testWidgets("invalidate refreshes estimates without building distant items", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    await tester.pumpWidget(h.build(estimate: 500));
    h.list.invalidateAllExtents();
    await tester.pump();
    expect(h.list.extentForIndex(8000), (500.0, true));
    await tester.pumpWidget(h.build(estimate: 300));
    h.list.invalidateExtent(8000);
    await tester.pump();
    expect(h.list.extentForIndex(8000), (300.0, true));
    expect(h.list.extentForIndex(8001), (500.0, true));
    expect(find.byKey(const ValueKey(8000)), findsNothing);
  });

  testWidgets("batch updates preserve reading position and notify once", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    await h.place(tester);
    var notifications = 0;
    h.list.extentsChangedListenable.addListener(() => notifications++);
    var complete = false;
    final future = h.list.updateEstimatedExtents({20: 150, 30: 200, 8000: 500});
    unawaited(future.then((_) => complete = true));
    expect(complete, isFalse);
    expect(notifications, 0);
    await tester.pump();
    await future;
    expect(complete, isTrue);
    expect(notifications, 1);
    expect(h.list.extentForIndex(20), (150.0, true));
    expect(h.list.extentForIndex(8000), (500.0, true));
    expect(h.list.anchor!.index, 1000);
    expect(h.list.anchor!.offsetInItem, closeTo(37.5, 0.01));
  });

  testWidgets("invalid batch values are rejected atomically", (tester) async {
    await tester.pumpWidget(h.build());
    expect(
      () => h.list.updateEstimatedExtents({8000: 150, 10000: 200}),
      throwsRangeError,
    );
    expect(
      () => h.list.updateEstimatedExtents({8000: double.nan}),
      throwsArgumentError,
    );
    expect(
      () => h.list.updateEstimatedExtents({8000: -1}),
      throwsArgumentError,
    );
    await tester.pump();
    expect(h.list.extentForIndex(8000), (100.0, true));
  });

  testWidgets("batch updates reject writes during child layout", (
    tester,
  ) async {
    await tester.pumpWidget(
      h.build(
        duringBuild: () => expect(
          () => h.list.updateEstimatedExtents({8000: 150}),
          throwsStateError,
        ),
      ),
    );
  });

  testWidgets("scroll pixels include leading padding", (tester) async {
    await tester.pumpWidget(h.build(padding: const EdgeInsets.only(top: 30)));
    expect(h.list.indexForScrollOffset(0), isNull);
    expect(h.list.indexForScrollOffset(29), isNull);
    expect(h.list.indexForScrollOffset(30), 0);
    expect(h.list.indexForScrollOffset(129), 0);
    expect(h.list.indexForScrollOffset(130), 1);
    expect(h.list.indexForScrollOffset(1000030), isNull);
  });

  testWidgets("scroll pixels exclude reserved blank leading space", (
    tester,
  ) async {
    await tester.pumpWidget(h.build(overscroll: OverscrollToTarget.always));
    unawaited(h.list.jumpToIndex(0, alignment: 0.5));
    await tester.pump();
    expect(h.list.overscrollSpace.leading, 300);
    expect(h.list.indexForScrollOffset(299), isNull);
    expect(h.list.indexForScrollOffset(300), 0);
    expect(h.list.indexForScrollOffset(400), 1);
  });
}

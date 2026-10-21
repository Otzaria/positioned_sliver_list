import "dart:async";
import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart" as compat;
import "package:positioned_sliver_list/positioned_sliver_list.dart";

const _itemCount = 1000;

Object? _column300(double width) => math.min(width, 300);

class _Harness {
  final list = ListController();
  final scroll = ScrollController();
  int estimateCalls = 0;
  final childWidths = <int, double>{};

  Widget build({
    double width = 400,
    CrossAxisLayoutKey? key = _column300,
    Object? estimationKey,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 600,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SuperSliverList.builder(
              listController: list,
              itemCount: _itemCount,
              estimationKey: estimationKey,
              crossAxisLayoutKey: key,
              extentEstimation: (index, crossAxis) {
                estimateCalls++;
                return index == null ? 0 : 30000 / math.min(crossAxis, 300);
              },
              itemBuilder: (_, index) => LayoutBuilder(
                builder: (_, constraints) {
                  childWidths[index] = constraints.maxWidth;
                  return const SizedBox(height: 50);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Measures the first items, then moves away so that they are not live.
  Future<void> measureAndLeave(WidgetTester tester) async {
    unawaited(list.jumpToIndex(500));
    await tester.pump();
    await tester.pump();
  }

  EstimateRefreshStats get stats => list.estimateRefreshStats!;

  void dispose() {
    list.dispose();
    scroll.dispose();
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  testWidgets("unchanged key keeps measured extents across width change", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    await h.measureAndLeave(tester);
    expect(h.list.extentForIndex(5), (50.0, false));
    final calls = h.estimateCalls;
    final before = h.stats;

    await tester.pumpWidget(h.build(width: 350));
    await tester.pump();
    expect(h.list.extentForIndex(5), (50.0, false));
    expect(h.list.extentForIndex(900), (100.0, true));
    expect(h.estimateCalls, calls);
    expect(h.stats.refreshCount, before.refreshCount);
    expect(h.stats.skippedResizeCount, before.skippedResizeCount + 1);
    expect(h.list.anchor!.index, 500);
    expect(h.list.anchor!.offsetInItem, 0);
  });

  testWidgets("changed key refreshes", (tester) async {
    await tester.pumpWidget(h.build());
    await h.measureAndLeave(tester);

    await tester.pumpWidget(h.build(width: 250));
    await tester.pump();
    await tester.pump();
    expect(h.stats.refreshCount, 1);
    expect(h.stats.skippedResizeCount, 0);
    expect(h.list.extentForIndex(5), (120.0, true));
    expect(h.list.extentForIndex(900), (120.0, true));
    expect(h.list.anchor!.index, 500);
  });

  testWidgets("key fn returning different value for same width refreshes", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    await h.measureAndLeave(tester);

    await tester.pumpWidget(h.build(key: (width) => math.min(width, 200)));
    expect(h.stats.refreshCount, 1);
    expect(h.list.extentForIndex(5).$2, isTrue);
  });

  testWidgets("new closure same key no refresh", (tester) async {
    await tester.pumpWidget(h.build());
    await h.measureAndLeave(tester);
    final calls = h.estimateCalls;

    await tester.pumpWidget(h.build(key: (width) => math.min(width, 300)));
    await tester.pumpWidget(h.build(key: (width) => math.min(width, 300)));
    expect(h.estimateCalls, calls);
    expect(h.stats.refreshCount, 0);
    expect(h.list.extentForIndex(5), (50.0, false));
  });

  testWidgets("setting a key or removing it does not refresh by itself", (
    tester,
  ) async {
    await tester.pumpWidget(h.build(key: null));
    await h.measureAndLeave(tester);
    await tester.pumpWidget(h.build());
    expect(h.stats.refreshCount, 0);
    await tester.pumpWidget(h.build(width: 350));
    expect(h.stats.skippedResizeCount, 1);
    await tester.pumpWidget(h.build(width: 350, key: null));
    expect(h.stats.refreshCount, 0);
    await tester.pumpWidget(h.build(width: 320, key: null));
    await tester.pump();
    expect(h.stats.refreshCount, 1);
  });

  testWidgets("live children receive new constraints", (tester) async {
    await tester.pumpWidget(h.build());
    expect(h.childWidths[0], 400);
    await tester.pumpWidget(h.build(width: 350));
    expect(h.stats.skippedResizeCount, 1);
    expect(h.childWidths[0], 350);
    expect(tester.getSize(find.byType(LayoutBuilder).first).width, 350);
  });

  testWidgets("unchanged widths during an animation skip every refresh", (
    tester,
  ) async {
    await tester.pumpWidget(h.build());
    await h.measureAndLeave(tester);
    final calls = h.estimateCalls;
    for (var width = 395.0; width >= 300; width -= 5) {
      await tester.pumpWidget(h.build(width: width));
    }
    await tester.pump();
    expect(h.stats.skippedResizeCount, 20);
    expect(h.stats.refreshCount, 0);
    expect(h.estimateCalls, calls);
    expect(h.list.extentForIndex(5), (50.0, false));
  });

  testWidgets("estimationKey + crossAxisLayoutKey together refresh once", (
    tester,
  ) async {
    await tester.pumpWidget(h.build(estimationKey: 1));
    await h.measureAndLeave(tester);
    await tester.pumpWidget(h.build(width: 250, estimationKey: 2));
    await tester.pump();
    await tester.pump();
    expect(h.stats.refreshCount, 1);
  });

  testWidgets("compat forwards the padded extent, including separators", (
    tester,
  ) async {
    final controller = compat.ItemScrollController();
    final keyWidths = <double>[];
    Widget build(double width) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 600,
          child: compat.ScrollablePositionedList.separated(
            itemScrollController: controller,
            itemCount: 500,
            padding: const EdgeInsets.symmetric(horizontal: 50),
            crossAxisLayoutKey: (width) {
              keyWidths.add(width);
              return math.min(width, 250);
            },
            itemBuilder: (_, index) => const SizedBox(height: 40),
            separatorBuilder: (_, index) => const SizedBox(height: 3),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(400));
    expect(keyWidths, [300]);
    controller.jumpTo(index: 300);
    await tester.pump();
    await tester.pump();
    final list = controller.listController!;
    expect(list.extentForIndex(1), (3.0, false));
    expect(list.extentForIndex(2), (40.0, false));

    await tester.pumpWidget(build(360));
    expect(keyWidths.last, 260);
    expect(list.extentForIndex(1), (3.0, false));
    expect(list.extentForIndex(2), (40.0, false));
    expect(list.estimateRefreshStats!.skippedResizeCount, 1);
    expect(list.estimateRefreshStats!.refreshCount, 0);
  });

  testWidgets("SuperListView forwards the key", (tester) async {
    final list = ListController();
    addTearDown(list.dispose);
    Widget build(double width) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 600,
          child: SuperListView.builder(
            listController: list,
            itemCount: 100,
            crossAxisLayoutKey: _column300,
            itemBuilder: (_, index) => const SizedBox(height: 40),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(400));
    await tester.pumpWidget(build(350));
    expect(list.estimateRefreshStats!.skippedResizeCount, 1);
    await tester.pumpWidget(build(200));
    await tester.pump();
    expect(list.estimateRefreshStats!.refreshCount, 1);
  });
}

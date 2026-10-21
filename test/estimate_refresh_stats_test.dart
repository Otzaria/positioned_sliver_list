import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

const _itemCount = 5000;

Widget _list({
  required ListController? controller,
  double width = 400,
  Object? estimationKey,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: 600,
      child: CustomScrollView(
        slivers: [
          SuperSliverList.builder(
            listController: controller,
            itemCount: _itemCount,
            estimationKey: estimationKey,
            extentEstimation: (index, crossAxis) =>
                index == null ? 0 : 40000 / crossAxis,
            itemBuilder: (_, index) => const SizedBox(height: 50),
          ),
        ],
      ),
    ),
  ),
);

void _refreshInEveryFrame() {
  final saved = SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh;
  SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh = false;
  addTearDown(
    () => SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh = saved,
  );
}

void main() {
  late ListController controller;
  setUp(() => controller = ListController());
  tearDown(() => controller.dispose());

  testWidgets("width change counts one refresh of all items", (tester) async {
    _refreshInEveryFrame();
    await tester.pumpWidget(_list(controller: controller));
    final before = controller.estimateRefreshStats!;
    expect(before.refreshCount, 0);

    await tester.pumpWidget(_list(controller: controller, width: 200));
    final after = controller.estimateRefreshStats!;
    expect(after.refreshCount, 1);
    expect(after.lastRefreshItemCount, _itemCount);
    expect(after.lastRefreshDuration.isNegative, isFalse);
    expect(after.indexRebuildCount, greaterThan(before.indexRebuildCount));

    await tester.pump();
    expect(controller.estimateRefreshStats!.refreshCount, 1);
  });

  testWidgets("deferred width change counts the settle refresh", (
    tester,
  ) async {
    await tester.pumpWidget(_list(controller: controller));
    await tester.pumpWidget(_list(controller: controller, width: 300));
    await tester.pumpWidget(_list(controller: controller, width: 200));
    var stats = controller.estimateRefreshStats!;
    expect(stats.deferredResizeCount, 2);
    expect(stats.refreshCount, 0);
    final estimated = controller.numberOfItemsWithEstimatedExtent;

    await tester.pump();
    stats = controller.estimateRefreshStats!;
    expect(stats.deferredResizeCount, 2);
    expect(stats.refreshCount, 1);
    expect(stats.lastRefreshItemCount, estimated);
    expect(stats.lastRefreshItemCount, lessThan(_itemCount));
  });

  testWidgets("estimationKey and invalidateAllExtents count refreshes", (
    tester,
  ) async {
    await tester.pumpWidget(_list(controller: controller, estimationKey: 1));
    await tester.pumpWidget(_list(controller: controller, estimationKey: 1));
    expect(controller.estimateRefreshStats!.refreshCount, 0);

    await tester.pumpWidget(_list(controller: controller, estimationKey: 2));
    expect(controller.estimateRefreshStats!.refreshCount, 1);

    controller.invalidateAllExtents();
    await tester.pump();
    final stats = controller.estimateRefreshStats!;
    expect(stats.refreshCount, 2);
    expect(stats.lastRefreshItemCount, _itemCount);
  });

  testWidgets("null when detached; survives controller re-attach", (
    tester,
  ) async {
    _refreshInEveryFrame();
    expect(controller.estimateRefreshStats, isNull);
    await tester.pumpWidget(_list(controller: controller));
    await tester.pumpWidget(_list(controller: controller, width: 300));
    final stats = controller.estimateRefreshStats!;
    expect(stats.refreshCount, 1);

    final other = ListController();
    addTearDown(other.dispose);
    await tester.pumpWidget(_list(controller: other, width: 300));
    expect(controller.estimateRefreshStats, isNull);
    expect(other.estimateRefreshStats, stats);

    await tester.pumpWidget(_list(controller: controller, width: 300));
    expect(controller.estimateRefreshStats, stats);
    expect(other.estimateRefreshStats, isNull);

    await tester.pumpWidget(const SizedBox());
    expect(controller.estimateRefreshStats, isNull);
  });

  testWidgets("timeline events are emitted in debug", (tester) async {
    _refreshInEveryFrame();
    await tester.pumpWidget(_list(controller: controller));
    FlutterTimeline.debugCollectionEnabled = true;
    addTearDown(() => FlutterTimeline.debugCollectionEnabled = false);

    await tester.pumpWidget(_list(controller: controller, width: 200));
    final timings = FlutterTimeline.debugCollect();
    expect(
      timings.getAggregated("PositionedSliverList.refreshEstimates").count,
      1,
    );
    expect(
      timings
          .getAggregated("PositionedSliverList.applyPendingEstimateUpdates")
          .count,
      1,
    );
    expect(
      timings.getAggregated("PositionedSliverList.rebuildOffsetIndex").count,
      greaterThanOrEqualTo(1),
    );
  }, skip: kReleaseMode);

  testWidgets("deferred refresh timeline events are emitted in debug", (
    tester,
  ) async {
    await tester.pumpWidget(_list(controller: controller));
    FlutterTimeline.debugCollectionEnabled = true;
    addTearDown(() => FlutterTimeline.debugCollectionEnabled = false);

    await tester.pumpWidget(_list(controller: controller, width: 200));
    await tester.pump();
    final timings = FlutterTimeline.debugCollect();
    expect(
      timings.getAggregated("PositionedSliverList.refreshEstimates").count,
      1,
    );
    expect(
      timings
          .getAggregated("PositionedSliverList.applyPendingEstimateUpdates")
          .count,
      1,
    );
  }, skip: kReleaseMode);

  test("value semantics", () {
    const a = EstimateRefreshStats(
      refreshCount: 1,
      lastRefreshItemCount: 2,
      lastRefreshDuration: Duration(microseconds: 3),
      deferredResizeCount: 7,
      skippedResizeCount: 6,
      indexRebuildCount: 4,
      lastIndexRebuildDuration: Duration(microseconds: 5),
    );
    const b = EstimateRefreshStats(
      refreshCount: 1,
      lastRefreshItemCount: 2,
      lastRefreshDuration: Duration(microseconds: 3),
      deferredResizeCount: 7,
      skippedResizeCount: 6,
      indexRebuildCount: 4,
      lastIndexRebuildDuration: Duration(microseconds: 5),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const EstimateRefreshStats()));
    expect(a.toString(), contains("refreshCount: 1"));
    expect(a.toString(), contains("skippedResizeCount: 6"));
    expect(a, isNot(const EstimateRefreshStats(skippedResizeCount: 6)));
    expect(a.toString(), contains("deferredResizeCount: 7"));
  });
}

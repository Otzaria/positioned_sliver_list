// Win 4: Batched build scope / layout callback for extent precalculation.
//
// Baseline pays one invokeLayoutCallback + one BuildOwner.buildScope per
// measured item during extent precalculation. The optimized variant wraps the
// entire per-frame measuring loop in a single layout callback and build
// scope, increasing items-measured-per-millisecond.
//
// The scenario builds a list with an always-precalculate policy and pumps
// frames until every extent has been measured. The layout budget per frame is
// time-based, so cheaper per-item overhead directly translates into fewer
// frames and less total wall time.
//
// Run with:
//   flutter test test/perf/win4_precalc_batch_measure_perf_test.dart
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

class _AlwaysPrecalculatePolicy extends ExtentPrecalculationPolicy {
  @override
  bool shouldPrecalculateExtents(ExtentPrecalculationContext context) => true;
}

void main() {
  testWidgets("Win 4: per-item vs batched extent precalculation",
      (tester) async {
    const itemCount = 6000;

    Future<double> scenario(bool batched) async {
      final saved = SuperSliverListPerfFlags.batchExtentPrecalculation;
      SuperSliverListPerfFlags.batchExtentPrecalculation = batched;
      final listController = ListController();
      final scrollController = ScrollController();
      final policy = _AlwaysPrecalculatePolicy();
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SuperListView.builder(
              controller: scrollController,
              listController: listController,
              extentPrecalculationPolicy: policy,
              itemCount: itemCount,
              // Cheapest possible item: measures per-item *overhead*
              // (buildScope + invokeLayoutCallback) rather than item cost.
              itemBuilder: (context, index) => SizedBox(
                height: 20.0 + (index * 7) % 40,
              ),
            ),
          ),
        );
        var frames = 0;
        while (listController.numberOfItemsWithEstimatedExtent > 0 &&
            frames < 2000) {
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
        }
        expect(listController.numberOfItemsWithEstimatedExtent, 0,
            reason: "extent precalculation did not finish within 2000 frames");
        final totalExtent = listController.totalExtent;
        // ignore: avoid_print
        print("      [${batched ? "batched" : "per-item"}] "
            "precalculated $itemCount items in $frames frames");
        await tester.pumpWidget(const SizedBox());
        return totalExtent;
      } finally {
        SuperSliverListPerfFlags.batchExtentPrecalculation = saved;
        scrollController.dispose();
        listController.dispose();
      }
    }

    final perf = PerfTester<int, double>(
      testName: "Win 4: extent precalculation batching",
      testCases: const [0],
      implementation1: (_) => scenario(false),
      implementation2: (_) => scenario(true),
      impl1Name: "per-item-scope",
      impl2Name: "batched-scope",
    );
    await perf.run(warmupRuns: 1, benchmarkRuns: 12);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

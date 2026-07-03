// Win 13: _shouldPrecalculateExtents work when the result is cached.
//
// Baseline performs the viewport ancestor walk and allocates an
// ExtentPrecalculationContext on every call, even though the result is
// cached per layout pass (`??=`). The method is called repeatedly per pass:
// per sliver for its own layout, once more for the pending-layout
// descriptor, and once per invisible sliver via
// _shouldSkipExtentPrecalculationForInvisibleList (which re-queries visible
// dirty slivers). The optimized variant skips all of it when the cached
// value exists.
//
// The scenario precalculates extents for 60 slivers (59 invisible) to
// completion.
//
// Run with:
//   flutter test test/perf/win13_precalc_check_cache_perf_test.dart
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

class _AlwaysPrecalculatePolicy extends ExtentPrecalculationPolicy {
  @override
  bool shouldPrecalculateExtents(ExtentPrecalculationContext context) => true;
}

void main() {
  testWidgets("Win 13: eager vs cached precalculation check", (tester) async {
    const sliverCount = 60;
    const itemsPerSliver = 60;

    Future<double> scenario(bool cached) async {
      final saved = SuperSliverListPerfFlags.cachedShouldPrecalculateExtents;
      SuperSliverListPerfFlags.cachedShouldPrecalculateExtents = cached;
      final scrollController = ScrollController();
      final policy = _AlwaysPrecalculatePolicy();
      final listControllers =
          List.generate(sliverCount, (_) => ListController());
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                for (var s = 0; s < sliverCount; s++)
                  SuperSliverList.builder(
                    listController: listControllers[s],
                    extentPrecalculationPolicy: policy,
                    itemCount: itemsPerSliver,
                    itemBuilder: (context, index) =>
                        SizedBox(height: 20.0 + (index * 7) % 40),
                  ),
              ],
            ),
          ),
        );
        var frames = 0;
        bool anyEstimated() => listControllers
            .any((c) => c.numberOfItemsWithEstimatedExtent > 0);
        while (anyEstimated() && frames < 3000) {
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
        }
        expect(anyEstimated(), isFalse,
            reason: "precalculation did not finish within 3000 frames");
        var checksum = 0.0;
        for (final c in listControllers) {
          checksum += c.totalExtent;
        }
        await tester.pumpWidget(const SizedBox());
        return checksum;
      } finally {
        SuperSliverListPerfFlags.cachedShouldPrecalculateExtents = saved;
        scrollController.dispose();
        for (final c in listControllers) {
          c.dispose();
        }
      }
    }

    final perf = PerfTester<int, double>(
      testName: "Win 13: precalculation check caching",
      testCases: const [0],
      implementation1: (_) => scenario(false),
      implementation2: (_) => scenario(true),
      impl1Name: "eager-context",
      impl2Name: "cached",
    );
    await perf.run(warmupRuns: 1, benchmarkRuns: 8);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

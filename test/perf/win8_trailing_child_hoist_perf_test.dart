// Win 8: Hoisted childScrollOffset/paintExtentOf in addTrailingChild.
//
// Baseline computes `childScrollOffset(lastChild) + paintExtentOf(lastChild)`
// twice per inserted trailing child (once for the guard, once for the new
// layout offset). The optimized variant computes it once. Constant-factor
// win on the cache-filling hot path.
//
// Run with:
//   flutter test test/perf/win8_trailing_child_hoist_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";
import "widget_scenarios.dart";

void main() {
  testWidgets("Win 8: duplicated vs hoisted trailing-edge computation",
      (tester) async {
    Future<double> scenario(ScrollScenario s, bool hoisted) async {
      final saved = SuperSliverListPerfFlags.hoistTrailingChildValues;
      SuperSliverListPerfFlags.hoistTrailingChildValues = hoisted;
      try {
        return await runForwardJumpScenario(tester, s);
      } finally {
        SuperSliverListPerfFlags.hoistTrailingChildValues = saved;
      }
    }

    final perf = PerfTester<ScrollScenario, double>(
      testName: "Win 8: addTrailingChild value hoisting",
      testCases: const [
        // Cache refilled from scratch every pump; ~2000 trailing inserts.
        ScrollScenario(
          name: "large-cache",
          itemCount: 15000,
          cacheExtent: 12000,
          step: 30000,
          steps: 5,
          heightBase: 8,
          heightSpread: 10,
        ),
      ],
      implementation1: (s) => scenario(s, false),
      implementation2: (s) => scenario(s, true),
      impl1Name: "recompute",
      impl2Name: "hoisted",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 12);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

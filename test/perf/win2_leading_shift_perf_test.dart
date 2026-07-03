// Win 2: Batched layout-offset shifting when inserting leading children.
//
// Baseline shifts the layout offset of *all* subsequent children once per
// inserted leading child (O(k·n) per layout). The optimized variant places
// leading children top-down using actual extents and applies the accumulated
// correction in a single O(n) pass.
//
// The scenario scrolls upward in steps smaller than the cache area, so each
// pump inserts dozens of leading children while hundreds of live children
// below them are subject to shifting.
//
// Run with:
//   flutter test test/perf/win2_leading_shift_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";
import "widget_scenarios.dart";

void main() {
  testWidgets("Win 2: per-insert shift vs batched shift", (tester) async {
    Future<double> scenario(ScrollScenario s, bool batched) async {
      final saved = SuperSliverListPerfFlags.batchLeadingChildShift;
      SuperSliverListPerfFlags.batchLeadingChildShift = batched;
      try {
        return await runUpwardScrollScenario(tester, s);
      } finally {
        SuperSliverListPerfFlags.batchLeadingChildShift = saved;
      }
    }

    final perf = PerfTester<ScrollScenario, double>(
      testName: "Win 2: leading children shift batching",
      testCases: const [
        // Realistic cache area (~430 live children, ~50 inserts per pump).
        ScrollScenario(
          name: "moderate-cache",
          itemCount: 8000,
          cacheExtent: 6000,
          step: 1500,
          steps: 30,
        ),
        // Large cache with small items (~3300 live children, ~120 inserts
        // per pump) - the O(k*n) shifting becomes dominant.
        ScrollScenario(
          name: "large-cache",
          itemCount: 8000,
          cacheExtent: 20000,
          step: 1500,
          steps: 30,
          heightBase: 8,
          heightSpread: 10,
        ),
      ],
      implementation1: (s) => scenario(s, false),
      implementation2: (s) => scenario(s, true),
      impl1Name: "per-insert-shift",
      impl2Name: "batched-shift",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 10);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

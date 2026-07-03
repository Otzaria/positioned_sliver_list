// Win 1: O(1) membership check in RenderSuperSliverList.childScrollOffset.
//
// Baseline scans the live child list linearly on every childScrollOffset
// call. The method is invoked from O(n) layout loops (cache filling via
// addTrailingChild, leading-children fill, estimation correction), giving
// O(n²) behavior in the number of live children. The optimized variant uses
// an O(1) parent/keptAlive check.
//
// The scenario uses small items and a large cache extent (many live
// children) and jumps beyond the cache area every pump so the whole child
// population is rebuilt each frame — the worst case for the scan.
//
// Run with:
//   flutter test test/perf/win1_child_scroll_offset_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";
import "widget_scenarios.dart";

void main() {
  testWidgets("Win 1: childScrollOffset linear scan vs O(1) check",
      (tester) async {
    Future<double> scenario(ScrollScenario s, bool fastLookup) async {
      final saved = SuperSliverListPerfFlags.fastChildScrollOffsetLookup;
      SuperSliverListPerfFlags.fastChildScrollOffsetLookup = fastLookup;
      try {
        return await runForwardJumpScenario(tester, s);
      } finally {
        SuperSliverListPerfFlags.fastChildScrollOffsetLookup = saved;
      }
    }

    final perf = PerfTester<ScrollScenario, double>(
      testName: "Win 1: childScrollOffset membership check",
      testCases: const [
        // Realistic cache area (~230 live children).
        ScrollScenario(
          name: "moderate-cache",
          itemCount: 10000,
          cacheExtent: 3000,
          step: 12000,
          steps: 14,
        ),
        // Large cache area with small items (~2000 live children) - the
        // quadratic scan cost becomes dominant.
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
      impl1Name: "linear-scan",
      impl2Name: "O(1)-check",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 12);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

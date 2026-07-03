// Win 5: Lazy `_firstWholeVisibleChild` lookup.
//
// Baseline walks all leading cache-area children on *every* layout to find
// the first wholly visible child, but the result is only consumed while the
// cross axis is resizing. The optimized variant skips the walk unless the
// cross axis actually resized.
//
// The scenario scrolls forward in small steps with a large cache area and
// small items, so each layout pass walks ~1600 leading cache children in the
// baseline.
//
// Run with:
//   flutter test test/perf/win5_first_visible_walk_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";
import "widget_scenarios.dart";

void main() {
  testWidgets("Win 5: eager vs lazy first-visible-child walk", (tester) async {
    Future<double> scenario(ScrollScenario s, bool lazy) async {
      final saved = SuperSliverListPerfFlags.lazyFirstVisibleChild;
      SuperSliverListPerfFlags.lazyFirstVisibleChild = lazy;
      try {
        return await runForwardStepScenario(tester, s);
      } finally {
        SuperSliverListPerfFlags.lazyFirstVisibleChild = saved;
      }
    }

    final perf = PerfTester<ScrollScenario, double>(
      testName: "Win 5: first-visible-child walk",
      testCases: const [
        ScrollScenario(
          name: "large-cache-small-steps",
          itemCount: 8000,
          cacheExtent: 20000,
          step: 800,
          steps: 40,
          heightBase: 8,
          heightSpread: 10,
        ),
      ],
      implementation1: (s) => scenario(s, false),
      implementation2: (s) => scenario(s, true),
      impl1Name: "eager-walk",
      impl2Name: "lazy-walk",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 10);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

// Win 16: Defer the estimate refresh while the width keeps changing.
//
// Baseline refreshes the estimates of all 190,760 items and rebuilds the
// offset index in every frame of a width animation. The optimized variant
// keeps the previous extents, marked as estimated, while the width changes
// and re-estimates only the items not measured at the final width once it
// settles.
//
// The widget scenario jumps to item 95,000 of wrapped text items, animates
// the width from 900 to 600 pixels in 30 frames and settles for 2 frames. The
// checksum is the anchor, the scroll pixels and the total extent after the
// settle. The micro benchmark compares the per-frame work on the extent list
// alone: marking all items estimated versus refreshing them and querying an
// offset.
//
// Run with:
//   flutter test --tags perf test/perf/win16_deferred_width_refresh_perf_test.dart
@Tags(["perf"])
library;

import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";
import "package:positioned_sliver_list/src/extent_list.dart";

import "perf_tester.dart";
import "resize_scenarios.dart";

const _items = 190760;
const _frames = 30;

void main() {
  testWidgets("Win 16: refresh every frame vs deferred refresh", (
    tester,
  ) async {
    final saved = SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh;
    Future<ResizeResult> scenario(String name, {required bool defer}) async {
      SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh = defer;
      try {
        return await runResizeScenario(
          tester,
          name: name,
          from: 900,
          to: 600,
          frames: _frames,
        );
      } finally {
        SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh = saved;
      }
    }

    final perf = PerfTester<int, ResizeResult>.multi(
      testName: "Win 16: deferred width refresh ($_items items)",
      testCases: const [0],
      implementations: [
        PerfImpl("same-frame", (_) => scenario("same-frame", defer: false)),
        PerfImpl("deferred", (_) => scenario("deferred", defer: true)),
      ],
      equalityCheck: (a, b) => a!.matches(b!),
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 8);
    for (final name in ["same-frame", "deferred"]) {
      // ignore: avoid_print
      print(describeTimes(name));
    }
  }, timeout: const Timeout(Duration(minutes: 20)));

  test("Win 16 micro: refresh per frame vs mark estimated", () async {
    double run({required bool defer}) {
      final list = ExtentList();
      list.resize(_items, (index) => index == null ? 0 : 40.0 + index % 7);
      final checksum = list.offsetForIndex(_items ~/ 2);
      for (var frame = 0; frame < _frames; frame++) {
        final base = 30.0 + frame % 5;
        double estimate(int? index) => index == null ? 0 : base + index % 3;
        if (defer) {
          list.markAllDirty();
        } else {
          list.refreshEstimates(estimate);
        }
        // The offset query of every layout; its value differs on purpose.
        list.offsetForIndex(_items ~/ 2 - frame);
      }
      list.refreshDirtyEstimates((index) => index == null ? 0 : 34.0);
      return checksum + list.offsetForIndex(_items - 1);
    }

    final perf = PerfTester<int, double>(
      testName: "Win 16 micro: $_frames frames on $_items extents",
      testCases: const [0],
      implementation1: (_) => run(defer: false),
      implementation2: (_) => run(defer: true),
      impl1Name: "refresh",
      impl2Name: "mark-estimated",
    );
    await perf.run(warmupRuns: 3, benchmarkRuns: 15);
  });
}

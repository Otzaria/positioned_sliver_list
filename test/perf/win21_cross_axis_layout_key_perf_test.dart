// Win 21: `crossAxisLayoutKey` skips refreshes for width changes that cannot
// change item extents.
//
// Items are wrapped text in a column at most 800 pixels wide, and the
// estimator depends on the width only through that column. Without a key,
// every frame of a width animation from 1000 to 900 pixels refreshes all
// 190,760 estimates and rebuilds the offset index. With
// `crossAxisLayoutKey: (w) => min(w, 800)` the key never changes, so measured
// extents and estimates are kept and only the live items are laid out again.
//
// The checksum is the anchor and the visible item positions after the width
// settles; the total extent differs on purpose, as measured extents outside
// the live items are kept with the key.
//
// Run with:
//   flutter test --tags perf test/perf/win21_cross_axis_layout_key_perf_test.dart
@Tags(["perf"])
library;

import "dart:math" as math;

import "package:flutter_test/flutter_test.dart";

import "perf_tester.dart";
import "resize_scenarios.dart";

const _column = 800.0;

void main() {
  testWidgets("Win 21: no key vs crossAxisLayoutKey", (tester) async {
    Future<ResizeResult> scenario(String name, {required bool key}) =>
        runResizeScenario(
          tester,
          name: name,
          from: 1000,
          to: 900,
          frames: 20,
          maxColumnWidth: _column,
          crossAxisLayoutKey: key ? (w) => math.min(w, _column) : null,
        );

    final perf = PerfTester<int, ResizeResult>(
      testName: "Win 21: crossAxisLayoutKey (190,760 items)",
      testCases: const [0],
      implementation1: (_) => scenario("no-key", key: false),
      implementation2: (_) => scenario("key", key: true),
      impl1Name: "no-key",
      impl2Name: "key",
      equalityCheck: (a, b) => a!.matches(b!, compareExtent: false),
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 8);
    // ignore: avoid_print
    print(describeTimes("no-key"));
    // ignore: avoid_print
    print(describeTimes("key"));
  }, timeout: const Timeout(Duration(minutes: 20)));
}

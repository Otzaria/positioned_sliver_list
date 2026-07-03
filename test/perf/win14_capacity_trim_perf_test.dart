// Win 14: Capacity-trim hysteresis in ResizableFloat64List.
//
// Baseline trims backing-store capacity as soon as capacity/2 >= length,
// trimming to exactly `length` at a power-of-two boundary; the next insert
// doubles capacity again. One remove+insert cycle at the boundary therefore
// causes two full O(n) copies. The optimized variant requires
// capacity/4 >= length before trimming (hysteresis with ~2x headroom).
//
// The scenario oscillates an ExtentList of ~16k items across the boundary,
// as a chat app hovering at a capacity boundary would (each message added /
// pruned crossing it).
//
// Run with:
//   flutter test test/perf/win14_capacity_trim_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/src/extent_list.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

// One above a power of two, so removing a single item hits the trim
// condition and re-adding it forces a re-grow.
const _boundary = 16385;
const _cycles = 4000;

enum _Mode { insertRemove, resize }

double _run(_Mode mode, {required bool hysteresis}) {
  final saved = SuperSliverListPerfFlags.trimHysteresis;
  SuperSliverListPerfFlags.trimHysteresis = hysteresis;
  try {
    final list = ExtentList();
    list.resize(_boundary, (_) => 100.0);
    switch (mode) {
      case _Mode.insertRemove:
        for (var i = 0; i < _cycles; i++) {
          list.removeAt(list.length - 1);
          list.insertAt(list.length, (_) => 100.0);
        }
      case _Mode.resize:
        for (var i = 0; i < _cycles; i++) {
          list.resize(_boundary - 1, (_) => 100.0);
          list.resize(_boundary, (_) => 100.0);
        }
    }
    return list.totalExtent + list.length + list.dirtyItemCount;
  } finally {
    SuperSliverListPerfFlags.trimHysteresis = saved;
  }
}

void main() {
  test("Win 14: trim thrash vs hysteresis", () async {
    final perf = PerfTester<_Mode, double>(
      testName: "Win 14: capacity trim at power-of-two boundary",
      testCases: _Mode.values,
      implementation1: (m) => _run(m, hysteresis: false),
      implementation2: (m) => _run(m, hysteresis: true),
      impl1Name: "trim-at-half",
      impl2Name: "hysteresis",
    );
    await perf.run(warmupRuns: 3, benchmarkRuns: 15);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

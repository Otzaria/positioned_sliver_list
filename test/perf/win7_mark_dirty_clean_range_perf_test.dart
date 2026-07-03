// Win 7: markDirty preserves (part of) the tracked clean range.
//
// Baseline discards the entire tracked clean range when any single item is
// invalidated; the next setExtent re-anchors the range to one index and the
// lazy getters re-walk the whole clean span (O(n)). The optimized variant
// only shrinks the range to exclude the dirtied index.
//
// The scenario mirrors a streaming chat: a fully measured list where an item
// near the end is repeatedly invalidated (listController.invalidateExtent)
// and re-measured, with the clean-range getters read in between (as layout
// does every frame).
//
// Run with:
//   flutter test test/perf/win7_mark_dirty_clean_range_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/src/extent_list.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

double _extentFor(int index) => 40.0 + (index * 13) % 80;

class _Scenario {
  const _Scenario(this.itemCount, this.iterations);
  final int itemCount;
  final int iterations;

  @override
  String toString() => "items=$itemCount iterations=$iterations";
}

double _run(_Scenario s, {required bool preserve}) {
  final saved = SuperSliverListPerfFlags.preserveCleanRangeOnMarkDirty;
  SuperSliverListPerfFlags.preserveCleanRangeOnMarkDirty = preserve;
  try {
    final n = s.itemCount;
    final list = ExtentList();
    list.resize(n, (_) => 100.0);
    for (var i = 0; i < n; i++) {
      list.setExtent(i, _extentFor(i));
    }
    // Fully expanded clean range.
    var probe = (list.cleanRangeStart ?? -1) + (list.cleanRangeEnd ?? -1);

    var checksum = 0.0;
    for (var i = 0; i < s.iterations; i++) {
      // Invalidate an item near the end (streaming item growing).
      final index = n - 1 - (i % 50);
      list.markDirty(index);
      // Layout reads the clean range every frame. The returned values differ
      // between the two strategies (both are valid clean sub-ranges), so they
      // feed `probe` (cost only), not the verified checksum.
      probe += (list.cleanRangeStart ?? -1) + (list.cleanRangeEnd ?? -1);
      // Item is re-measured.
      list.setExtent(index, _extentFor(index));
      probe += (list.cleanRangeStart ?? -1) + (list.cleanRangeEnd ?? -1);
      checksum += list.totalExtent;
    }
    // Keep `probe` alive without affecting output equality.
    if (probe.isNaN) {
      checksum = double.negativeInfinity;
    }
    return checksum + list.dirtyItemCount;
  } finally {
    SuperSliverListPerfFlags.preserveCleanRangeOnMarkDirty = saved;
  }
}

void main() {
  test("Win 7: markDirty range discard vs preservation", () async {
    final perf = PerfTester<_Scenario, double>(
      testName: "Win 7: clean range across invalidations",
      testCases: const [
        _Scenario(20000, 1000),
        _Scenario(100000, 300),
      ],
      implementation1: (s) => _run(s, preserve: false),
      implementation2: (s) => _run(s, preserve: true),
      impl1Name: "discard-range",
      impl2Name: "preserve-range",
    );
    await perf.run(warmupRuns: 5, benchmarkRuns: 20);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

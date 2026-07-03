// Win 6: Incremental clean-range maintenance in ExtentList.setExtent.
//
// Baseline resets the tracked clean range to a single index on every
// setExtent, forcing the lazy clean-range getters to re-walk the entire
// clean span (O(n) per measured item, O(n²) for a full extent
// precalculation). The optimized variant extends the tracked range when the
// cleaned index is inside or adjacent to it.
//
// The scenario replicates the extent-precalculation loop in
// RenderSuperSliverList._calculatePendingLayout: repeatedly read
// cleanRangeStart/cleanRangeEnd and clean the items just outside the range.
//
// Run with:
//   flutter test test/perf/win6_clean_range_extend_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/src/extent_list.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

double _extentFor(int index) => 40.0 + (index * 13) % 80;

double _run(int n, {required bool incremental}) {
  final saved = SuperSliverListPerfFlags.incrementalCleanRange;
  SuperSliverListPerfFlags.incrementalCleanRange = incremental;
  try {
    final list = ExtentList();
    list.resize(n, (_) => 100.0);
    // Seed the clean range in the middle of the list, like the first laid
    // out visible item would.
    final mid = n ~/ 2;
    list.setExtent(mid, _extentFor(mid));

    var checksum = 0.0;
    // Precalculation loop (mirrors _calculatePendingLayout).
    while (list.hasDirtyItems) {
      final start = list.cleanRangeStart!;
      final end = list.cleanRangeEnd!;
      checksum += start + end;
      if (start > 0) {
        list.setExtent(start - 1, _extentFor(start - 1));
      }
      if (end < n - 1) {
        list.setExtent(end + 1, _extentFor(end + 1));
      }
    }
    return checksum + list.totalExtent;
  } finally {
    SuperSliverListPerfFlags.incrementalCleanRange = saved;
  }
}

void main() {
  test("Win 6: clean-range reset vs incremental extension", () async {
    final perf = PerfTester<int, double>(
      testName: "Win 6: clean-range maintenance during precalculation",
      testCases: const [2000, 10000],
      implementation1: (n) => _run(n, incremental: false),
      implementation2: (n) => _run(n, incremental: true),
      impl1Name: "reset-O(n)",
      impl2Name: "incremental",
    );
    await perf.run(warmupRuns: 5, benchmarkRuns: 20);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

// Win 3: Incremental Fenwick tree maintenance.
//
// Baseline discards the Fenwick tree whenever the item count changes, forcing
// an O(n) rebuild on the next offset/index query. The optimized variant
// appends incrementally (O(log n)) and truncates in O(1), which matters for
// chat-style lists that append an item (and query offsets) every frame.
//
// Run with:
//   flutter test test/perf/win3_fenwick_append_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/src/extent_list.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

class _Scenario {
  const _Scenario({
    required this.initialCount,
    required this.appendCount,
    required this.removeCount,
  });

  final int initialCount;
  final int appendCount;
  final int removeCount;

  @override
  String toString() =>
      "initial=$initialCount appends=$appendCount removes=$removeCount";
}

/// Integer-valued extents keep all double arithmetic exact, so baseline and
/// optimized implementations produce bit-identical results.
double _extentFor(int index) => 40.0 + (index * 13) % 80;

double _run(_Scenario s, {required bool incremental}) {
  final saved = SuperSliverListPerfFlags.incrementalFenwick;
  SuperSliverListPerfFlags.incrementalFenwick = incremental;
  try {
    final list = ExtentList();
    list.resize(s.initialCount, (index) => 100.0);
    for (var i = 0; i < s.initialCount; i++) {
      list.setExtent(i, _extentFor(i));
    }
    // Build the tree once, like a settled layout would have.
    var checksum = list.offsetForIndex(list.length - 1);

    // Chat simulation: append one item per "frame", then run the queries a
    // layout pass performs (offsetForIndex + indexForOffset).
    for (var j = 0; j < s.appendCount; j++) {
      final n = list.length;
      list.resize(n + 1, (index) => 90.0);
      list.setExtent(n, _extentFor(n));
      checksum += list.offsetForIndex(n);
      final probe = checksum % list.totalExtent;
      checksum += (list.indexForOffset(probe) ?? -1).toDouble();
    }

    // Trailing removals (O(1) truncate vs full rebuild).
    for (var j = 0; j < s.removeCount; j++) {
      list.removeAt(list.length - 1);
      checksum += list.offsetForIndex(list.length - 1);
    }
    return checksum;
  } finally {
    SuperSliverListPerfFlags.incrementalFenwick = saved;
  }
}

void main() {
  test("Win 3: incremental Fenwick append/truncate vs full rebuild", () async {
    final perf = PerfTester<_Scenario, double>(
      testName: "Win 3: Fenwick maintenance on item count changes",
      testCases: const [
        _Scenario(initialCount: 5000, appendCount: 300, removeCount: 50),
        _Scenario(initialCount: 50000, appendCount: 300, removeCount: 50),
      ],
      implementation1: (s) => _run(s, incremental: false),
      implementation2: (s) => _run(s, incremental: true),
      impl1Name: "rebuild-O(n)",
      impl2Name: "incremental",
    );
    await perf.run(warmupRuns: 10, benchmarkRuns: 50);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

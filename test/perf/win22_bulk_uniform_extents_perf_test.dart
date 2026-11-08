// Win 22: Bulk fills of uniform item extents.
//
// Run with:
//   flutter test --tags perf test/perf/win22_bulk_uniform_extents_perf_test.dart
@Tags(["perf"])
library;

import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/src/extent_list.dart";
import "package:positioned_sliver_list/src/perf_flags.dart";

import "perf_tester.dart";

const _sizes = [190760, 1000000];

// Reuse the same list so the refresh case measures the per-item work rather
// than initial allocation or growth. The old and new implementations each
// receive their own backing buffer.
final _refreshLists = <(bool, int), ExtentList>{};

double _refresh(int size, {required bool optimized}) {
  final previous = SuperSliverListPerfFlags.bulkUniformExtentFill;
  SuperSliverListPerfFlags.bulkUniformExtentFill = optimized;
  try {
    final list = _refreshLists.putIfAbsent((optimized, size), () {
      final value = ExtentList();
      value.resize(size, (_) => 30.0);
      return value;
    });
    list.refreshEstimates((index) {
      if (index == null) return 40.0;
      throw StateError("A uniform estimate must not request per-item extents");
    });
    return list.totalExtent;
  } finally {
    SuperSliverListPerfFlags.bulkUniformExtentFill = previous;
  }
}

double _resize(int size, {required bool optimized}) {
  final previous = SuperSliverListPerfFlags.bulkUniformExtentFill;
  SuperSliverListPerfFlags.bulkUniformExtentFill = optimized;
  try {
    final list = ResizableFloat64List();
    list.resizeWithDefault(size, 40.0);
    return list[0] + list[size - 1] + list.length;
  } finally {
    SuperSliverListPerfFlags.bulkUniformExtentFill = previous;
  }
}

void main() {
  test("Win 22: bulk vs element-wise uniform estimate refresh", () async {
    final perf = PerfTester<int, double>(
      testName: "Win 22: uniform estimate refresh",
      testCases: _sizes,
      implementation1: (n) => _refresh(n, optimized: false),
      implementation2: (n) => _refresh(n, optimized: true),
      impl1Name: "element-wise",
      impl2Name: "typed-data fillRange",
    );
    await perf.run(warmupRuns: 3, benchmarkRuns: 15);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test("Win 22: bulk vs element-wise uniform list growth", () async {
    final perf = PerfTester<int, double>(
      testName: "Win 22: uniform list growth",
      testCases: _sizes,
      implementation1: (n) => _resize(n, optimized: false),
      implementation2: (n) => _resize(n, optimized: true),
      impl1Name: "element-wise",
      impl2Name: "typed-data fillRange",
    );
    await perf.run(warmupRuns: 3, benchmarkRuns: 15);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

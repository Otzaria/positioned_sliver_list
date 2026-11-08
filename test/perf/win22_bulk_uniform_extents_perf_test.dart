// Win 22: Bulk refresh of uniform item extent estimates.
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

// Each variant owns a stable buffer. Benchmark the refresh, not allocation.
final _refreshLists = <(bool, int), ExtentList>{};

void _prepareLists() {
  for (final optimized in [false, true]) {
    for (final size in _sizes) {
      final list = ExtentList();
      list.resize(size, (_) => 30.0);
      _refreshLists[(optimized, size)] = list;
    }
  }
}

double _refresh(int size, {required bool optimized}) {
  final previous = SuperSliverListPerfFlags.bulkUniformExtentFill;
  SuperSliverListPerfFlags.bulkUniformExtentFill = optimized;
  try {
    final list = _refreshLists[(optimized, size)]!;
    list.refreshEstimates((index) {
      if (index == null) return 40.0;
      throw StateError("A uniform estimate must not request per-item extents");
    });
    return list.totalExtent;
  } finally {
    SuperSliverListPerfFlags.bulkUniformExtentFill = previous;
  }
}

void main() {
  setUpAll(_prepareLists);

  // Report each size independently so a large case cannot hide a regression.
  for (final size in _sizes) {
    test("Win 22: uniform estimate refresh ($size items)", () async {
      expect(_refresh(size, optimized: false), _refresh(size, optimized: true));
      final perf = PerfTester<int, double>(
        testName: "Win 22: uniform estimate refresh ($size)",
        testCases: [size],
        implementation1: (n) => _refresh(n, optimized: false),
        implementation2: (n) => _refresh(n, optimized: true),
        impl1Name: "element-wise",
        impl2Name: "typed-data fillRange",
      );
      await perf.run(warmupRuns: 5, benchmarkRuns: 25);
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}

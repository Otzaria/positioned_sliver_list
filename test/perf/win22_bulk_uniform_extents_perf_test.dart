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

// Each variant owns a stable buffer. This keeps allocation and growth
// strategies from obscuring the cost of the uniform write being measured.
final _refreshLists = <(bool, int), ExtentList>{};
final _resizeLists = <(bool, int), ResizableFloat64List>{};

void _prepareLists() {
  for (final optimized in [false, true]) {
    for (final size in _sizes) {
      final extentList = ExtentList();
      extentList.resize(size, (_) => 30.0);
      _refreshLists[(optimized, size)] = extentList;

      final list = ResizableFloat64List();
      list.resizeWithDefault(size, 20.0);
      _resizeLists[(optimized, size)] = list;
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

double _resize(int size, {required bool optimized}) {
  final previous = SuperSliverListPerfFlags.bulkUniformExtentFill;
  SuperSliverListPerfFlags.bulkUniformExtentFill = optimized;
  try {
    final list = _resizeLists[(optimized, size)]!;
    // Shrink without releasing capacity, then refill the final quarter.
    // Avoids charging either implementation for a fresh Float64List
    // allocation on every measurement.
    final start = size * 3 ~/ 4;
    list.resizeWithDefault(start, 20.0);
    list.resizeWithDefault(size, 40.0);
    return list[start - 1] + list[start] + list[size - 1] + list.length;
  } finally {
    SuperSliverListPerfFlags.bulkUniformExtentFill = previous;
  }
}

void main() {
  setUpAll(_prepareLists);

  // Report timings by size: a 1m-item case must not hide a 190k regression.
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

    test("Win 22: uniform list growth ($size items)", () async {
      expect(_resize(size, optimized: false), _resize(size, optimized: true));
      final perf = PerfTester<int, double>(
        testName: "Win 22: uniform list growth ($size)",
        testCases: [size],
        implementation1: (n) => _resize(n, optimized: false),
        implementation2: (n) => _resize(n, optimized: true),
        impl1Name: "element-wise",
        impl2Name: "typed-data fillRange",
      );
      await perf.run(warmupRuns: 5, benchmarkRuns: 25);
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}

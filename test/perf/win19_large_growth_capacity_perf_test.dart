// Win 19: Near-exact growth for large resizes of ResizableFloat64List.
//
// Baseline doubles capacity until it fits, so the first resize to n items
// reserves the next power of two: up to twice the memory needed. The
// optimized variant reserves n + n/16 when the growth is more than 2x.
//
// Run with:
//   flutter test --tags perf test/perf/win19_large_growth_capacity_perf_test.dart
@Tags(["perf"])
library;

import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";
import "package:positioned_sliver_list/src/extent_list.dart";

import "perf_tester.dart";

const _sizes = [131073, 190760, 1000001];

final _capacities = <(bool, int), int>{};

double _run(int size, {required bool nearExact}) {
  final saved = SuperSliverListPerfFlags.nearExactLargeGrowth;
  SuperSliverListPerfFlags.nearExactLargeGrowth = nearExact;
  try {
    final list = ExtentList();
    list.resize(size, (index) => index == null ? 0 : 40.0 + index % 7);
    // A few appends after the first resize, as streaming content would add.
    for (var i = 0; i < 100; i++) {
      list.insertAt(list.length, (_) => 50.0);
    }
    _capacities[(nearExact, size)] = list.debugCapacity;
    return list.totalExtent +
        list.offsetForIndex(list.length - 1) +
        list.dirtyItemCount;
  } finally {
    SuperSliverListPerfFlags.nearExactLargeGrowth = saved;
  }
}

void main() {
  test("Win 19: power-of-two vs near-exact large growth", () async {
    final perf = PerfTester<int, double>(
      testName: "Win 19: capacity of a large first resize",
      testCases: _sizes,
      implementation1: (n) => _run(n, nearExact: false),
      implementation2: (n) => _run(n, nearExact: true),
      impl1Name: "power-of-two",
      impl2Name: "near-exact",
    );
    await perf.run(warmupRuns: 3, benchmarkRuns: 20);
    for (final size in _sizes) {
      double mb(bool nearExact) => _capacities[(nearExact, size)]! * 8 / 1e6;
      // ignore: avoid_print
      print(
        "Win 19 n=$size: extents capacity "
        "${_capacities[(false, size)]} (${mb(false).toStringAsFixed(2)} MB) -> "
        "${_capacities[(true, size)]} (${mb(true).toStringAsFixed(2)} MB)",
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

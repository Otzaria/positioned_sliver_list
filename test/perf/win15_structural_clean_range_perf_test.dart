// Win 15: Clean range preserved across insertAt/removeAt.
//
// Baseline discards the tracked clean range on every structural change, even
// for a pure append where it remains valid. The precalculation anchor is
// lost, and once the next measured item re-anchors it, the lazy getters must
// re-walk the entire clean span - O(n) per appended message in a streaming
// chat. The optimized variant shifts/clips the range instead.
//
// The scenario simulates a fully measured chat list receiving appended
// messages: append -> layout reads the clean range -> new item measured ->
// clean range read again.
//
// Run with:
//   flutter test test/perf/win15_structural_clean_range_perf_test.dart
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/src/extent_list.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

double _extentFor(int index) => 40.0 + (index * 13) % 80;

class _Scenario {
  const _Scenario(this.itemCount, this.appends);
  final int itemCount;
  final int appends;

  @override
  String toString() => "items=$itemCount appends=$appends";
}

double _run(_Scenario s, {required bool preserve}) {
  final saved = SuperSliverListPerfFlags.preserveCleanRangeOnStructuralChange;
  SuperSliverListPerfFlags.preserveCleanRangeOnStructuralChange = preserve;
  try {
    final list = ExtentList();
    list.resize(s.itemCount, (_) => 100.0);
    for (var i = 0; i < s.itemCount; i++) {
      list.setExtent(i, _extentFor(i));
    }
    // Fully expanded clean range.
    var probe = (list.cleanRangeStart ?? -1) + (list.cleanRangeEnd ?? -1);

    var checksum = 0.0;
    for (var i = 0; i < s.appends; i++) {
      // New message arrives.
      list.insertAt(list.length, (_) => 100.0);
      // Layout reads the clean range (values differ between strategies right
      // after the append - null vs preserved - so this feeds the cost-only
      // probe, not the verified checksum).
      probe += (list.cleanRangeStart ?? -1) + (list.cleanRangeEnd ?? -1);
      // The new message gets measured...
      final index = list.length - 1;
      list.setExtent(index, _extentFor(index));
      // ...and the next layout reads the clean range again. At this point
      // both strategies report the same maximal range.
      checksum += list.cleanRangeStart! + list.cleanRangeEnd!;
    }
    if (probe.isNaN) {
      checksum = double.negativeInfinity; // keep `probe` alive
    }
    return checksum + list.totalExtent + list.dirtyItemCount;
  } finally {
    SuperSliverListPerfFlags.preserveCleanRangeOnStructuralChange = saved;
  }
}

void main() {
  test("Win 15: clean range across appends", () async {
    final perf = PerfTester<_Scenario, double>(
      testName: "Win 15: structural clean-range preservation",
      testCases: const [
        _Scenario(20000, 1000),
        _Scenario(100000, 200),
      ],
      implementation1: (s) => _run(s, preserve: false),
      implementation2: (s) => _run(s, preserve: true),
      impl1Name: "discard-range",
      impl2Name: "preserve-range",
    );
    await perf.run(warmupRuns: 3, benchmarkRuns: 15);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

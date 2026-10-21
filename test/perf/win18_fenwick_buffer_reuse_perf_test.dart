// Win 18: Reuse the Fenwick tree's backing store on full rebuilds.
//
// Baseline allocates a new Float64List(n + 1) every time the tree is rebuilt
// after an estimate refresh or a middle insertion. The optimized variant
// refills the previous buffer in place.
//
// Each scenario runs 200 operations on a list of 190,760 items, each
// followed by the offsetForIndex query of the next layout. The checksum is
// the sum of the queried offsets; integer extents keep it exact.
//
// Run with:
//   flutter test --tags perf test/perf/win18_fenwick_buffer_reuse_perf_test.dart
@Tags(["perf"])
library;

import "dart:typed_data";

import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";
import "package:positioned_sliver_list/src/extent_list.dart";

import "perf_tester.dart";

const _items = 190760;
const _operations = 200;

enum _Mode { refresh, insertAt }

final _allocatedBytes = <(bool, _Mode), int>{};

double _run(_Mode mode, {required bool reuse}) {
  final saved = SuperSliverListPerfFlags.reuseFenwickBuffer;
  SuperSliverListPerfFlags.reuseFenwickBuffer = reuse;
  try {
    final list = ExtentList();
    list.resize(_items, (index) => index == null ? 0 : 40.0 + index % 7);
    var checksum = list.offsetForIndex(_items - 1);
    Float64List? buffer = list.debugFenwickTree!.debugBuffer;
    var allocated = 0;
    for (var i = 0; i < _operations; i++) {
      switch (mode) {
        case _Mode.refresh:
          final base = 30.0 + i % 5;
          list.refreshEstimates(
            (index) => index == null ? 0 : base + index % 3,
          );
        case _Mode.insertAt:
          list.insertAt(list.length ~/ 2, (_) => 55.0);
      }
      checksum += list.offsetForIndex(list.length - 1 - i);
      final current = list.debugFenwickTree!.debugBuffer;
      if (!identical(current, buffer)) {
        allocated += current.lengthInBytes;
        buffer = current;
      }
    }
    _allocatedBytes[(reuse, mode)] = allocated;
    return checksum;
  } finally {
    SuperSliverListPerfFlags.reuseFenwickBuffer = saved;
  }
}

void main() {
  test("Win 18: Fenwick rebuild allocates vs reuses its buffer", () async {
    final perf = PerfTester<_Mode, double>(
      testName: "Win 18: Fenwick buffer reuse ($_items items)",
      testCases: _Mode.values,
      implementation1: (m) => _run(m, reuse: false),
      implementation2: (m) => _run(m, reuse: true),
      impl1Name: "allocate",
      impl2Name: "reuse",
    );
    await perf.run(warmupRuns: 3, benchmarkRuns: 10);
    for (final mode in _Mode.values) {
      final before = _allocatedBytes[(false, mode)]! / (1 << 20);
      final after = _allocatedBytes[(true, mode)]! / (1 << 20);
      // ignore: avoid_print
      print(
        "Win 18 ${mode.name}: tree buffers allocated over $_operations "
        "operations: ${before.toStringAsFixed(1)} MB -> "
        "${after.toStringAsFixed(1)} MB",
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

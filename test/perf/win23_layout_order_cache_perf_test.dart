// Win 23: Per-pass layout ordering before delayed multi-sliver corrections.
//
// Run with:
// flutter test --tags perf test/perf/win23_layout_order_cache_perf_test.dart
@Tags(["perf"])
library;

import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/src/layout_pass.dart";
import "package:positioned_sliver_list/src/render_object.dart";

import "perf_tester.dart";

class _StubSliver implements RenderSuperSliverList {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      "_StubSliver";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _cases = <int, LayoutPass>{};

void _prepare() {
  for (final count in [64, 256, 1024]) {
    final slivers = List<RenderSuperSliverList>.generate(
      count,
      (_) => _StubSliver(),
    );
    final pass = LayoutPass(
      slivers: slivers,
      initialScrollPosition: 0,
      childScrollOffsetEstimation: false,
      sliverWithOffsetEstimation: null,
      maxCorrectionCount: 7,
    );
    for (final sliver in slivers) {
      pass.recordLaidOutSliver(sliver);
    }
    _cases[count] = pass;
  }
}

int _scan(int count, {required bool indexed}) {
  final pass = _cases[count]!;
  var checksum = 0;
  for (final sliver in pass.slivers) {
    checksum += indexed
        ? pass.layoutOrderOf(sliver)
        : pass.sliversDuringLayout.indexOf(sliver);
  }
  return checksum;
}

void main() {
  setUpAll(_prepare);
  test("Win 23: indexed vs linear per-sliver order lookups", () async {
    final perf = PerfTester<int, int>(
      testName: "Win 23: layout-pass sliver order",
      testCases: [64, 256, 1024],
      implementation1: (n) => _scan(n, indexed: false),
      implementation2: (n) => _scan(n, indexed: true),
      impl1Name: "repeated indexOf",
      impl2Name: "per-pass index map",
    );
    await perf.run(warmupRuns: 5, benchmarkRuns: 25);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

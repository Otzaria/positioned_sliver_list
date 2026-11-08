// Win 24: Reuse the shared render-sliver-to-viewport transform for all
// visible item-position notifications instead of repeating the same ancestor
// walk and allocating a new transform matrix for each item.
//
// Run with:
//   flutter test --tags perf test/perf/win24_item_positions_transform_perf_test.dart
@Tags(["perf"])
library;

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

import "perf_tester.dart";

void main() {
  testWidgets("Win 24: parent transform reuse in a long reading list", (
    tester,
  ) async {
    final list = ListController();
    final scroll = ScrollController();
    final previous =
        SuperSliverListPerfFlags.shareItemPositionViewportTransform;
    addTearDown(() {
      SuperSliverListPerfFlags.shareItemPositionViewportTransform = previous;
      list.dispose();
      scroll.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 650,
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverOpacity(
                      opacity: 1,
                      sliver: SuperSliverList.builder(
                        listController: list,
                        itemCount: 50000,
                        extentEstimation: (_, _) => 14,
                        itemBuilder: (_, index) => const SizedBox(height: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    scroll.jumpTo(35000);
    await tester.pumpAndSettle();
    expect(list.computeItemPositions(), isNotEmpty);

    int measure({required bool shareTransform}) {
      SuperSliverListPerfFlags.shareItemPositionViewportTransform =
          shareTransform;
      var checksum = 0;
      // Only the position-collection hot path is measured: no widget build,
      // render/layout, extent refresh or allocation of the whole list.
      for (var i = 0; i < 150; i++) {
        final positions = list.computeItemPositions()!;
        checksum += positions.length;
        if (positions.isNotEmpty) {
          checksum += positions.first.index;
          checksum -= positions.last.index;
        }
      }
      return checksum;
    }

    // The shared PerfTester verifier only prints mismatches; make parity a
    // failing assertion before accepting any timing as a valid comparison.
    SuperSliverListPerfFlags.shareItemPositionViewportTransform = false;
    final baseline = list.computeItemPositions()!;
    SuperSliverListPerfFlags.shareItemPositionViewportTransform = true;
    final optimized = list.computeItemPositions()!;
    expect(optimized.length, baseline.length);
    for (var i = 0; i < baseline.length; i++) {
      expect(optimized[i].index, baseline[i].index);
      expect(
        optimized[i].itemLeadingEdge,
        closeTo(baseline[i].itemLeadingEdge, 1e-10),
      );
      expect(
        optimized[i].itemTrailingEdge,
        closeTo(baseline[i].itemTrailingEdge, 1e-10),
      );
    }
    final baselineChecksum = measure(shareTransform: false);
    final optimizedChecksum = measure(shareTransform: true);
    expect(optimizedChecksum, baselineChecksum);

    final perf = PerfTester<int, int>(
      testName: "Win 24: visible item transform reuse",
      testCases: const [0],
      implementation1: (_) => measure(shareTransform: false),
      implementation2: (_) => measure(shareTransform: true),
      impl1Name: "child.localToGlobal each item",
      impl2Name: "shared viewport transform",
    );
    await perf.run(warmupRuns: 5, benchmarkRuns: 20);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

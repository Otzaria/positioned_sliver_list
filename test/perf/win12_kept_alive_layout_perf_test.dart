// Win 12: Single-pass kept-alive children layout.
//
// Baseline runs two full visitChildren passes (over live + kept-alive
// children) on every layout when layoutKeptAliveChildren is enabled, and
// converts SliverConstraints to BoxConstraints once per kept-alive child.
// The optimized variant collects kept-alive children during a single
// traversal and hoists the constraints conversion.
//
// The scenario scrolls through a list where every item is kept alive, so
// the keep-alive bucket grows to ~2400 children that are processed on every
// layout.
//
// Run with:
//   flutter test test/perf/win12_kept_alive_layout_perf_test.dart
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

void main() {
  testWidgets("Win 12: two-pass vs single-pass kept-alive layout",
      (tester) async {
    const itemCount = 2500;

    Future<double> scenario(bool optimized) async {
      final saved = SuperSliverListPerfFlags.optimizedKeptAliveLayout;
      SuperSliverListPerfFlags.optimizedKeptAliveLayout = optimized;
      final scrollController = ScrollController();
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SuperSliverList.builder(
                  layoutKeptAliveChildren: true,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  addSemanticIndexes: false,
                  itemCount: itemCount,
                  itemBuilder: (context, index) => KeepAlive(
                    keepAlive: true,
                    child: SizedBox(height: 15.0 + (index * 7) % 30),
                  ),
                ),
              ],
            ),
          ),
        );
        var checksum = 0.0;
        // Scroll through the whole list; every scrolled-past child is kept
        // alive, growing the bucket processed on each layout.
        while (scrollController.position.pixels <
            scrollController.position.maxScrollExtent) {
          scrollController.jumpTo(
            (scrollController.position.pixels + 1200).clamp(
              0.0,
              scrollController.position.maxScrollExtent,
            ),
          );
          await tester.pump();
          checksum += scrollController.position.pixels;
        }
        // A few more frames with the fully populated bucket.
        for (var i = 0; i < 20; i++) {
          scrollController.jumpTo(i.isEven ? 10000.0 : 12000.0);
          await tester.pump();
          checksum += scrollController.position.pixels;
        }
        checksum += scrollController.position.maxScrollExtent;
        await tester.pumpWidget(const SizedBox());
        return checksum;
      } finally {
        SuperSliverListPerfFlags.optimizedKeptAliveLayout = saved;
        scrollController.dispose();
      }
    }

    final perf = PerfTester<int, double>(
      testName: "Win 12: kept-alive children layout",
      testCases: const [0],
      implementation1: (_) => scenario(false),
      implementation2: (_) => scenario(true),
      impl1Name: "two-pass",
      impl2Name: "single-pass",
    );
    await perf.run(warmupRuns: 1, benchmarkRuns: 8);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

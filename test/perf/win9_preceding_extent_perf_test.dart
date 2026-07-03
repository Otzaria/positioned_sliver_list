// Win 9: Fast getActualPrecedingScrollExtent.
//
// Baseline walks this sliver's ancestor chain once per preceding viewport
// child (O(children * depth)) while resolving a non-estimation
// getOffsetToReveal. The optimized variant finds the sliver's direct
// viewport ancestor with a single upward walk (O(children + depth)).
//
// The scenario uses a viewport with 50 slivers, each nested inside three
// SliverPadding wrappers, and repeatedly resolves reveal offsets for items
// of the last sliver.
//
// Run with:
//   flutter test test/perf/win9_preceding_extent_perf_test.dart
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

void main() {
  testWidgets("Win 9: per-child ancestor walk vs single upward walk",
      (tester) async {
    const sliverCount = 50;
    const itemsPerSliver = 30;
    const reveals = 400;

    Future<double> scenario(bool fast) async {
      final saved = SuperSliverListPerfFlags.fastPrecedingScrollExtent;
      SuperSliverListPerfFlags.fastPrecedingScrollExtent = fast;
      final listController = ListController();
      final scrollController = ScrollController();
      try {
        Widget nest(Widget sliver, int levels) {
          var result = sliver;
          for (var i = 0; i < levels; i++) {
            result = SliverPadding(
              padding: EdgeInsets.zero,
              sliver: result,
            );
          }
          return result;
        }

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                for (var s = 0; s < sliverCount; s++)
                  nest(
                    SuperSliverList.builder(
                      itemCount: itemsPerSliver,
                      listController:
                          s == sliverCount - 1 ? listController : null,
                      itemBuilder: (context, index) =>
                          SizedBox(height: 20.0 + (index % 3) * 10),
                    ),
                    3,
                  ),
              ],
            ),
          ),
        );
        var checksum = 0.0;
        for (var i = 0; i < reveals; i++) {
          checksum += listController.getOffsetToReveal(
            i % itemsPerSliver,
            (i % 4) * 0.25,
          );
        }
        await tester.pumpWidget(const SizedBox());
        return checksum;
      } finally {
        SuperSliverListPerfFlags.fastPrecedingScrollExtent = saved;
        scrollController.dispose();
        listController.dispose();
      }
    }

    final perf = PerfTester<int, double>(
      testName: "Win 9: preceding scroll extent resolution",
      testCases: const [0],
      implementation1: (_) => scenario(false),
      implementation2: (_) => scenario(true),
      impl1Name: "per-child-walk",
      impl2Name: "single-walk",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 15);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

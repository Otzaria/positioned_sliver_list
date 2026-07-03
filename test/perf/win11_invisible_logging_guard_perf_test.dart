// Win 11: Stopwatch/logging guard in the invisible-sliver layout path.
//
// Baseline creates and starts a Stopwatch on every layout of every
// scrolled-past / not-yet-reached sliver purely to feed a FINER log line.
// The optimized variant only does so when FINER logging is actually enabled.
//
// The scenario scrolls through a viewport with 60 slivers so that ~58 of
// them take the invisible path on every pump. The expected win is tiny (one
// allocation + clock read per invisible sliver per frame); the benchmark
// documents whether it is measurable at all.
//
// Run with:
//   flutter test test/perf/win11_invisible_logging_guard_perf_test.dart
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

void main() {
  testWidgets("Win 11: unconditional vs guarded logging stopwatch",
      (tester) async {
    const sliverCount = 60;
    const itemsPerSliver = 10;

    Future<double> scenario(bool guarded) async {
      final saved = SuperSliverListPerfFlags.guardInvisibleLayoutLogging;
      SuperSliverListPerfFlags.guardInvisibleLayoutLogging = guarded;
      final scrollController = ScrollController();
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                for (var s = 0; s < sliverCount; s++)
                  SuperSliverList.builder(
                    itemCount: itemsPerSliver,
                    itemBuilder: (context, index) =>
                        SizedBox(height: 20.0 + (index % 3) * 10),
                  ),
              ],
            ),
          ),
        );
        var checksum = 0.0;
        final max = scrollController.position.maxScrollExtent;
        for (var i = 0; i < 40; i++) {
          final target =
              (i.isEven ? (i + 1) * 400.0 : (i - 1) * 250.0).clamp(0.0, max);
          scrollController.jumpTo(target);
          await tester.pump();
          checksum += scrollController.position.pixels;
        }
        checksum += scrollController.position.maxScrollExtent;
        await tester.pumpWidget(const SizedBox());
        return checksum;
      } finally {
        SuperSliverListPerfFlags.guardInvisibleLayoutLogging = saved;
        scrollController.dispose();
      }
    }

    final perf = PerfTester<int, double>(
      testName: "Win 11: invisible-sliver logging stopwatch",
      testCases: const [0],
      implementation1: (_) => scenario(false),
      implementation2: (_) => scenario(true),
      impl1Name: "unconditional",
      impl2Name: "guarded",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 12);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

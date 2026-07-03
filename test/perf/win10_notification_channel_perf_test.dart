// Win 10: Extents-only notification channel.
//
// Listening to [ListController] directly fires on every layout where
// anything changed - including pure visible-range changes, i.e. every scroll
// frame. The new [ListController.extentsChangedListenable] channel only fires
// when content geometry (extents / item count) changes.
//
// The scenario scrolls back and forth through fully measured content with a
// scrollbar/minimap-style listener attached (reads visible range and item
// extents on every notification). On the legacy channel the listener runs
// every frame; on the extents channel it doesn't run at all.
//
// Savings scale with the cost of the attached listeners; callback counts are
// printed to show the semantic difference.
//
// Run with:
//   flutter test test/perf/win10_notification_channel_perf_test.dart
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

import "perf_tester.dart";

void main() {
  testWidgets("Win 10: legacy vs extents-only notification channel",
      (tester) async {
    const itemCount = 600;

    Future<double> scenario(bool extentsChannel) async {
      final listController = ListController();
      final scrollController = ScrollController();
      var callbacks = 0;
      void minimapListener() {
        callbacks++;
        // Typical scrollbar/minimap work: inspect extents around the visible
        // range plus the total extent.
        final range = listController.visibleRange;
        if (range != null) {
          final first = (range.first - 150).clamp(0, itemCount - 1);
          final last = (range.last + 150).clamp(0, itemCount - 1);
          var sum = 0.0;
          for (var i = first; i <= last; i++) {
            sum += listController.extentForIndex(i).$1;
          }
          sum += listController.totalExtent;
          if (sum.isNaN) callbacks--; // keep `sum` alive
        }
      }

      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SuperListView.builder(
              controller: scrollController,
              listController: listController,
              // ignore: deprecated_member_use
              cacheExtent: 3000,
              itemCount: itemCount,
              itemBuilder: (context, index) =>
                  SizedBox(height: 8.0 + (index * 7) % 10),
            ),
          ),
        );
        // Measure every item once (scroll to the end and back).
        while (scrollController.position.pixels <
            scrollController.position.maxScrollExtent) {
          scrollController.jumpTo(
            (scrollController.position.pixels + 2000).clamp(
              0.0,
              scrollController.position.maxScrollExtent,
            ),
          );
          await tester.pump();
        }
        scrollController.jumpTo(0);
        await tester.pump();
        expect(listController.numberOfItemsWithEstimatedExtent, 0);

        // Attach the listener to the selected channel and scroll through the
        // measured content.
        final Listenable channel = extentsChannel
            ? listController.extentsChangedListenable
            : listController;
        channel.addListener(minimapListener);
        var checksum = 0.0;
        for (var i = 0; i < 120; i++) {
          scrollController.jumpTo(i.isEven ? 1000.0 : 3500.0);
          await tester.pump();
          checksum += scrollController.position.pixels;
        }
        channel.removeListener(minimapListener);
        checksum += listController.totalExtent;
        // ignore: avoid_print
        print("      [${extentsChannel ? "extents-channel" : "legacy"}] "
            "listener invoked $callbacks times during 120 scroll frames");
        await tester.pumpWidget(const SizedBox());
        return checksum;
      } finally {
        scrollController.dispose();
        listController.dispose();
      }
    }

    final perf = PerfTester<int, double>(
      testName: "Win 10: ListController notification channel",
      testCases: const [0],
      implementation1: (_) => scenario(false),
      implementation2: (_) => scenario(true),
      impl1Name: "legacy",
      impl2Name: "extents-channel",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 12);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

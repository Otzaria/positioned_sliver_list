// Win 20: Item position notifications on rebuilds of the compatibility list.
//
// By default `ScrollablePositionedList` notifies its `itemPositionsListener`
// after every rebuild, even when nothing moved, as the original package does.
// A list rebuilt on every layout by a `LayoutBuilder` then rebuilds whatever
// listens to the positions in every frame. With `notifyPositionsOnRebuild:
// false`, only frames that move positions notify.
//
// The scenario rebuilds the list 500 times through a `LayoutBuilder`, scrolls
// every 50 rebuilds, and keeps a position display (a `LayoutBuilder` row per
// visible item) that rebuilds on each notification. Savings scale with the
// cost of that display. The checksum is the final positions; notification
// counts are printed to show the semantic difference.
//
// Run with:
//   flutter test --tags perf test/perf/win20_compat_rebuild_positions_perf_test.dart
@Tags(["perf"])
library;

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

import "perf_tester.dart";

const _rebuilds = 500;

void main() {
  testWidgets("Win 20: notify on every rebuild vs only on change", (
    tester,
  ) async {
    Future<double> scenario(bool notifyPositionsOnRebuild) async {
      final listener = ItemPositionsListener.create();
      final controller = ItemScrollController();
      var notifications = 0;
      void count() => ++notifications;
      var generation = 0;
      late StateSetter setGeneration;
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatefulBuilder(
                  builder: (context, set) {
                    setGeneration = set;
                    return SizedBox(
                      width: 300,
                      height: 600,
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            ScrollablePositionedList.builder(
                              itemPositionsListener: listener,
                              itemScrollController: controller,
                              notifyPositionsOnRebuild:
                                  notifyPositionsOnRebuild,
                              itemCount: 2000,
                              itemBuilder: (context, index) => SizedBox(
                                height: 20.0 + (index * 7) % 30,
                                child: Text("$index $generation"),
                              ),
                            ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: ValueListenableBuilder<Iterable<ItemPosition>>(
                    valueListenable: listener.itemPositions,
                    builder: (context, positions, _) => Column(
                      children: [
                        for (final position in positions)
                          LayoutBuilder(
                            builder: (context, constraints) => SizedBox(
                              height: 12,
                              child: Text(
                                "${position.index} "
                                "${position.itemLeadingEdge.toStringAsFixed(3)}",
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        listener.itemPositions.addListener(count);
        for (var i = 0; i < _rebuilds; i++) {
          setGeneration(() => ++generation);
          if (i % 50 == 49) {
            controller.scrollController!.jumpTo(i * 37.0);
          }
          await tester.pump();
        }
        await tester.pump();
        listener.itemPositions.removeListener(count);
        var checksum = 0.0;
        for (final position in listener.itemPositions.value) {
          checksum +=
              position.index * 1000 +
              position.itemLeadingEdge +
              position.itemTrailingEdge;
        }
        // ignore: avoid_print
        print(
          "      [notifyPositionsOnRebuild: $notifyPositionsOnRebuild] "
          "$notifications notifications during $_rebuilds rebuilds",
        );
        await tester.pumpWidget(const SizedBox());
        return checksum;
      } finally {
        listener.itemPositions.removeListener(count);
      }
    }

    final perf = PerfTester<int, double>(
      testName: "Win 20: compat item positions on rebuild",
      testCases: const [0],
      implementation1: (_) => scenario(true),
      implementation2: (_) => scenario(false),
      impl1Name: "notify-every-rebuild",
      impl2Name: "notify-on-change",
    );
    await perf.run(warmupRuns: 2, benchmarkRuns: 12);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

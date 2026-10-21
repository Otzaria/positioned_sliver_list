// Shared width animation scenario for the resize perf tests.
import "dart:async";
import "dart:math" as math;

import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

/// Words in the item at [index]; the text wraps into one to several lines.
int _words(int index) => 5 + index % 40;

/// Item text width in the FlutterTest font: every glyph is 14 pixels wide.
double _textWidth(int index) => ("$index ".length + 5 * _words(index)) * 14.0;

/// Integer estimate of the item height at [width], dependent on the width.
double resizeEstimate(int index, double width) {
  final lines = (_textWidth(index) / math.max(width, 14)).ceil();
  return lines * 14.0;
}

/// Result of [runResizeScenario], compared between implementations.
class ResizeResult {
  ResizeResult({
    required this.anchorIndex,
    required this.offsetInItem,
    required this.pixels,
    required this.totalExtent,
    required this.positions,
  });

  final int anchorIndex;
  final double offsetInItem;
  final double pixels;
  final double totalExtent;

  /// Sum of the leading edges of the visible items.
  final double positions;

  bool matches(ResizeResult other, {bool compareExtent = true}) {
    bool close(double a, double b) => (a - b).abs() <= 1e-6;
    return anchorIndex == other.anchorIndex &&
        close(offsetInItem, other.offsetInItem) &&
        close(positions, other.positions) &&
        (!compareExtent ||
            (close(pixels, other.pixels) &&
                close(totalExtent, other.totalExtent)));
  }

  @override
  String toString() =>
      "anchor $anchorIndex+${offsetInItem.toStringAsFixed(6)} "
      "pixels ${pixels.toStringAsFixed(6)} "
      "total ${totalExtent.toStringAsFixed(6)} "
      "positions ${positions.toStringAsFixed(6)}";
}

/// Refresh statistics of the last run, per implementation name.
final lastStats = <String, EstimateRefreshStats>{};

/// Milliseconds spent in the animated frames, per implementation name.
final resizeFrameTimes = <String, List<double>>{};

String describeTimes(String name) {
  final times = List.of(resizeFrameTimes[name] ?? const <double>[])..sort();
  if (times.isEmpty) return "$name: no samples";
  final mean = times.reduce((a, b) => a + b) / times.length;
  final median = times.length.isOdd
      ? times[times.length ~/ 2]
      : (times[times.length ~/ 2 - 1] + times[times.length ~/ 2]) / 2;
  return "$name: animation frames median ${median.toStringAsFixed(1)} ms, "
      "mean ${mean.toStringAsFixed(1)} ms over ${times.length} runs; "
      "${lastStats[name]}";
}

/// Jumps to the middle of a large list of wrapped text items, animates the
/// width from [from] to [to] in [frames] frames and lets it settle.
Future<ResizeResult> runResizeScenario(
  WidgetTester tester, {
  required String name,
  required double from,
  required double to,
  int frames = 30,
  int settleFrames = 2,
  int itemCount = 190760,
  int jumpIndex = 95000,
  double? maxColumnWidth,
  CrossAxisLayoutKey? crossAxisLayoutKey,
  bool delayPopulatingCacheArea = true,
}) async {
  tester.view.physicalSize = const Size(2000, 1200);
  tester.view.devicePixelRatio = 1;
  final list = ListController();
  final scroll = ScrollController();
  var width = from;
  late StateSetter setWidth;
  double estimate(int? index, double crossAxis) => index == null
      ? 0
      : resizeEstimate(index, math.min(crossAxis, maxColumnWidth ?? crossAxis));
  try {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: StatefulBuilder(
            builder: (context, set) {
              setWidth = set;
              return SizedBox(
                width: width,
                height: 800,
                child: CustomScrollView(
                  controller: scroll,
                  scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
                  slivers: [
                    SuperSliverList.builder(
                      listController: list,
                      itemCount: itemCount,
                      extentEstimation: estimate,
                      crossAxisLayoutKey: crossAxisLayoutKey,
                      delayPopulatingCacheArea: delayPopulatingCacheArea,
                      itemBuilder: (context, index) {
                        final text = Text(
                          "$index ${"word " * _words(index)}",
                          style: const TextStyle(fontSize: 14, height: 1),
                        );
                        final column = maxColumnWidth;
                        return column == null
                            ? text
                            : Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: column),
                                  child: text,
                                ),
                              );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    unawaited(list.jumpToIndex(jumpIndex, offset: -7));
    await tester.pump();
    await tester.pump();
    final stopwatch = Stopwatch()..start();
    for (var frame = 1; frame <= frames; frame++) {
      setWidth(() => width = from + (to - from) * frame / frames);
      await tester.pump(const Duration(milliseconds: 16));
    }
    stopwatch.stop();
    for (var frame = 0; frame < settleFrames; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    (resizeFrameTimes[name] ??= []).add(stopwatch.elapsedMicroseconds / 1000);
    lastStats[name] = list.estimateRefreshStats!;
    final anchor = list.anchor!;
    var positions = 0.0;
    for (final position
        in list.computeItemPositions() ?? const <ItemPosition>[]) {
      positions += position.itemLeadingEdge;
    }
    return ResizeResult(
      anchorIndex: anchor.index,
      offsetInItem: anchor.offsetInItem,
      pixels: scroll.position.pixels,
      totalExtent: list.totalExtent,
      positions: positions,
    );
  } finally {
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
    list.dispose();
    scroll.dispose();
  }
}

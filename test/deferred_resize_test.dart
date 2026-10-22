import "dart:async";
import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

const _count = 10000;
const _viewport = 600.0;

/// Item height at [width], like wrapped text.
double _reflow(int index, double width) =>
    width <= 0 ? 20 : (20.0 + (index % 9) * 30) * 400 / width;

/// A width dependent estimate that differs from the real heights.
double _estimateAt(double width) => 100 * 400 / width;

class _Harness {
  final list = ListController();
  final scroll = ScrollController();
  final width = ValueNotifier(400.0);
  final offstage = ValueNotifier(false);
  int estimateCalls = 0;

  Widget build({
    int count = _count,
    Object? estimationKey,
    CrossAxisLayoutKey? crossAxisLayoutKey,
    CrossAxisLayoutKey Function(double width)? crossAxisLayoutKeyAt,
    InitialScrollPosition initialScrollPosition = InitialScrollPosition.start,
    OverscrollToTarget overscrollToTarget = OverscrollToTarget.none,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: ListenableBuilder(
        listenable: Listenable.merge([width, offstage]),
        builder: (context, _) => Offstage(
          offstage: offstage.value,
          child: SizedBox(
            width: width.value,
            height: _viewport,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SuperSliverList.builder(
                  listController: list,
                  itemCount: count,
                  estimationKey: estimationKey,
                  crossAxisLayoutKey:
                      crossAxisLayoutKeyAt?.call(width.value) ??
                      crossAxisLayoutKey,
                  initialScrollPosition: initialScrollPosition,
                  overscrollToTarget: overscrollToTarget,
                  extentEstimation: (index, crossAxis) {
                    estimateCalls++;
                    return index == null ? 0 : _estimateAt(crossAxis);
                  },
                  itemBuilder: (_, index) => SizedBox(
                    key: ValueKey(index),
                    height: _reflow(index, width.value),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  EstimateRefreshStats get stats => list.estimateRefreshStats!;

  Future<void> jump(WidgetTester tester, int index, {double offset = 0}) async {
    unawaited(list.jumpToIndex(index, offset: offset));
    await tester.pump();
    await tester.pump();
  }

  /// Changes the width in every one of [frames] frames.
  Future<void> animate(
    WidgetTester tester, {
    required double to,
    int frames = 20,
    void Function(int frame)? afterFrame,
  }) async {
    final from = width.value;
    for (var frame = 1; frame <= frames; frame++) {
      width.value = from + (to - from) * frame / frames;
      await tester.pump(const Duration(milliseconds: 16));
      afterFrame?.call(frame);
    }
  }

  void dispose() {
    list.dispose();
    scroll.dispose();
    width.dispose();
    offstage.dispose();
  }
}

double _top(WidgetTester tester, int index) =>
    tester.getTopLeft(find.byKey(ValueKey(index))).dy;

double _bottom(WidgetTester tester, int index) =>
    tester.getBottomLeft(find.byKey(ValueKey(index))).dy;

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  testWidgets("animation refreshes once", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000, offset: -37);
    final fraction = 37 / _reflow(5000, 400);
    final calls = h.estimateCalls;

    await h.animate(
      tester,
      to: 300,
      afterFrame: (frame) {
        expect(h.estimateCalls, calls, reason: "frame $frame");
        expect(
          _top(tester, 5000),
          closeTo(-fraction * _reflow(5000, h.width.value), 0.01),
          reason: "frame $frame",
        );
      },
    );
    expect(h.stats.deferredResizeCount, 20);
    expect(h.stats.refreshCount, 0);
    expect(h.list.extentForIndex(9000), (_estimateAt(400), true));
    final estimated = h.list.numberOfItemsWithEstimatedExtent;

    await tester.pump();
    expect(h.estimateCalls - calls, 1 + estimated);
    expect(h.stats.refreshCount, 1);
    expect(h.list.extentForIndex(9000), (_estimateAt(300), true));
    expect(_top(tester, 5000), closeTo(-fraction * _reflow(5000, 300), 0.01));
    await tester.pump();
    expect(h.estimateCalls - calls, 1 + estimated);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets("jumpToIndex during animation is exact", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000);
    await h.animate(tester, to: 350, frames: 10);
    unawaited(h.list.jumpToIndex(8000, alignment: 0.3));
    h.width.value = 340;
    await tester.pump();
    expect(_top(tester, 8000), closeTo(0.3 * _viewport, 0.01));
    expect(h.stats.refreshCount, 1);
    await h.animate(tester, to: 300, frames: 10);
    await tester.pump();
    expect(h.stats.refreshCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets("targetRectResolver during animation", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000);
    await h.animate(tester, to: 350, frames: 5);
    unawaited(
      h.list.jumpToIndex(
        7777,
        alignment: 0.5,
        targetRectResolver: (_, item) =>
            Rect.fromLTWH(0, item.size.height / 2, item.size.width, 0),
      ),
    );
    h.width.value = 340;
    await tester.pump();
    final top = _top(tester, 7777);
    expect(top + _reflow(7777, 340) / 2, closeTo(_viewport / 2, 0.01));
  });

  testWidgets("scrollToIndex lands exactly", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000);
    var done = false;
    unawaited(
      h.list
          .scrollToIndex(5400, duration: const Duration(milliseconds: 300))
          .then((_) => done = true),
    );
    await h.animate(tester, to: 300, frames: 30);
    for (var i = 0; i < 10 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(done, isTrue);
    expect(_top(tester, 5400), closeTo(0, 0.01));
    await tester.pump();
    expect(_top(tester, 5400), closeTo(0, 0.01));
  });

  testWidgets("initial end", (tester) async {
    await tester.pumpWidget(
      h.build(initialScrollPosition: InitialScrollPosition.end),
    );
    expect(_bottom(tester, _count - 1), closeTo(_viewport, 0.01));
    await h.animate(
      tester,
      to: 300,
      frames: 10,
      afterFrame: (frame) => expect(
        _bottom(tester, _count - 1),
        closeTo(_viewport, 0.01),
        reason: "frame $frame",
      ),
    );
    await tester.pump();
    expect(_bottom(tester, _count - 1), closeTo(_viewport, 0.01));
    expect(h.stats.refreshCount, 1);
  });

  for (final stick in [false, true]) {
    testWidgets("anchored at end${stick ? " with StickTarget.bottom" : ""}", (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      if (stick) h.list.stickTarget = const StickTarget.bottom();
      unawaited(
        h.list.jumpToIndex(
          _count - 1,
          alignment: 1,
          offset: -_reflow(_count - 1, 400),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_bottom(tester, _count - 1), closeTo(_viewport, 0.01));
      await h.animate(
        tester,
        to: 300,
        frames: 10,
        afterFrame: (frame) => expect(
          _bottom(tester, _count - 1),
          closeTo(_viewport, 0.01),
          reason: "frame $frame",
        ),
      );
      await tester.pump();
      expect(_bottom(tester, _count - 1), closeTo(_viewport, 0.01));
      expect(h.stats.deferredResizeCount, 10);
    });
  }

  testWidgets("header anchor keeps Y", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000, offset: -10);
    final header =
        tester.renderObject(find.byKey(const ValueKey(5002))) as RenderBox;
    final y = _top(tester, 5002);
    final handle = h.list.preserveHeader(header)!;
    await h.animate(
      tester,
      to: 300,
      frames: 10,
      afterFrame: (frame) =>
          expect(_top(tester, 5002), closeTo(y, 0.01), reason: "$frame"),
    );
    await tester.pump();
    expect(_top(tester, 5002), closeTo(y, 0.01));
    expect(h.stats.refreshCount, 1);
    handle.cancel();
  });

  testWidgets("pinned overscroll with 5000 items", (tester) async {
    await tester.pumpWidget(
      h.build(count: 5000, overscrollToTarget: OverscrollToTarget.always),
    );
    unawaited(h.list.jumpToIndex(4998, alignment: 0.2));
    await tester.pump();
    expect(_top(tester, 4998), closeTo(120, 0.01));
    await h.animate(
      tester,
      to: 300,
      frames: 10,
      afterFrame: (frame) => expect(
        _top(tester, 4998),
        closeTo(120, 0.01),
        reason: "frame $frame",
      ),
    );
    await tester.pump();
    expect(_top(tester, 4998), closeTo(120, 0.01));
    expect(h.stats.deferredResizeCount, 10);
  });

  testWidgets("estimationKey during animation refreshes immediately", (
    tester,
  ) async {
    await tester.pumpWidget(h.build(estimationKey: 1));
    await h.jump(tester, 5000);
    await h.animate(tester, to: 350, frames: 5);
    expect(h.stats.refreshCount, 0);
    h.width.value = 340;
    await tester.pumpWidget(h.build(estimationKey: 2));
    expect(h.stats.refreshCount, 1);
    expect(h.stats.deferredResizeCount, 5);
    expect(h.list.extentForIndex(9000), (_estimateAt(340), true));
    await tester.pump();
    expect(h.stats.refreshCount, 1);
  });

  // Like a text column that is a fraction of the window, not of the list.
  CrossAxisLayoutKey columnOf(double window) =>
      (_) => (window * 0.95).roundToDouble();

  testWidgets("a key that changes with the window is deferred", (tester) async {
    await tester.pumpWidget(h.build(crossAxisLayoutKeyAt: columnOf));
    await h.jump(tester, 5000, offset: -37);
    final fraction = 37 / _reflow(5000, 400);
    final calls = h.estimateCalls;

    await h.animate(
      tester,
      to: 300,
      afterFrame: (frame) {
        expect(h.estimateCalls, calls, reason: "frame $frame");
        expect(
          _top(tester, 5000),
          closeTo(-fraction * _reflow(5000, h.width.value), 0.01),
          reason: "frame $frame",
        );
      },
    );
    expect(h.stats.refreshCount, 0);
    await tester.pump();
    expect(h.stats.refreshCount, 1);
    expect(h.list.extentForIndex(9000), (_estimateAt(300), true));
    expect(_top(tester, 5000), closeTo(-fraction * _reflow(5000, 300), 0.01));
  });

  testWidgets("a key change without a width change refreshes", (tester) async {
    await tester.pumpWidget(h.build(crossAxisLayoutKeyAt: columnOf));
    await h.jump(tester, 5000);
    await tester.pumpWidget(
      h.build(crossAxisLayoutKeyAt: (width) => columnOf(width - 50)),
    );
    expect(h.stats.refreshCount, 0);
    expect(h.stats.deferredResizeCount, 1);
    await tester.pump();
    expect(h.stats.refreshCount, 1);
    expect(_top(tester, 5000), closeTo(0, 0.01));

    // A small list refreshes in the same frame.
    await tester.pumpWidget(
      h.build(count: 100, crossAxisLayoutKeyAt: columnOf),
    );
    await tester.pump();
    final refreshes = h.stats.refreshCount;
    await tester.pumpWidget(
      h.build(
        count: 100,
        crossAxisLayoutKeyAt: (width) => columnOf(width - 50),
      ),
    );
    expect(h.stats.refreshCount, refreshes + 1);
  });

  testWidgets("updateEstimatedExtents during deferral is kept", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000);
    await h.animate(tester, to: 350, frames: 3);
    unawaited(h.list.updateEstimatedExtents({9000: 777}));
    await tester.pump();
    expect(h.list.extentForIndex(9000), (777.0, true));
    expect(h.list.extentForIndex(9001), (_estimateAt(350), true));
    expect(h.stats.refreshCount, 1);
    await tester.pump();
    expect(h.list.extentForIndex(9000), (777.0, true));

    unawaited(h.list.updateEstimatedExtents({9000: 555}));
    h.width.value = 300;
    await tester.pump();
    expect(h.list.extentForIndex(9000), (555.0, true));
    expect(h.list.extentForIndex(9001), (_estimateAt(300), true));
  });

  testWidgets("invalidateExtent during deferral", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000);
    await h.animate(tester, to: 350, frames: 3);
    h.list.invalidateExtent(9000);
    h.width.value = 340;
    await tester.pump();
    expect(h.list.extentForIndex(9000), (_estimateAt(340), true));
    expect(h.list.extentForIndex(9001), (_estimateAt(400), true));
    await tester.pump();
    expect(h.list.extentForIndex(9001), (_estimateAt(340), true));
  });

  testWidgets("small lists refresh in the same frame", (tester) async {
    await tester.pumpWidget(h.build(count: 1000));
    await h.jump(tester, 500);
    final calls = h.estimateCalls;
    h.width.value = 300;
    await tester.pump();
    expect(h.estimateCalls - calls, 1001);
    expect(h.stats.refreshCount, 1);
    expect(h.stats.deferredResizeCount, 0);
    expect(h.list.extentForIndex(900), (_estimateAt(300), true));
  });

  testWidgets("offstage settles", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000);
    await h.animate(tester, to: 350, frames: 3);
    h.offstage.value = true;
    await tester.pump();
    await tester.pump();
    expect(h.stats.refreshCount, 1);
    expect(h.list.extentForIndex(9000), (_estimateAt(350), true));
  });

  testWidgets("indexForScrollOffset exact for laid-out items", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000, offset: -20);
    await h.animate(tester, to: 330, frames: 4);
    expect(h.list.numberOfItemsWithEstimatedExtent, greaterThan(9000));
    final pixels = h.scroll.position.pixels;
    var visible = 0;
    while (find.byKey(ValueKey(5000 + visible)).evaluate().isNotEmpty) {
      visible++;
    }
    expect(visible, greaterThan(1));
    for (var index = 5000; index < 5000 + visible; index++) {
      final top = _top(tester, index);
      expect(h.list.indexForScrollOffset(pixels + top + 0.5), index);
      expect(
        h.list.indexForScrollOffset(pixels + _bottom(tester, index) - 0.5),
        index,
      );
    }
  });

  testWidgets("zero width calls no estimator", (tester) async {
    await tester.pumpWidget(h.build());
    await h.jump(tester, 5000);
    final calls = h.estimateCalls;
    h.width.value = 0;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(h.estimateCalls, calls);
    expect(h.stats.refreshCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    h.width.value = 300;
    await tester.pump();
    await tester.pump();
    expect(h.stats.refreshCount, 1);
    expect(h.estimateCalls, greaterThan(calls));
    expect(h.list.extentForIndex(9000), (_estimateAt(300), true));
  });

  testWidgets("key changes during animation defer; unchanged widths skip", (
    tester,
  ) async {
    await tester.pumpWidget(
      h.build(crossAxisLayoutKey: (width) => math.min(width, 300)),
    );
    await h.jump(tester, 5000);
    // 400 -> 250: skipped while the key stays 300, deferred below it.
    await h.animate(tester, to: 250, frames: 6);
    expect(h.stats.skippedResizeCount, 4);
    expect(h.stats.deferredResizeCount, 2);
    expect(h.stats.refreshCount, 0);
    // Back to 400: the first skipped width settles the deferred refresh.
    await h.animate(tester, to: 400, frames: 6);
    expect(h.stats.deferredResizeCount, 4);
    expect(h.stats.skippedResizeCount, 8);
    expect(h.stats.refreshCount, 1);
    expect(h.list.extentForIndex(9000), (_estimateAt(325), true));
    await tester.pump();
    expect(h.stats.refreshCount, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

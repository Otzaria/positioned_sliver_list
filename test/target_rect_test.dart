import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

void main() {
  for (final mode in ["initial", "jump", "animation"]) {
    testWidgets(
      "nested RenderBox sizes are readable in $mode target resolver",
      (tester) async {
        final scroll = ScrollController();
        final list = ListController();
        final inner = GlobalKey();
        addTearDown(scroll.dispose);
        addTearDown(list.dispose);
        var calls = 0;
        Rect resolve(int index, RenderBox item) {
          ++calls;
          final box = inner.currentContext!.findRenderObject()! as RenderBox;
          expect(box.size.height, 100);
          return MatrixUtils.transformRect(
            box.getTransformTo(item),
            Offset.zero & box.size,
          );
        }

        await tester.pumpWidget(
          _view(
            scroll: scroll,
            list: list,
            initialIndex: mode == "initial" ? 5000 : null,
            initialAlignment: 0.3,
            initialTargetRectResolver: mode == "initial" ? resolve : null,
            targetBuilder: () => Column(
              children: [
                const SizedBox(height: 1700),
                SizedBox(key: inner, height: 100),
                const Spacer(),
              ],
            ),
          ),
        );
        if (mode == "jump") {
          final jump = list.jumpToIndex(
            5000,
            alignment: 0.3,
            targetRectResolver: resolve,
          );
          await tester.pumpAndSettle();
          await jump;
        } else if (mode == "animation") {
          final animation = list.scrollToIndex(
            5000,
            alignment: 0.3,
            duration: const Duration(milliseconds: 200),
            targetRectResolver: resolve,
          );
          await tester.pumpAndSettle();
          await animation;
        }
        expect(calls, greaterThan(0));
        expect(tester.getTopLeft(find.byKey(inner)).dy, closeTo(180, 0.01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    "inner target uses descendant geometry changed in the same frame",
    (tester) async {
      final scroll = ScrollController();
      final list = ListController();
      final inner = GlobalKey();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      var prefix = 1700.0;
      var height = 100.0;
      var layouts = 0;
      var builds = 0;
      late StateSetter rebuild;
      Rect resolve(int index, RenderBox item) {
        final box = inner.currentContext!.findRenderObject()! as RenderBox;
        final offset = MatrixUtils.transformPoint(
          box.getTransformTo(item),
          Offset(0, box.size.height * 0.25),
        );
        return Rect.fromLTWH(offset.dx, offset.dy, 0, 0);
      }

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return _view(
              scroll: scroll,
              list: list,
              initialIndex: 5000,
              initialAlignment: 0.3,
              initialTargetRectResolver: resolve,
              onBuild: () => ++builds,
              targetBuilder: () => _LayoutCounter(
                onLayout: () => ++layouts,
                child: Column(
                  children: [
                    SizedBox(height: prefix),
                    SizedBox(key: inner, height: height),
                    const Spacer(),
                  ],
                ),
              ),
            );
          },
        ),
      );
      expect(tester.getTopLeft(find.byKey(inner)).dy + 25, closeTo(180, 0.01));
      layouts = 0;
      builds = 0;
      final same = list.jumpToIndex(
        5000,
        alignment: 0.3,
        targetRectResolver: resolve,
      );
      await tester.pump();
      await same;
      expect(layouts, 1);
      expect(builds, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      rebuild(() {
        prefix = 700;
        height = 400;
      });
      final jump = list.jumpToIndex(
        5000,
        alignment: 0.3,
        targetRectResolver: resolve,
      );
      await tester.pump();
      await jump;
      expect(tester.getSize(find.byKey(inner)).height, 400);
      expect(tester.getTopLeft(find.byKey(inner)).dy + 100, closeTo(180, 0.01));
      final settledLayouts = layouts;
      final settledBuilds = builds;
      await tester.pump();
      expect(layouts, settledLayouts);
      expect(builds, settledBuilds);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets("initial inner target is resolved in the first frame", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    RenderBox? targetBox;
    await tester.pumpWidget(
      _view(
        scroll: scroll,
        list: list,
        initialIndex: 5000,
        initialAlignment: 0.35,
        initialOffset: 12,
        initialTargetRectResolver: (index, box) {
          expect(index, 5000);
          targetBox = box;
          return Rect.fromLTWH(0, box.size.height * 0.75, 0, 0);
        },
      ),
    );
    expect(targetBox, isNotNull);
    expect(
      targetBox!.localToGlobal(Offset(0, targetBox!.size.height * 0.75)).dy,
      closeTo(222, 0.01),
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final axis in Axis.values) {
    for (final reverse in [false, true]) {
      for (final direction in TextDirection.values) {
        testWidgets(
          "resolves a distant inner rect before paint $axis $reverse $direction",
          (tester) async {
            final scroll = ScrollController();
            final list = ListController();
            addTearDown(scroll.dispose);
            addTearDown(list.dispose);
            var built = 0;
            RenderBox? targetBox;
            final rect = axis == Axis.vertical
                ? const Rect.fromLTWH(0, 1700, 100, 77)
                : const Rect.fromLTWH(1700, 0, 77, 100);
            await tester.pumpWidget(
              _view(
                scroll: scroll,
                list: list,
                axis: axis,
                reverse: reverse,
                direction: direction,
                onBuild: () => built++,
              ),
            );
            built = 0;
            var completed = false;
            unawaited(
              list
                  .jumpToIndex(
                    5000,
                    alignment: 0.3,
                    offset: 12,
                    targetRectResolver: (index, box) {
                      expect(index, 5000);
                      expect(box.hasSize, isTrue);
                      expect(box.size.longestSide, 2400);
                      targetBox = box;
                      return rect;
                    },
                  )
                  .then((_) => completed = true),
            );
            await tester.pump();
            expect(completed, isTrue);
            final global = MatrixUtils.transformRect(
              targetBox!.getTransformTo(null),
              rect,
            );
            final leading = axis == Axis.vertical
                ? (reverse ? 600 - global.bottom : global.top)
                : ((direction == TextDirection.rtl) != reverse
                      ? 600 - global.right
                      : global.left);
            expect(leading, closeTo(192, 0.01));
            expect(built, lessThan(100));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  testWidgets("null target rect falls back to the item's leading edge", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_view(scroll: scroll, list: list));
    final jump = list.jumpToIndex(
      5000,
      alignment: 0.25,
      targetRectResolver: (_, _) => null,
    );
    await tester.pumpAndSettle();
    await jump;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(5000))).dy,
      closeTo(150, 0.01),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("animation resolves a zero-height inner target after layout", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    RenderBox? targetBox;
    await tester.pumpWidget(_view(scroll: scroll, list: list));
    await tester.pumpAndSettle();
    final animation = list.scrollToIndex(
      5000,
      alignment: 0.2,
      offset: 9,
      duration: const Duration(milliseconds: 200),
      targetRectResolver: (_, box) {
        targetBox = box;
        return const Rect.fromLTWH(0, 1800, 0, 0);
      },
    );
    await tester.pumpAndSettle();
    await animation;
    expect(animation.isAnimating, isFalse);
    expect(
      targetBox!.localToGlobal(const Offset(0, 1800)).dy,
      closeTo(129, 0.01),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("replacement jump releases the old inner target resolver", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_view(scroll: scroll, list: list));
    var oldCalls = 0;
    final old = list.jumpToIndex(
      5000,
      targetRectResolver: (_, _) {
        oldCalls++;
        return const Rect.fromLTWH(0, 1800, 0, 0);
      },
    );
    final current = list.jumpToIndex(20, offset: 31);
    await tester.pumpAndSettle();
    await Future.wait([old, current]);
    expect(oldCalls, 0);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(20))).dy,
      closeTo(31, 0.01),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _view({
  required ScrollController scroll,
  required ListController list,
  Axis axis = Axis.vertical,
  bool reverse = false,
  TextDirection direction = TextDirection.ltr,
  VoidCallback? onBuild,
  int? initialIndex,
  double initialAlignment = 0,
  double initialOffset = 0,
  TargetRectResolver? initialTargetRectResolver,
  Widget Function()? targetBuilder,
}) => Directionality(
  textDirection: direction,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: axis == Axis.vertical ? 400 : 600,
      height: axis == Axis.vertical ? 600 : 400,
      child: CustomScrollView(
        controller: scroll,
        scrollDirection: axis,
        reverse: reverse,
        scrollCacheExtent: const ScrollCacheExtent.viewport(1),
        slivers: [
          SuperSliverList.builder(
            listController: list,
            initialIndex: initialIndex,
            initialAlignment: initialAlignment,
            initialOffset: initialOffset,
            initialTargetRectResolver: initialTargetRectResolver,
            itemCount: 10000,
            extentEstimation: (_, _) => 1,
            estimationKey: "constant-target-test-extents",
            itemBuilder: (_, index) {
              onBuild?.call();
              final extent = index == 5000 ? 2400.0 : 100.0;
              return SizedBox(
                key: ValueKey(index),
                height: axis == Axis.vertical ? extent : null,
                width: axis == Axis.horizontal ? extent : null,
                child: index == 5000 ? targetBuilder?.call() : null,
              );
            },
          ),
        ],
      ),
    ),
  ),
);

class _LayoutCounter extends SingleChildRenderObjectWidget {
  const _LayoutCounter({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutCounter(onLayout);
}

class _RenderLayoutCounter extends RenderProxyBox {
  _RenderLayoutCounter(this.onLayout);

  final VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}

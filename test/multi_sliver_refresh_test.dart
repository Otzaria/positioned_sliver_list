import "dart:async";

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

const _viewport = 600.0;

double _estimateAt(double width) => 100 * 400 / width;

double _reflow(int index, double width) =>
    (20.0 + (index % 9) * 30) * 400 / width;

/// Two lists in one viewport; the second one is the one being read.
class _Harness {
  _Harness({required this.firstCount});

  final int firstCount;
  final first = ListController();
  final second = ListController();
  final scroll = ScrollController();
  final width = ValueNotifier(400.0);
  final estimationKey = ValueNotifier(0);

  SuperSliverList _list(String name, ListController controller, int count) =>
      SuperSliverList.builder(
        listController: controller,
        itemCount: count,
        estimationKey: estimationKey.value,
        extentEstimation: (index, crossAxis) =>
            index == null ? 0 : _estimateAt(crossAxis) + estimationKey.value,
        itemBuilder: (_, index) => SizedBox(
          key: ValueKey("$name$index"),
          height: _reflow(index, width.value),
        ),
      );

  Widget build() => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: ListenableBuilder(
        listenable: Listenable.merge([width, estimationKey]),
        builder: (context, _) => SizedBox(
          width: width.value,
          height: _viewport,
          child: CustomScrollView(
            controller: scroll,
            slivers: [_list("a", first, firstCount), _list("b", second, 1000)],
          ),
        ),
      ),
    ),
  );

  Future<void> jumpToSecond(WidgetTester tester, int index) async {
    unawaited(second.jumpToIndex(index));
    await tester.pump();
    await tester.pump();
  }

  void dispose() {
    first.dispose();
    second.dispose();
    scroll.dispose();
    width.dispose();
    estimationKey.dispose();
  }
}

double _top(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key), skipOffstage: false)).dy;

void main() {
  for (final firstCount in [1000, 5000]) {
    group("first list with $firstCount items", () {
      late _Harness h;
      setUp(() => h = _Harness(firstCount: firstCount));
      tearDown(() => h.dispose());

      for (final to in [300.0, 500.0]) {
        testWidgets("width $to keeps the second list in place", (tester) async {
          await tester.pumpWidget(h.build());
          await h.jumpToSecond(tester, 200);
          expect(_top(tester, "b200"), 0);
          expect(find.byKey(const ValueKey("a0")), findsNothing);

          h.width.value = to;
          await tester.pump();
          await tester.pump();
          expect(_top(tester, "b200"), closeTo(0, 0.01));
          expect(h.first.extentForIndex(firstCount - 1), (
            _estimateAt(to),
            true,
          ));
        });
      }

      testWidgets("width animation keeps the second list in place", (
        tester,
      ) async {
        await tester.pumpWidget(h.build());
        await h.jumpToSecond(tester, 200);
        for (var frame = 1; frame <= 20; frame++) {
          h.width.value = 400 - 5.0 * frame;
          await tester.pump(const Duration(milliseconds: 16));
          expect(_top(tester, "b200"), closeTo(0, 0.01), reason: "$frame");
        }
        await tester.pump();
        await tester.pump();
        expect(_top(tester, "b200"), closeTo(0, 0.01));
      });

      testWidgets("estimationKey keeps the second list in place", (
        tester,
      ) async {
        await tester.pumpWidget(h.build());
        await h.jumpToSecond(tester, 200);
        h.estimationKey.value = 7;
        await tester.pump();
        await tester.pump();
        expect(_top(tester, "b200"), closeTo(0, 0.01));
        expect(h.first.extentForIndex(firstCount - 1), (
          _estimateAt(400) + 7,
          true,
        ));
      });
    });
  }

  testWidgets("the end of the first list visible", (tester) async {
    final h = _Harness(firstCount: 1000);
    addTearDown(h.dispose);
    await tester.pumpWidget(h.build());
    await h.jumpToSecond(tester, 0);
    h.scroll.jumpTo(h.scroll.offset - 100);
    await tester.pump();
    expect(_top(tester, "b0"), 100);

    h.width.value = 300;
    await tester.pump();
    await tester.pump();
    // The first list ends in view, so its end stays in place.
    expect(_top(tester, "b0"), closeTo(100, 0.01));
  });

  testWidgets("the end of the first list in cache", (tester) async {
    final h = _Harness(firstCount: 1000);
    addTearDown(h.dispose);
    await tester.pumpWidget(h.build());
    await h.jumpToSecond(tester, 0);
    h.scroll.jumpTo(h.scroll.offset + 100);
    await tester.pump();
    expect(
      find.byKey(const ValueKey("a999"), skipOffstage: false),
      findsOneWidget,
    );
    // b2 spans 70..150 in the second list, so 30 of its 80 are above the top.
    expect(_top(tester, "b2"), -30);

    h.width.value = 300;
    await tester.pump();
    await tester.pump();
    expect(_top(tester, "b2"), closeTo(-30 / 80 * _reflow(2, 300), 0.01));
  });
}

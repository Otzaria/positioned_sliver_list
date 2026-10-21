import "dart:async";

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

const _count = 100000;

int _inits = 0;

class _Item extends StatefulWidget {
  const _Item(this.index, {super.key});

  final int index;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  @override
  void initState() {
    super.initState();
    _inits++;
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 20.0 + widget.index % 9 * 30);
}

class _Harness {
  final list = ListController();
  final width = ValueNotifier(400.0);
  final key = ValueNotifier(0);

  Widget build() => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: ListenableBuilder(
        listenable: Listenable.merge([width, key]),
        builder: (_, _) => SizedBox(
          width: width.value,
          height: 600,
          child: CustomScrollView(
            slivers: [
              SuperSliverList.builder(
                listController: list,
                itemCount: _count,
                estimationKey: key.value,
                // Narrower, or a newer key, means taller estimates above.
                extentEstimation: (index, crossAxis) => index == null
                    ? 0
                    : (100 + 10 * key.value) * 400 / crossAxis,
                itemBuilder: (_, index) => _Item(index, key: ValueKey(index)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void dispose() {
    list.dispose();
    width.dispose();
    key.dispose();
  }
}

enum _Change { width, estimationKey, batch }

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(h.build());
    unawaited(h.list.jumpToIndex(50000, offset: -5));
    await tester.pump();
    await tester.pump();
  }

  void change(_Change change) {
    switch (change) {
      case _Change.width:
        h.width.value = 300;
      case _Change.estimationKey:
        h.key.value = 5;
      case _Change.batch:
        unawaited(
          h.list.updateEstimatedExtents({
            for (var i = 0; i < 40000; i += 2) i: 400,
          }),
        );
    }
  }

  for (final defer in [false, true]) {
    for (final kind in _Change.values) {
      testWidgets("an active header anchor keeps its position through a "
          "${kind.name} refresh without building the items between "
          "(defer: $defer)", (tester) async {
        final saved = SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh;
        SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh = defer;
        addTearDown(
          () => SuperSliverListPerfFlags.deferCrossAxisEstimateRefresh = saved,
        );
        await start(tester);
        final header = find.byKey(const ValueKey(50002));
        final y = tester.getTopLeft(header).dy;
        final handle = h.list.preserveHeader(tester.renderObject(header))!;
        addTearDown(handle.cancel);
        await tester.pump();

        _inits = 0;
        change(kind);
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getTopLeft(header).dy, closeTo(y, 0.01));
        }
        expect(h.list.estimateRefreshStats!.refreshCount, switch (kind) {
          _Change.batch => 0,
          _ => 1,
        });
        expect(_inits, lessThan(200));
        expect(handle.isActive, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets("a jump to a laid out item during a refresh does not build the "
      "items between", (tester) async {
    await start(tester);
    _inits = 0;
    unawaited(h.list.jumpToIndex(50003, alignment: 0.2));
    h.width.value = 300;
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(50003))).dy,
      closeTo(120, 0.01),
    );
    expect(_inits, lessThan(200));
    expect(tester.takeException(), isNull);
  });
}

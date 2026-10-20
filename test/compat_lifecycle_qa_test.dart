import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

void main() {
  testWidgets(
    "the caller owns an external list controller across reattachment",
    (tester) async {
      final item = ItemScrollController();
      final native = ListController();
      addTearDown(native.dispose);
      await tester.pumpWidget(_list(item, native: native));
      expect(item.listController, same(native));
      expect(native.isAttached, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(native.isAttached, isFalse);
      void listener() {}
      native.addListener(listener);
      native.removeListener(listener);
      await tester.pumpWidget(_list(item, native: native));
      final moved = item.jumpToAsync(index: 70, offset: -23);
      await tester.pumpAndSettle();
      await moved;
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(70))).dy,
        closeTo(-23, 0.01),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets("replacing the external controller transfers position updates", (
    tester,
  ) async {
    final item = ItemScrollController();
    final first = ListController();
    final second = ListController();
    final positions = ItemPositionsListener.create();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(_list(item, native: first, positions: positions));
    final oldMove = item.scrollTo(
      index: 900,
      duration: const Duration(seconds: 1),
    );
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pumpWidget(_list(item, native: second, positions: positions));
    await oldMove;
    expect(first.isAttached, isFalse);
    expect(second.isAttached, isTrue);
    expect(item.listController, same(second));
    final current = item.jumpToAsync(index: 40, offset: -21);
    await tester.pumpAndSettle();
    await current;
    final target = positions.itemPositions.value.singleWhere(
      (position) => position.index == 40,
    );
    expect(target.itemLeadingEdge, closeTo(-21 / 400, 0.003));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(40))).dy,
      closeTo(-21, 0.01),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    "separated identity remapping retains state and descendant keys",
    (tester) async {
      final item = ItemScrollController();
      var ids = List<int>.generate(100, (index) => index);
      final descendant = GlobalKey();
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 400,
              child: StatefulBuilder(
                builder: (_, setState) {
                  rebuild = setState;
                  return ScrollablePositionedList.separated(
                    itemScrollController: item,
                    itemCount: ids.length,
                    findChildIndexCallback: (key) {
                      final index = ids.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                    estimateExtent: (_, _) => 80,
                    estimatedSeparatorExtent: 10,
                    itemBuilder: (_, index) => _StatefulParagraph(
                      key: ValueKey(ids[index]),
                      id: ids[index],
                      descendant: ids[index] == 3 ? descendant : null,
                    ),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final target = find.byKey(const ValueKey(3));
      final state = tester.state(target);
      final descendantState = descendant.currentContext;
      rebuild(() {
        ids = List.of(ids)..remove(3);
        ids.insert(8, 3);
      });
      await tester.pump();
      final moved = item.jumpToAsync(index: 8);
      await tester.pumpAndSettle();
      await moved;
      expect(tester.state(target), same(state));
      expect(descendant.currentContext, same(descendantState));
      expect(tester.getTopLeft(target).dy, closeTo(0, 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets("the latest jump wins and both layout futures complete", (
    tester,
  ) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(_list(controller));
    var firstCompleted = false;
    var latestCompleted = false;
    final first = controller.jumpToAsync(index: 900).then((_) {
      firstCompleted = true;
    });
    final latest = controller
        .jumpToAsync(index: 4000, alignment: 0.25, offset: -12)
        .then((_) {
          latestCompleted = true;
        });
    expect(latestCompleted, isFalse);
    await tester.pumpAndSettle();
    expect(firstCompleted, isTrue);
    expect(latestCompleted, isTrue);
    await Future.wait([first, latest]);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(4000))).dy,
      closeTo(88, 0.01),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("an unmounted pending jump cannot move the next attachment", (
    tester,
  ) async {
    final controller = ItemScrollController();
    await tester.pumpWidget(_list(controller));
    var detachedCompleted = false;
    final detached = controller.jumpToAsync(index: 4000).then((_) {
      detachedCompleted = true;
    });
    await tester.pumpWidget(const SizedBox());
    expect(detachedCompleted, isTrue);
    await detached;
    expect(controller.isAttached, isFalse);
    await tester.pumpWidget(_list(controller));
    final current = controller.jumpToAsync(index: 20, offset: -25);
    await tester.pumpAndSettle();
    await current;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(20))).dy,
      closeTo(-25, 0.01),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _list(
  ItemScrollController controller, {
  ListController? native,
  ItemPositionsListener? positions,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 400,
      height: 400,
      child: ScrollablePositionedList.builder(
        itemScrollController: controller,
        listController: native,
        itemPositionsListener: positions,
        itemCount: 5000,
        estimateExtent: (index, _) => 80.0 + index % 5 * 20,
        itemBuilder: (_, index) => SizedBox(
          key: ValueKey(index),
          height: 80.0 + index % 5 * 20,
          child: Text("Paragraph $index"),
        ),
      ),
    ),
  ),
);

class _StatefulParagraph extends StatefulWidget {
  const _StatefulParagraph({required this.id, this.descendant, super.key});
  final int id;
  final Key? descendant;

  @override
  State<_StatefulParagraph> createState() => _StatefulParagraphState();
}

class _StatefulParagraphState extends State<_StatefulParagraph> {
  @override
  Widget build(BuildContext context) => SizedBox(
    key: widget.descendant,
    height: 80,
    child: Text("Paragraph ${widget.id}"),
  );
}

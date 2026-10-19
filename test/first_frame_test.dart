import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

double _extent(int index) => 20.0 + (index * 7919) % 300;
Finder _text(String t) => find.text(t, skipOffstage: false);

class _OnInit extends StatefulWidget {
  const _OnInit(this.cb);
  final VoidCallback cb;
  @override
  State<_OnInit> createState() => _OnInitState();
}

class _OnInitState extends State<_OnInit> {
  @override
  void initState() {
    super.initState();
    widget.cb();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget _app(ItemScrollController c, VoidCallback onInit) => MaterialApp(
  home: Column(
    children: [
      Expanded(
        child: ScrollablePositionedList.builder(
          itemCount: 10000,
          itemScrollController: c,
          itemBuilder: (_, i) =>
              SizedBox(height: _extent(i), child: Text("Item $i")),
        ),
      ),
      _OnInit(onInit),
    ],
  ),
);

void main() {
  testWidgets("jumpTo from a sibling's initState in the list's first frame", (
    tester,
  ) async {
    final c = ItemScrollController();
    await tester.pumpWidget(
      _app(c, () => c.jumpTo(index: 4321, alignment: 0.5)),
    );
    expect(tester.takeException(), isNull);
    await tester.pump();
    final h = tester.getSize(find.byType(Expanded)).height;
    expect(tester.getTopLeft(_text("Item 4321")).dy, closeTo(h / 2, 0.5));
  });

  testWidgets("scrollTo from a sibling's initState in the list's first frame", (
    tester,
  ) async {
    final c = ItemScrollController();
    var done = false;
    await tester.pumpWidget(
      _app(c, () {
        unawaited(
          c
              .scrollTo(
                index: 4321,
                duration: const Duration(milliseconds: 300),
              )
              .then((_) => done = true),
        );
      }),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(tester.getTopLeft(_text("Item 4321")).dy, closeTo(0, 0.5));
  });
}

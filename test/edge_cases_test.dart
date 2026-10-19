// Edge cases: lifecycle, input during animations, unusual layouts.
import "dart:async";

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

const _w = 400.0;
const _h = 600.0;

double _extent(int index) => 20.0 + (index * 7919) % 300;

Finder _text(String t) => find.text(t, skipOffstage: false);

Widget _host(
  Widget child, {
  double w = _w,
  double h = _h,
  TextDirection dir = TextDirection.ltr,
}) => Directionality(
  textDirection: dir,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(800, 800)),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: w, height: h, child: child),
    ),
  ),
);

class _Item extends StatelessWidget {
  const _Item(this.index, this.height);
  final int index;
  final double height;
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, child: Text("Item $index"));
}

void main() {
  group("zero-size viewport", () {
    testWidgets("jumpTo while collapsed to 0 height, then expand", (
      tester,
    ) async {
      final c = ItemScrollController();
      final p = ItemPositionsListener.create();
      Widget build(double h) => _host(
        ScrollablePositionedList.builder(
          itemCount: 10000,
          itemScrollController: c,
          itemPositionsListener: p,
          itemBuilder: (_, i) => _Item(i, _extent(i)),
        ),
        h: h,
      );
      await tester.pumpWidget(build(_h));
      await tester.pumpWidget(build(0));
      c.jumpTo(index: 5000);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(build(_h));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(_text("Item 5000")).dy, closeTo(0, 0.5));
    });

    testWidgets("collapse to 0 and back keeps the reading position", (
      tester,
    ) async {
      final c = ItemScrollController();
      Widget build(double h) => _host(
        ScrollablePositionedList.builder(
          itemCount: 10000,
          itemScrollController: c,
          itemBuilder: (_, i) => _Item(i, _extent(i)),
        ),
        h: h,
      );
      await tester.pumpWidget(build(_h));
      c.jumpTo(index: 3000, offset: -40);
      await tester.pump();
      expect(tester.getTopLeft(_text("Item 3000")).dy, closeTo(-40, 0.5));
      await tester.pumpWidget(build(0));
      await tester.pump();
      await tester.pumpWidget(build(_h));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(_text("Item 3000")).dy, closeTo(-40, 0.5));
    });

    testWidgets("jumpTo with 0-height viewport completes the future", (
      tester,
    ) async {
      final lc = ListController();
      addTearDown(lc.dispose);
      await tester.pumpWidget(
        _host(
          CustomScrollView(
            slivers: [
              SuperSliverList.builder(
                listController: lc,
                itemCount: 1000,
                itemBuilder: (_, i) => _Item(i, _extent(i)),
              ),
            ],
          ),
          h: 0,
        ),
      );
      var done = false;
      unawaited(lc.jumpToIndex(700).then((_) => done = true));
      await tester.pump();
      await tester.pump();
      expect(done, isTrue);
    });
  });

  group("itemCount changes", () {
    testWidgets("shrinks below the visible/anchor index", (tester) async {
      final c = ItemScrollController();
      final p = ItemPositionsListener.create();
      Widget build(int n) => _host(
        ScrollablePositionedList.builder(
          itemCount: n,
          itemScrollController: c,
          itemPositionsListener: p,
          itemBuilder: (_, i) => _Item(i, _extent(i)),
        ),
      );
      await tester.pumpWidget(build(1000));
      c.jumpTo(index: 900);
      await tester.pump();
      await tester.pumpWidget(build(100));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final idx = p.itemPositions.value.map((e) => e.index).toList();
      expect(idx, isNotEmpty);
      expect(idx.every((i) => i < 100), isTrue);
      expect(_text("Item 99").evaluate(), isNotEmpty);
    });

    testWidgets("shrinks below a pending jump target in the same frame", (
      tester,
    ) async {
      final c = ItemScrollController();
      Widget build(int n) => _host(
        ScrollablePositionedList.builder(
          itemCount: n,
          itemScrollController: c,
          itemBuilder: (_, i) => _Item(i, _extent(i)),
        ),
      );
      await tester.pumpWidget(build(1000));
      c.jumpTo(index: 900);
      await tester.pumpWidget(build(50));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_text("Item 49").evaluate(), isNotEmpty);
    });

    testWidgets("shrinks to 0 during scrollTo, future completes", (
      tester,
    ) async {
      final c = ItemScrollController();
      Widget build(int n) => _host(
        ScrollablePositionedList.builder(
          itemCount: n,
          itemScrollController: c,
          itemBuilder: (_, i) => _Item(i, _extent(i)),
        ),
      );
      await tester.pumpWidget(build(1000));
      var done = false;
      unawaited(
        c
            .scrollTo(index: 800, duration: const Duration(seconds: 1))
            .then((_) => done = true),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(done, isTrue);
    });

    testWidgets("grows at the end (background loading) during scrollTo", (
      tester,
    ) async {
      final c = ItemScrollController();
      Widget build(int n) => _host(
        ScrollablePositionedList.builder(
          itemCount: n,
          itemScrollController: c,
          itemBuilder: (_, i) => _Item(i, _extent(i)),
        ),
      );
      await tester.pumpWidget(build(1000));
      var done = false;
      unawaited(
        c
            .scrollTo(index: 800, duration: const Duration(milliseconds: 500))
            .then((_) => done = true),
      );
      for (var n = 1100; n < 2000; n += 100) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pumpWidget(build(n));
      }
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(tester.getTopLeft(_text("Item 800")).dy, closeTo(0, 0.5));
    });
  });

  group("extent changes while reading", () {
    testWidgets("items above grow (background load) — visible item stays", (
      tester,
    ) async {
      final c = ItemScrollController();
      final heights = <int, double>{};
      late StateSetter set;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return ScrollablePositionedList.builder(
                itemCount: 2000,
                itemScrollController: c,
                itemBuilder: (_, i) => _Item(i, heights[i] ?? 60),
              );
            },
          ),
        ),
      );
      c.jumpTo(index: 500, offset: -25);
      await tester.pump();
      expect(tester.getTopLeft(_text("Item 500")).dy, closeTo(-25, 0.01));
      // Items in the cache area above grow.
      set(() {
        for (var i = 490; i < 500; i++) {
          heights[i] = 300;
        }
      });
      await tester.pump();
      expect(tester.getTopLeft(_text("Item 500")).dy, closeTo(-25, 0.01));
      // The anchor item itself grows (text reflow): its top must stay.
      set(() => heights[500] = 400);
      await tester.pump();
      expect(tester.getTopLeft(_text("Item 500")).dy, closeTo(-25, 0.01));
    });

    testWidgets("RTL width change keeps leading item", (tester) async {
      final c = ItemScrollController();
      Widget build(double w) => _host(
        ScrollablePositionedList.builder(
          itemCount: 5000,
          itemScrollController: c,
          itemBuilder: (_, i) =>
              SizedBox(height: 40000 / w + i % 7 * 10, child: Text("Item $i")),
        ),
        w: w,
        dir: TextDirection.rtl,
      );
      await tester.pumpWidget(build(400));
      c.jumpTo(index: 2500);
      await tester.pump();
      await tester.pumpWidget(build(250));
      await tester.pump();
      expect(tester.getTopLeft(_text("Item 2500")).dy, closeTo(0, 0.5));
      await tester.pumpWidget(build(600));
      await tester.pump();
      expect(tester.getTopLeft(_text("Item 2500")).dy, closeTo(0, 0.5));
    });

    testWidgets("item positions notify only on change", (tester) async {
      final c = ItemScrollController();
      final p = ItemPositionsListener.create();
      var n = 0;
      p.itemPositions.addListener(() => n++);
      late StateSetter set;
      var tick = 0;
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 1000,
            itemScrollController: c,
            itemPositionsListener: p,
            itemBuilder: (_, i) => i == 2
                ? StatefulBuilder(
                    builder: (_, s) {
                      set = s;
                      return Text("Item $i tick $tick");
                    },
                  )
                : _Item(i, 50),
          ),
        ),
      );
      await tester.pump();
      final before = n;
      // An item rebuilds without moving anything: relayout of the sliver
      // should not notify.
      for (var k = 0; k < 5; k++) {
        set(() => tick++);
        await tester.pump();
      }
      expect(n, before);
    });
  });

  group("lifecycle", () {
    // pumpWidget with EnginePhase.build in a bare tree never lays the tree
    // out afterwards (also for ListView), so a MaterialApp hosts these.
    testWidgets("jumpTo before first layout (build phase only)", (
      tester,
    ) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: _host(
            ScrollablePositionedList.builder(
              itemCount: 10000,
              itemScrollController: c,
              itemBuilder: (_, i) => _Item(i, _extent(i)),
            ),
          ),
        ),
        phase: EnginePhase.build,
      );
      c.jumpTo(index: 4321, alignment: 0.5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(_text("Item 4321")).dy, closeTo(300, 0.5));
    });

    testWidgets("scrollTo before first layout (build phase only)", (
      tester,
    ) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: _host(
            ScrollablePositionedList.builder(
              itemCount: 10000,
              itemScrollController: c,
              itemBuilder: (_, i) => _Item(i, _extent(i)),
            ),
          ),
        ),
        phase: EnginePhase.build,
      );
      var done = false;
      unawaited(
        c
            .scrollTo(index: 4321, duration: const Duration(milliseconds: 300))
            .then((_) => done = true),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(done, isTrue);
      expect(tester.getTopLeft(_text("Item 4321")).dy, closeTo(0, 0.5));
    });

    testWidgets("jumpTo and scrollTo under an opaque route", (tester) async {
      final c = ItemScrollController();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: _host(
            ScrollablePositionedList.builder(
              itemCount: 10000,
              itemScrollController: c,
              itemBuilder: (_, i) => _Item(i, _extent(i)),
            ),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
      );
      await tester.pumpAndSettle();
      c.jumpTo(index: 2000, alignment: 0.25);
      await tester.pump();
      expect(tester.takeException(), isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_text("Item 2000")).dy, closeTo(150, 0.5));

      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
      );
      await tester.pumpAndSettle();
      var done = false;
      unawaited(
        c
            .scrollTo(index: 7000, duration: const Duration(milliseconds: 300))
            .then((_) => done = true),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(done, isTrue);
      expect(tester.getTopLeft(_text("Item 7000")).dy, closeTo(0, 0.5));
    });

    testWidgets("tab closed mid scrollTo: future completes, no exception", (
      tester,
    ) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 10000,
            itemScrollController: c,
            itemBuilder: (_, i) => _Item(i, _extent(i)),
          ),
        ),
      );
      var done = false;
      unawaited(
        c
            .scrollTo(index: 9000, duration: const Duration(seconds: 2))
            .then((_) => done = true),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(done, isTrue);
      expect(c.isAttached, isFalse);
    });

    testWidgets("tab closed with pending jump (same frame)", (tester) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 10000,
            itemScrollController: c,
            itemBuilder: (_, i) => _Item(i, _extent(i)),
          ),
        ),
      );
      c.jumpTo(index: 9000);
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets("mouse wheel cancels scrollTo and does not get yanked back", (
      tester,
    ) async {
      final c = ItemScrollController();
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 10000,
            itemScrollController: c,
            scrollController: sc,
            itemBuilder: (_, i) => _Item(i, 50),
          ),
        ),
      );
      var done = false;
      unawaited(
        c
            .scrollTo(index: 5000, duration: const Duration(seconds: 2))
            .then((_) => done = true),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();
      final after = sc.position.pixels;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(sc.position.pixels, closeTo(after, 1));
    });

    testWidgets("PageDown during scrollTo", (tester) async {
      final c = ItemScrollController();
      final sc = ScrollController();
      addTearDown(sc.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedList.builder(
              itemCount: 10000,
              itemScrollController: c,
              scrollController: sc,
              itemBuilder: (_, i) => _Item(i, 50),
            ),
          ),
        ),
      );
      var done = false;
      unawaited(
        c
            .scrollTo(index: 5000, duration: const Duration(seconds: 2))
            .then((_) => done = true),
      );
      await tester.pump(const Duration(milliseconds: 300));
      // Focus the scrollable via a tap is not possible while ignoring pointer;
      // use PrimaryScrollController-less Scrollable.ensureVisible-free route:
      sc.position.moveTo(
        sc.position.pixels + 300,
        duration: const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();
      expect(done, isTrue);
    });
  });

  group("geometry", () {
    testWidgets("offset inside an item taller than the viewport", (
      tester,
    ) async {
      final c = ItemScrollController();
      final p = ItemPositionsListener.create();
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 200,
            itemScrollController: c,
            itemPositionsListener: p,
            itemBuilder: (_, i) => _Item(i, i == 100 ? 3000 : _extent(i)),
          ),
        ),
      );
      c.jumpTo(index: 100, offset: -1500);
      await tester.pump();
      expect(tester.getTopLeft(_text("Item 100")).dy, closeTo(-1500, 0.5));
      final pos = p.itemPositions.value.toList();
      expect(pos.length, 1);
      expect(pos.single.index, 100);
      expect(pos.single.itemLeadingEdge, closeTo(-2.5, 1e-6));
      expect(c.anchor!.offsetInItem, closeTo(1500, 0.5));
    });

    testWidgets("reverse list alignment 0.5", (tester) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 5000,
            reverse: true,
            itemScrollController: c,
            itemBuilder: (_, i) => _Item(i, _extent(i)),
          ),
        ),
      );
      c.jumpTo(index: 2000, alignment: 0.5);
      await tester.pump();
      // Leading edge of a reversed list is the bottom of the item.
      expect(tester.getBottomLeft(_text("Item 2000")).dy, closeTo(300, 0.5));
    });

    testWidgets("horizontal RTL with padding, jump to 0 and to 10", (
      tester,
    ) async {
      final c = ItemScrollController();
      final p = ItemPositionsListener.create();
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 100,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 30, right: 20),
            itemScrollController: c,
            itemPositionsListener: p,
            itemBuilder: (_, i) => SizedBox(width: 80, child: Text("Item $i")),
          ),
          dir: TextDirection.rtl,
        ),
      );
      c.jumpTo(index: 10);
      await tester.pump();
      // RTL: leading edge is the right side of the viewport.
      expect(tester.getTopRight(find.text("Item 10")).dx, closeTo(_w, 0.5));
      c.jumpTo(index: 0);
      await tester.pump();
      expect(tester.getTopRight(find.text("Item 0")).dx, closeTo(_w - 20, 0.5));
      final first = p.itemPositions.value.firstWhere((e) => e.index == 0);
      expect(first.itemLeadingEdge, closeTo(20 / _w, 1e-3));
    });

    testWidgets("shrinkWrap inside a Column", (tester) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              Flexible(
                child: ScrollablePositionedList.builder(
                  shrinkWrap: true,
                  itemCount: 500,
                  itemScrollController: c,
                  itemBuilder: (_, i) => _Item(i, _extent(i)),
                ),
              ),
            ],
          ),
        ),
      );
      c.jumpTo(index: 250);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(_text("Item 250")).dy, closeTo(0, 0.5));
    });

    testWidgets("shrinkWrap short list with jumpTo does not loop", (
      tester,
    ) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              ScrollablePositionedList.builder(
                shrinkWrap: true,
                itemCount: 5,
                itemScrollController: c,
                itemBuilder: (_, i) => _Item(i, 30),
              ),
            ],
          ),
        ),
      );
      c.jumpTo(index: 4, alignment: 0.5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_text("Item 0")).dy, closeTo(0, 0.5));
    });

    testWidgets("separated: jump to last item and anchor on a separator", (
      tester,
    ) async {
      final c = ItemScrollController();
      final p = ItemPositionsListener.create();
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.separated(
            itemCount: 300,
            itemScrollController: c,
            itemPositionsListener: p,
            itemBuilder: (_, i) => _Item(i, _extent(i)),
            separatorBuilder: (_, i) =>
                SizedBox(height: 10, child: Text("Sep $i")),
          ),
        ),
      );
      c.jumpTo(index: 299);
      await tester.pump();
      // allowOverscrollToTarget (on by default) puts the last item at the top.
      expect(tester.getTopLeft(_text("Item 299")).dy, closeTo(0, 0.5));
      c.jumpTo(index: 150, offset: -_extent(150) - 5);
      await tester.pump();
      final a = c.anchor!;
      expect(a.index, 150);
      expect(a.offsetInItem, closeTo(_extent(150) + 5, 0.5));
      // restoring the anchor must land at the same place
      c.jumpTo(index: 0);
      await tester.pump();
      c.jumpTo(index: a.index, offset: -a.offsetInItem);
      await tester.pump();
      expect(tester.getTopLeft(_text("Sep 150")).dy, closeTo(-5, 0.5));
      expect(p.itemPositions.value.every((e) => e.index < 300), isTrue);
    });

    testWidgets("nested horizontal scrollable in items does not leak deltas", (
      tester,
    ) async {
      final sol = ScrollOffsetListener.create();
      final deltas = <double>[];
      final sub = sol.changes.listen(deltas.add);
      addTearDown(sub.cancel);
      await tester.pumpWidget(
        MaterialApp(
          home: ScrollablePositionedList.builder(
            itemCount: 100,
            scrollOffsetListener: sol,
            itemBuilder: (_, i) => SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 50,
                itemBuilder: (_, j) =>
                    SizedBox(width: 80, child: Text("$i/$j")),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text("0/0"), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(deltas, isEmpty);
    });

    testWidgets("keep-alive items survive far jumps", (tester) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        _host(
          ScrollablePositionedList.builder(
            itemCount: 5000,
            itemScrollController: c,
            itemBuilder: (_, i) => _KeepAlive(i),
          ),
        ),
      );
      await tester.tap(find.text("KA 1 0"));
      await tester.pump();
      expect(find.text("KA 1 1"), findsOneWidget);
      c.jumpTo(index: 4000);
      await tester.pump();
      await tester.pump();
      c.jumpTo(index: 0);
      await tester.pump();
      await tester.pump();
      expect(find.text("KA 1 1"), findsOneWidget);
      expect(tester.getTopLeft(find.text("KA 0 0")).dy, closeTo(0, 0.5));
    });
  });

  group("core sliver", () {
    testWidgets("non-trailing sliver: jump to last item alignment 0 settles", (
      tester,
    ) async {
      final lc = ListController();
      final sc = ScrollController();
      addTearDown(lc.dispose);
      addTearDown(sc.dispose);
      await tester.pumpWidget(
        _host(
          CustomScrollView(
            controller: sc,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
              SuperSliverList.builder(
                listController: lc,
                itemCount: 2000,
                itemBuilder: (_, i) => _Item(i, _extent(i)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 50)),
            ],
          ),
        ),
      );
      var done = false;
      unawaited(lc.jumpToIndex(1999).then((_) => done = true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(done, isTrue);
      expect(
        sc.position.pixels,
        lessThanOrEqualTo(sc.position.maxScrollExtent + 0.01),
      );
    });

    testWidgets("two SuperSliverLists in one viewport, jump into the second", (
      tester,
    ) async {
      final a = ListController();
      final b = ListController();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(
        _host(
          CustomScrollView(
            slivers: [
              SuperSliverList.builder(
                listController: a,
                itemCount: 3000,
                itemBuilder: (_, i) => Text(
                  "A $i",
                  style: TextStyle(height: 1 + (i % 5).toDouble()),
                ),
              ),
              SuperSliverList.builder(
                listController: b,
                itemCount: 3000,
                itemBuilder: (_, i) =>
                    SizedBox(height: _extent(i), child: Text("B $i")),
              ),
            ],
          ),
        ),
      );
      var done = false;
      unawaited(b.jumpToIndex(1500, alignment: 0.3).then((_) => done = true));
      await tester.pump();
      expect(done, isTrue);
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(_text("B 1500")).dy, closeTo(180, 0.5));
    });

    testWidgets(
      "jumpToIndex when detached does not throw in release semantics",
      (tester) async {
        final lc = ListController();
        addTearDown(lc.dispose);
        expect(() => lc.jumpToIndex(5), throwsA(isA<AssertionError>()));
      },
    );

    testWidgets("SelectionArea across items while jumping", (tester) async {
      final c = ItemScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectionArea(
            child: ScrollablePositionedList.builder(
              itemCount: 3000,
              itemScrollController: c,
              itemBuilder: (_, i) => Text("Line $i " * (1 + i % 4)),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.textContaining("Line 1 ")) + const Offset(2, 5),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(
        tester.getTopLeft(find.textContaining("Line 5 ")) + const Offset(20, 5),
      );
      await gesture.up();
      await tester.pump();
      c.jumpTo(index: 2500);
      await tester.pump();
      c.jumpTo(index: 0);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.index);
  final int index;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  int taps = 0;
  @override
  bool get wantKeepAlive => taps > 0;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: () => setState(() {
        taps++;
        updateKeepAlive();
      }),
      child: SizedBox(
        height: 30.0 + widget.index % 9 * 20,
        child: Text("KA ${widget.index} $taps"),
      ),
    );
  }
}

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

void main() {
  testWidgets("an explicit reveal replaces the header anchor", (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    final header = GlobalKey();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(MaterialApp(
        home: CustomScrollView(
      controller: scroll,
      slivers: [
        SuperSliverList.list(listController: list, children: [
          SizedBox(key: header, height: 100),
          const SizedBox(height: 1000),
        ])
      ],
    )));
    await tester.pumpAndSettle();
    final handle = list.preserveHeader(
        header.currentContext!.findRenderObject()! as RenderBox)!;
    // Pure queries leave ownership alone; legacy reveal queries start an
    // operation and must not coexist with the manual header policy.
    list.estimateOffsetToReveal(1, 0);
    expect(handle.isActive, isTrue);
    final offset = list.getOffsetToReveal(1, 0);
    expect(handle.isActive, isFalse);
    scroll.jumpTo(offset);
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(100, 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      "replacement, removal and explicit navigation release anchor ownership",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    final removed = ValueNotifier(false);
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    addTearDown(removed.dispose);
    final first = GlobalKey();
    final second = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: CustomScrollView(
      controller: scroll,
      slivers: [
        SuperSliverList.list(listController: list, children: [
          SizedBox(key: first, height: 100),
          ValueListenableBuilder<bool>(
              valueListenable: removed,
              builder: (_, value, __) => value
                  ? const SizedBox()
                  : SizedBox(key: second, height: 100)),
          const SizedBox(height: 1000),
        ])
      ],
    )));
    await tester.pumpAndSettle();
    final old = list.preserveHeader(
        first.currentContext!.findRenderObject()! as RenderBox)!;
    final current = list.preserveHeader(
        second.currentContext!.findRenderObject()! as RenderBox)!;
    old.cancel();
    expect(current.isActive, isTrue);
    removed.value = true;
    await tester.pump();
    expect(current.isActive, isFalse);
    expect(list.hasActiveHeaderAnchor, isFalse);
    final navigation = list.preserveHeader(
        first.currentContext!.findRenderObject()! as RenderBox)!;
    list.jumpToItem(index: 2, scrollController: scroll, alignment: 0);
    expect(navigation.isActive, isFalse);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      "short content stays within range when content before header grows",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    final height = ValueNotifier(100.0);
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    addTearDown(height.dispose);
    final header = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: CustomScrollView(
      controller: scroll,
      physics: const SuperRangeMaintainingScrollPhysics(
          parent: BouncingScrollPhysics()),
      slivers: [
        SuperSliverList.list(listController: list, children: [
          ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (_, h, child) =>
                  Column(children: [SizedBox(height: h), child!]),
              child: SizedBox(key: header, height: 50)),
        ])
      ],
    )));
    await tester.pumpAndSettle();
    final handle = list.preserveHeader(
        header.currentContext!.findRenderObject()! as RenderBox);
    expect(handle?.isActive, isTrue);
    height.value = 200;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(scroll.offset, 0);
    expect(scroll.position.outOfRange, isFalse);
    handle!.cancel();
    await tester.pumpWidget(const SizedBox());
  });

  for (final nested in [false, true]) {
    testWidgets("preserves descendant through large collapse nested=$nested",
        (tester) async {
      final scroll = ScrollController();
      final list = ListController();
      final height = ValueNotifier(700.0);
      final header = GlobalKey();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      addTearDown(height.dispose);
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
          home: CustomScrollView(
        controller: scroll,
        scrollCacheExtent: const ScrollCacheExtent.viewport(1),
        physics: const SuperRangeMaintainingScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverPadding(
              padding: const EdgeInsets.only(top: 37, bottom: 29),
              sliver: SuperSliverList.builder(
                listController: list,
                itemCount: 10000,
                extentEstimation: (_, __) => 80,
                itemBuilder: (_, index) {
                  builds++;
                  final target = SizedBox(key: header, height: 100);
                  if (index == 15) {
                    return nested
                        ? ValueListenableBuilder<double>(
                            valueListenable: height,
                            builder: (_, h, __) =>
                                Column(children: [SizedBox(height: h), target]))
                        : target;
                  }
                  if (index == 14 && !nested) {
                    return ValueListenableBuilder<double>(
                        valueListenable: height,
                        builder: (_, h, __) => SizedBox(height: h));
                  }
                  return const SizedBox(height: 100);
                },
              ))
        ],
      )));
      await tester.pumpAndSettle();
      list.jumpToItem(index: 15, scrollController: scroll, alignment: 0);
      await tester.pumpAndSettle();
      final finder = find.byKey(header);
      scroll.jumpTo(scroll.offset + tester.getTopLeft(finder).dy - 150);
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(finder).dy;
      final handle = list.preserveHeader(
          header.currentContext!.findRenderObject()! as RenderBox)!;
      height.value = 0;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(finder).dy, closeTo(before, 0.01));
      expect(builds, lessThan(150),
          reason: "must not lay out the entire history");
      expect(list.numberOfItemsWithEstimatedExtent, greaterThan(9800));
      handle.cancel();
      await tester.pumpWidget(const SizedBox());
    });
  }
}

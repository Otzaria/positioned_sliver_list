import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

void main() {
  testWidgets(
    "scroll pixels include preceding slivers outside the paint area",
    (tester) async {
      final scroll = ScrollController();
      final list = ListController();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 400,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 150)),
                SliverPadding(
                  padding: const EdgeInsets.only(top: 30),
                  sliver: SuperSliverList.builder(
                    listController: list,
                    itemCount: 5000,
                    extentEstimation: (_, _) => 100,
                    itemBuilder: (_, index) =>
                        SizedBox(key: ValueKey(index), height: 100),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      void verifyPixels() {
        for (final pixels in [0.0, 149.0, 150.0, 179.0]) {
          expect(list.indexForScrollOffset(pixels), isNull);
        }
        expect(list.indexForScrollOffset(180), 0);
        expect(list.indexForScrollOffset(279), 0);
        expect(list.indexForScrollOffset(280), 1);
        expect(list.indexForScrollOffset(100180), 1000);
      }

      verifyPixels();
      final jump = list.jumpToIndex(1000);
      await tester.pumpAndSettle();
      await jump;
      expect(scroll.offset, closeTo(100180, 0.01));
      verifyPixels();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets("merged estimate batches preserve a measured reading anchor", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(
      _viewport(
        scroll: scroll,
        list: list,
        count: 5000,
        itemBuilder: (_, index) => SizedBox(key: ValueKey(index), height: 100),
      ),
    );
    final placement = list.jumpToIndex(250, offset: -37);
    await tester.pumpAndSettle();
    await placement;
    final first = list.updateEstimatedExtents({0: 200, 4999: 300});
    final second = list.updateEstimatedExtents({0: 250, 100: 180, 4999: 400});
    await tester.pump();
    await Future.wait([first, second]);
    expect(list.anchor!.index, 250);
    expect(list.anchor!.offsetInItem, closeTo(37, 0.01));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(250))).dy,
      closeTo(-37, 0.01),
    );
    expect(list.extentForIndex(0), (250.0, true));
    expect(list.extentForIndex(4999), (400.0, true));
    expect(find.byKey(const ValueKey(4999)), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("detaching completes estimate batches before reattachment", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    Widget view() => _viewport(
      scroll: scroll,
      list: list,
      count: 5000,
      itemBuilder: (_, index) => SizedBox(key: ValueKey(index), height: 100),
    );
    await tester.pumpWidget(view());
    var firstCompleted = false;
    var secondCompleted = false;
    final first = list.updateEstimatedExtents({4000: 300}).then((_) {
      firstCompleted = true;
    });
    final second = list.updateEstimatedExtents({4001: 400}).then((_) {
      secondCompleted = true;
    });
    await tester.pumpWidget(const SizedBox());
    expect(firstCompleted, isTrue);
    expect(secondCompleted, isTrue);
    await Future.wait([first, second]);
    expect(list.isAttached, isFalse);
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(list.extentForIndex(4000), (100.0, true));
    expect(list.extentForIndex(4001), (100.0, true));
    expect(list.anchor!.index, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("wheel cancels a distant reveal before delayed content grows", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    final height = ValueNotifier(100.0);
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      _viewport(
        scroll: scroll,
        list: list,
        count: 1000,
        itemBuilder: (_, index) => index == 900
            ? ValueListenableBuilder<double>(
                valueListenable: height,
                builder: (_, value, _) =>
                    SizedBox(key: const ValueKey(900), height: value),
              )
            : SizedBox(key: ValueKey(index), height: 100),
      ),
    );
    await tester.pumpAndSettle();
    final animation = list.scrollToIndex(
      900,
      duration: const Duration(milliseconds: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, -80),
      ),
    );
    await tester.pumpAndSettle();
    await animation;
    expect(animation.isAnimating, isFalse);
    final userOffset = scroll.offset;
    height.value = 800;
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(userOffset, 0.01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("detaching completes a reveal without canceling a new list", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    Widget view() => _viewport(
      scroll: scroll,
      list: list,
      count: 1000,
      itemBuilder: (_, index) => SizedBox(key: ValueKey(index), height: 100),
    );
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    final old = list.scrollToIndex(900, duration: const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pumpWidget(const SizedBox());
    await old;
    expect(old.isAnimating, isFalse);
    expect(list.isAttached, isFalse);
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    final current = list.scrollToIndex(
      30,
      duration: const Duration(milliseconds: 100),
    );
    old.cancel();
    await tester.pumpAndSettle();
    await current;
    expect(tester.getTopLeft(find.byKey(const ValueKey(30))).dy, closeTo(0, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("identity based animation follows a reordered stateful item", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    var ids = List<int>.generate(100, (index) => index);
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
                return CustomScrollView(
                  controller: scroll,
                  scrollCacheExtent: const ScrollCacheExtent.viewport(2),
                  slivers: [
                    SuperSliverList.builder(
                      listController: list,
                      itemCount: ids.length,
                      findChildIndexCallback: (key) =>
                          ids.indexOf((key as ValueKey<int>).value),
                      extentEstimation: (index, _) =>
                          index == null ? 0 : 80.0 + ids[index] % 3 * 20,
                      itemBuilder: (_, index) => _IdentityItem(
                        key: ValueKey(ids[index]),
                        id: ids[index],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey(3));
    final identity = tester.state(target);
    final animation = list.animateToItem(
      index: () => ids.indexOf(3),
      scrollController: scroll,
      alignment: 0,
      duration: (_) => const Duration(milliseconds: 300),
      curve: (_) => Curves.linear,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    rebuild(() {
      ids = List.of(ids)..remove(3);
      ids.insert(8, 3);
    });
    await tester.pumpAndSettle();
    await animation;
    expect(tester.state(target), same(identity));
    expect(tester.getTopLeft(target).dy, closeTo(0, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final shrinkWrap in [false, true]) {
    testWidgets(
      "preserves a commentary header through collapse shrinkWrap=$shrinkWrap",
      (tester) async {
        final scroll = ScrollController();
        final list = ListController();
        final height = ValueNotifier(500.0);
        final header = GlobalKey();
        addTearDown(scroll.dispose);
        addTearDown(list.dispose);
        addTearDown(height.dispose);
        await tester.pumpWidget(
          _viewport(
            scroll: scroll,
            list: list,
            count: 1000,
            shrinkWrap: shrinkWrap,
            itemBuilder: (_, index) => index == 15
                ? ValueListenableBuilder<double>(
                    valueListenable: height,
                    builder: (_, value, _) => Column(
                      children: [
                        SizedBox(height: value),
                        SizedBox(key: header, height: 50),
                      ],
                    ),
                  )
                : const SizedBox(height: 100),
          ),
        );
        await tester.pumpAndSettle();
        final jump = list.jumpToIndex(15, offset: -400);
        await tester.pumpAndSettle();
        await jump;
        final before = tester.getTopLeft(find.byKey(header)).dy;
        expect(before, closeTo(100, 1));
        final handle = list.preserveHeader(
          header.currentContext!.findRenderObject()! as RenderBox,
        );
        expect(handle, isNotNull);
        height.value = 0;
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(header)).dy, closeTo(before, 0.01));
        handle!.cancel();
        expect(list.hasActiveHeaderAnchor, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets("wheel opt out survives delayed footer growth and grace expiry", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    final height = ValueNotifier(100.0);
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      _viewport(
        scroll: scroll,
        list: list,
        count: 20,
        initial: InitialScrollPosition.end,
        stick: const StickTarget.bottom(),
        itemBuilder: (_, index) => index == 19
            ? ValueListenableBuilder<double>(
                valueListenable: height,
                builder: (_, value, _) => SizedBox(height: value),
              )
            : const SizedBox(height: 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(list.stickTarget, const StickTarget.bottom());
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, -200),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final userOffset = scroll.offset;
    expect(list.stickTarget, isNull);
    height.value = 800;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(scroll.offset, closeTo(userOffset, 0.01));
    expect(scroll.position.extentAfter, greaterThan(600));
    expect(list.stickTarget, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _viewport({
  required ScrollController scroll,
  required ListController list,
  required int count,
  required IndexedWidgetBuilder itemBuilder,
  bool shrinkWrap = false,
  InitialScrollPosition initial = InitialScrollPosition.start,
  StickTarget? stick,
}) {
  final view = CustomScrollView(
    controller: scroll,
    shrinkWrap: shrinkWrap,
    scrollCacheExtent: const ScrollCacheExtent.viewport(2),
    slivers: [
      SuperSliverList.builder(
        listController: list,
        initialScrollPosition: initial,
        itemCount: count,
        extentEstimation: (_, _) => 100,
        itemBuilder: itemBuilder,
      ),
    ],
  );
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 400,
        child: stick == null
            ? view
            : StickToTarget(
                scrollController: scroll,
                listController: list,
                target: stick,
                child: view,
              ),
      ),
    ),
  );
}

class _IdentityItem extends StatefulWidget {
  const _IdentityItem({required this.id, super.key});
  final int id;

  @override
  State<_IdentityItem> createState() => _IdentityItemState();
}

class _IdentityItemState extends State<_IdentityItem> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 80.0 + widget.id % 3 * 20,
    child: Text("Paragraph ${widget.id}"),
  );
}

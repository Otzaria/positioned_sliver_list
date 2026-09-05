import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

void main() {
  testWidgets("one animation request owns every attached scroll position",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      Expanded(
          child: CustomScrollView(controller: scroll, slivers: [
        SuperSliverList.builder(
            listController: list,
            itemCount: 30,
            extentEstimation: (_, __) => 100,
            itemBuilder: (_, index) => const SizedBox(height: 100)),
      ])),
      Expanded(
          child: ListView.builder(
              controller: scroll,
              itemCount: 30,
              itemBuilder: (_, index) => const SizedBox(height: 100))),
    ])));
    await tester.pumpAndSettle();
    expect(scroll.positions, hasLength(2));
    list.animateToItem(
        index: () => 10,
        scrollController: scroll,
        alignment: 0,
        duration: (_) => const Duration(milliseconds: 100),
        curve: (_) => Curves.linear);
    await tester.pumpAndSettle();
    for (final position in scroll.positions) {
      expect(position.pixels, closeTo(1000, 1));
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final cancel in [true, false]) {
    testWidgets("pending reveal canceled without replacement=$cancel",
        (tester) async {
      final scroll = ScrollController();
      final list = ListController();
      final height = ValueNotifier(100.0);
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      addTearDown(height.dispose);
      await tester.pumpWidget(MaterialApp(
          home: CustomScrollView(
        controller: scroll,
        scrollCacheExtent: const ScrollCacheExtent.viewport(1),
        slivers: [
          SuperSliverList.builder(
            listController: list,
            initialScrollPosition: InitialScrollPosition.end,
            extentEstimation: (_, __) => 100,
            itemCount: 20,
            itemBuilder: (_, index) => index == 15
                ? ValueListenableBuilder<double>(
                    valueListenable: height,
                    builder: (_, h, __) => SizedBox(height: h))
                : const SizedBox(height: 100),
          )
        ],
      )));
      await tester.pumpAndSettle();
      final before = scroll.offset;
      list.getOffsetToReveal(19, 0, rect: const Rect.fromLTWH(0, 0, 0, 1));
      list.cancelPositioning();
      if (!cancel) {
        list.getOffsetToReveal(19, 0, rect: const Rect.fromLTWH(0, 0, 0, 1));
      }
      height.value = 500;
      await tester.pump();
      expect(scroll.offset, cancel ? before : before + 400);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("canceling an old animation does not cancel its replacement",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(MaterialApp(
        home: CustomScrollView(
      controller: scroll,
      slivers: [
        SuperSliverList.builder(
            listController: list,
            itemCount: 100,
            extentEstimation: (_, __) => 100,
            itemBuilder: (_, index) =>
                SizedBox(key: ValueKey(index), height: 100))
      ],
    )));
    await tester.pumpAndSettle();
    AnimationHandle animate(int index) => list.animateToItem(
        index: () => index,
        scrollController: scroll,
        alignment: 0,
        duration: (_) => const Duration(milliseconds: 100),
        curve: (_) => Curves.linear);
    final old = animate(10);
    await tester.pump(const Duration(milliseconds: 16));
    final replacement = animate(20);
    old.cancel();
    await tester.pumpAndSettle();
    expect(replacement.isAnimating, isFalse);
    expect(tester.getTopLeft(find.byKey(const ValueKey(20))).dy, closeTo(0, 1));
    final canceled = animate(30);
    list.cancelPositioning();
    expect(canceled.isAnimating, isFalse);
    final stopped = scroll.offset;
    await tester.pumpAndSettle();
    expect(scroll.offset, stopped);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("canceled stick target cannot leave a render reveal correction",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    final toolHeight = ValueNotifier(100.0);
    final responseHeight = ValueNotifier(100.0);
    final target = ValueNotifier<StickTarget?>(const StickTarget(
        index: 19, alignment: 0, rect: Rect.fromLTWH(0, 0, 0, 1)));
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    addTearDown(toolHeight.dispose);
    addTearDown(responseHeight.dispose);
    addTearDown(target.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: ValueListenableBuilder<StickTarget?>(
        valueListenable: target,
        builder: (context, t, child) => Listener(
          onPointerDown: (_) => target.value = null,
          child: StickToTarget(
              scrollController: scroll,
              listController: list,
              target: t,
              child: child!),
        ),
        child: CustomScrollView(
          controller: scroll,
          physics: const SuperRangeMaintainingScrollPhysics(),
          scrollCacheExtent: const ScrollCacheExtent.viewport(1),
          slivers: [
            SuperSliverList.builder(
              listController: list,
              initialScrollPosition: InitialScrollPosition.end,
              extentEstimation: (index, cross) => 100,
              itemCount: 20,
              itemBuilder: (context, index) => index == 15 || index == 19
                  ? ValueListenableBuilder<double>(
                      valueListenable:
                          index == 15 ? toolHeight : responseHeight,
                      builder: (context, h, _) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => toolHeight.value = 500,
                          child: SizedBox(
                              key: ValueKey("item-$index"), height: h)))
                  : const SizedBox(height: 100),
            )
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    responseHeight.value = 110;
    await tester.pump();
    final header = find.byKey(const ValueKey("item-15"));
    final before = tester.getTopLeft(header).dy;
    await tester.tapAt(tester.getTopLeft(header) + const Offset(50, 50));
    await tester.pump();
    expect(list.stickTarget, isNull);
    expect(tester.getTopLeft(header).dy, before);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}

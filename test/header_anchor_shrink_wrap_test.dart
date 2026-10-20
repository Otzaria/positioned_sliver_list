import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

void main() {
  for (final nextHeight in [0.0, 1000.0]) {
    testWidgets("shrink-wrap header stays fixed at height $nextHeight", (
      tester,
    ) async {
      final scroll = ScrollController();
      final list = ListController();
      final height = ValueNotifier(500.0);
      final header = GlobalKey();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      addTearDown(height.dispose);
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 400,
              child: CustomScrollView(
                controller: scroll,
                shrinkWrap: true,
                scrollCacheExtent: const ScrollCacheExtent.viewport(2),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 37, bottom: 29),
                    sliver: SuperSliverList.builder(
                      listController: list,
                      itemCount: 10000,
                      extentEstimation: (_, _) => 100,
                      itemBuilder: (_, index) {
                        built++;
                        if (index != 15) return const SizedBox(height: 100);
                        return ValueListenableBuilder<double>(
                          valueListenable: height,
                          builder: (_, value, _) => Column(
                            children: [
                              SizedBox(height: value),
                              SizedBox(key: header, height: 50),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final jump = list.jumpToIndex(15, offset: -400);
      await tester.pumpAndSettle();
      await jump;
      final before = tester.getTopLeft(find.byKey(header)).dy;
      expect(before, closeTo(100, 0.01));
      final handle = list.preserveHeader(
        header.currentContext!.findRenderObject()! as RenderBox,
      );
      expect(handle?.isActive, isTrue);
      height.value = nextHeight;
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(header)).dy, closeTo(before, 0.01));
      expect(built, lessThan(120));
      expect(list.numberOfItemsWithEstimatedExtent, greaterThan(9800));
      expect(tester.takeException(), isNull);
      handle!.cancel();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("unbounded shrink wrap clamps header anchoring to its range", (
    tester,
  ) async {
    final scroll = ScrollController();
    final list = ListController();
    final height = ValueNotifier(100.0);
    final header = GlobalKey();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            CustomScrollView(
              controller: scroll,
              shrinkWrap: true,
              slivers: [
                SuperSliverList.list(
                  listController: list,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: height,
                      builder: (_, value, _) => Column(
                        children: [
                          SizedBox(height: value),
                          SizedBox(key: header, height: 50),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = list.preserveHeader(
      header.currentContext!.findRenderObject()! as RenderBox,
    );
    expect(handle?.isActive, isTrue);
    height.value = 200;
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(scroll.position.maxScrollExtent, 0);
    expect(scroll.position.outOfRange, isFalse);
    expect(tester.takeException(), isNull);
    handle!.cancel();
    await tester.pumpWidget(const SizedBox());
  });
}

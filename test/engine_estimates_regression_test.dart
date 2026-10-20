import "dart:async";

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

void main() {
  testWidgets("explicit initial index zero consumes leading padding", (
    tester,
  ) async {
    final controller = ListController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 30),
              sliver: SuperSliverList.builder(
                listController: controller,
                initialIndex: 0,
                itemCount: 100,
                itemBuilder: (_, index) =>
                    SizedBox(key: ValueKey(index), height: 100),
              ),
            ),
          ],
        ),
      ),
    );
    final top = tester.getTopLeft(find.byKey(const ValueKey(0))).dy;
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(top, closeTo(0, 0.01));
  });

  for (final estimate in [100.0, 10.0, 1.0, 0.1, 0.001]) {
    testWidgets(
      "far jump with estimate $estimate only builds near the target",
      (tester) async {
        final controller = ListController();
        final built = <int>{};
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 600,
                child: CustomScrollView(
                  slivers: [
                    SuperSliverList.builder(
                      listController: controller,
                      itemCount: 50000,
                      extentEstimation: (_, _) => estimate,
                      itemBuilder: (_, index) {
                        built.add(index);
                        return SizedBox(key: ValueKey(index), height: 100);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        built.clear();
        unawaited(controller.jumpToIndex(30000, alignment: 0.5));
        await tester.pump();
        await tester.pump();
        final count = built.length;
        final targetTop = tester
            .getTopLeft(find.byKey(const ValueKey(30000)))
            .dy;
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        expect(count, lessThan(30));
        expect(targetTop, closeTo(300, 0.01));
      },
    );
  }
}

import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

void main() {
  for (final axis in Axis.values) {
    for (final reverse in [false, true]) {
      for (final followingSibling in ["none", "inner", "outer"]) {
        testWidgets(
          "grouped initial end: $axis reverse=$reverse following=$followingSibling",
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(600, 600));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final scroll = ScrollController();
            addTearDown(scroll.dispose);
            EdgeInsets padding(double before, double after) =>
                axis == Axis.vertical
                ? EdgeInsets.only(
                    top: reverse ? after : before,
                    bottom: reverse ? before : after,
                  )
                : EdgeInsets.only(
                    left: reverse ? after : before,
                    right: reverse ? before : after,
                  );
            Widget sibling(double extent) => SliverToBoxAdapter(
              child: SizedBox(height: extent, width: extent),
            );

            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: CustomScrollView(
                  controller: scroll,
                  scrollDirection: axis,
                  reverse: reverse,
                  slivers: [
                    SliverPadding(
                      padding: padding(17, 73),
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          sibling(120),
                          SliverPadding(
                            padding: padding(11, 37),
                            sliver: SliverMainAxisGroup(
                              slivers: [
                                sibling(160),
                                SliverOpacity(
                                  opacity: 1,
                                  sliver: SliverPadding(
                                    padding: padding(7, 19),
                                    sliver: SuperSliverList.builder(
                                      initialScrollPosition:
                                          InitialScrollPosition.end,
                                      extentEstimation: (_, _) => 52,
                                      itemCount: 20,
                                      itemBuilder: (_, _) =>
                                          const SizedBox(height: 52, width: 52),
                                    ),
                                  ),
                                ),
                                if (followingSibling == "inner") sibling(210),
                              ],
                            ),
                          ),
                          if (followingSibling == "outer") sibling(310),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
            // All leading padding and preceding siblings contribute. Trailing
            // padding contributes only until a following sibling separates the
            // list's end from the enclosing group's end. When the list is last
            // in both groups, all three trailing paddings still belong to it.
            const preceding = 17 + 120 + 11 + 160 + 7;
            final trailing = switch (followingSibling) {
              "inner" => 19,
              "outer" => 19 + 37,
              _ => 19 + 37 + 73,
            };
            final expected = preceding + 20 * 52 + trailing - 600;
            final total =
                preceding +
                20 * 52 +
                19 +
                37 +
                73 +
                (followingSibling == "inner" ? 210 : 0) +
                (followingSibling == "outer" ? 310 : 0);
            expect(tester.takeException(), isNull);
            expect(scroll.offset, closeTo(expected, 0.001));
            expect(
              scroll.position.maxScrollExtent,
              closeTo(total - 600, 0.001),
            );
            expect(scroll.position.outOfRange, isFalse);
            expect(await tester.pumpAndSettle(), 1);
            expect(scroll.offset, closeTo(expected, 0.001));
          },
        );
      }
    }
  }

  for (final anchor in [0.0, 0.5]) {
    testWidgets(
      "padded initial end before the viewport center, anchor=$anchor",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        const center = ValueKey("center");
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: CustomScrollView(
              controller: scroll,
              center: center,
              anchor: anchor,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(top: 13.7, bottom: 47.9),
                  sliver: SuperSliverList.builder(
                    initialScrollPosition: InitialScrollPosition.end,
                    itemCount: 20,
                    extentEstimation: (_, _) => 52,
                    itemBuilder: (_, _) => const SizedBox(height: 52),
                  ),
                ),
                const SliverToBoxAdapter(
                  key: center,
                  child: SizedBox(height: 1200),
                ),
              ],
            ),
          ),
        );
        final sliver = tester.renderObject<RenderSliver>(
          find.byType(SuperSliverList, skipOffstage: false),
        );
        expect(sliver.constraints.growthDirection, GrowthDirection.reverse);
        expect(sliver.constraints.scrollOffset, 0);
        expect(scroll.offset, 0);
        expect(tester.takeException(), isNull);
        expect(await tester.pumpAndSettle(), 1);
        expect(scroll.position.outOfRange, isFalse);
      },
    );
  }

  for (final estimate in [20.0, 50.0, 51.95, 52.0, 55.0, 100.0]) {
    testWidgets("initial end with visible padding and estimate $estimate", (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1728, 1039));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SuperListView.builder(
            controller: controller,
            padding: const EdgeInsets.only(top: 47.9),
            physics: const SuperRangeMaintainingScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            initialScrollPosition: InitialScrollPosition.end,
            extentEstimation: (_, _) => estimate,
            itemCount: 20,
            itemBuilder: (_, index) =>
                SizedBox(key: ValueKey(index), height: 52),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(controller.position.hasContentDimensions, isTrue);
      expect(controller.offset, closeTo(48.9, 0.001));
      expect(controller.position.maxScrollExtent, closeTo(48.9, 0.001));
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey(19))).dy,
        closeTo(1039, 0.001),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(48.9, 0.001));
    });
  }

  for (final axis in Axis.values) {
    for (final reverse in [false, true]) {
      for (final extent in [20.0, 50.0, 52.0]) {
        testWidgets(
          "nested padding: $axis reverse=$reverse itemExtent=$extent",
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(1039, 1039));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final controller = ScrollController();
            addTearDown(controller.dispose);
            // Both estimates and measurements can overflow only because of
            // padding. Directional padding must also work for reversed axes.
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.rtl,
                child: CustomScrollView(
                  controller: controller,
                  scrollDirection: axis,
                  reverse: reverse,
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 20,
                        end: 10,
                        top: 20,
                        bottom: 10,
                      ),
                      sliver: SliverOpacity(
                        opacity: 1,
                        sliver: SliverPadding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 47.9,
                            end: 13.7,
                            top: 47.9,
                            bottom: 13.7,
                          ),
                          sliver: SuperSliverList.builder(
                            initialScrollPosition: InitialScrollPosition.end,
                            extentEstimation: (_, _) => 52,
                            itemCount: 20,
                            itemBuilder: (_, _) =>
                                SizedBox(height: extent, width: extent),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            final expected = math.max(0, 20 * extent + 91.6 - 1039);
            expect(controller.offset, closeTo(expected, 0.001));
            expect(
              controller.position.maxScrollExtent,
              closeTo(expected, 0.001),
            );
            await tester.pumpAndSettle();
            expect(controller.offset, closeTo(expected, 0.001));
          },
        );
      }
    }
  }

  for (final anchor in [0.0, 0.25]) {
    testWidgets("initial end after a preceding sliver, anchor=$anchor", (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(
            controller: controller,
            anchor: anchor,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 2100)),
              SliverPadding(
                padding: const EdgeInsets.only(top: 47.9, bottom: 13.7),
                sliver: SuperSliverList.builder(
                  initialScrollPosition: InitialScrollPosition.end,
                  extentEstimation: (_, _) => 52,
                  itemCount: 20,
                  itemBuilder: (_, _) => const SizedBox(height: 52),
                ),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(controller.offset, closeTo(3201.6 - 600 * (1 - anchor), 0.001));
      expect(controller.offset, controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
    });
  }

  testWidgets("padded initial end sticks and permits an immediate append", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1728, 1039));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    var count = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return StickToTarget(
              scrollController: scroll,
              listController: list,
              target: const StickTarget.bottom(),
              child: SuperListView.builder(
                controller: scroll,
                listController: list,
                padding: const EdgeInsets.only(top: 47.9),
                initialScrollPosition: InitialScrollPosition.end,
                extentEstimation: (_, _) => 52,
                itemCount: count,
                itemBuilder: (_, _) => const SizedBox(height: 52),
              ),
            );
          },
        ),
      ),
    );
    for (final newCount in [20, 21]) {
      rebuild(() => count = newCount);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(scroll.position.hasContentDimensions, isTrue);
      expect(scroll.offset, closeTo(newCount * 52 + 47.9 - 1039, 0.001));
      expect(list.stickTarget, const StickTarget.bottom());
    }
    await tester.pumpAndSettle();
  });

  testWidgets(
    "initial end does not overscroll when estimated content is actually short",
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _buildList(controller: controller, itemExtent: 20),
      );

      expect(controller.position.pixels, 0);
      expect(controller.position.maxScrollExtent, 0);
      expect(await tester.pumpAndSettle(), 1);
    },
  );

  testWidgets(
    "initial end still reaches the end when measured content remains long",
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _buildList(controller: controller, itemExtent: 150),
      );

      expect(controller.position.pixels, 600);
      expect(controller.position.maxScrollExtent, 600);
      expect(await tester.pumpAndSettle(), 1);
    },
  );
}

Widget _buildList({
  required ScrollController controller,
  required double itemExtent,
}) {
  return MaterialApp(
    home: SuperListView.builder(
      controller: controller,
      physics: const BouncingScrollPhysics(),
      initialScrollPosition: InitialScrollPosition.end,
      itemCount: 8,
      itemBuilder: (context, index) => SizedBox(height: itemExtent),
    ),
  );
}

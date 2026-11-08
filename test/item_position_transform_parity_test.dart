import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

void main() {
  for (final axis in Axis.values) {
    for (final reverse in [false, true]) {
      for (final direction in TextDirection.values) {
        testWidgets("cached position transform matches Flutter: "
            "$axis reverse=$reverse $direction", (tester) async {
          final saved =
              SuperSliverListPerfFlags.shareItemPositionViewportTransform;
          addTearDown(
            () => SuperSliverListPerfFlags.shareItemPositionViewportTransform =
                saved,
          );
          final list = ListController();
          final scroll = ScrollController();
          addTearDown(list.dispose);
          addTearDown(scroll.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: direction,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 400,
                    height: 600,
                    child: CustomScrollView(
                      scrollDirection: axis,
                      reverse: reverse,
                      controller: scroll,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(11),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  width: axis == Axis.horizontal ? 25 : 400,
                                  height: axis == Axis.vertical ? 25 : 400,
                                ),
                              ),
                              const SliverPersistentHeader(
                                pinned: true,
                                delegate: _PositionTestPinnedHeader(),
                              ),
                              SliverOpacity(
                                opacity: 0.7,
                                sliver: SuperSliverList.builder(
                                  listController: list,
                                  itemCount: 300,
                                  extentEstimation: (_, _) => 40,
                                  addAutomaticKeepAlives: false,
                                  addRepaintBoundaries: false,
                                  addSemanticIndexes: false,
                                  itemBuilder: (_, index) => KeepAlive(
                                    keepAlive: index.isEven,
                                    child: SizedBox(
                                      key: ValueKey(index),
                                      width: axis == Axis.horizontal
                                          ? 30.0 + index % 4 * 5
                                          : null,
                                      height: axis == Axis.vertical
                                          ? 30.0 + index % 4 * 5
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          scroll.jumpTo(1100);
          await tester.pumpAndSettle();
          SuperSliverListPerfFlags.shareItemPositionViewportTransform = false;
          final baseline = list.computeItemPositions()!;
          SuperSliverListPerfFlags.shareItemPositionViewportTransform = true;
          final optimized = list.computeItemPositions()!;

          expect(baseline, isNotEmpty);
          expect(optimized.length, baseline.length);
          for (var i = 0; i < baseline.length; i++) {
            expect(optimized[i].index, baseline[i].index);
            expect(
              optimized[i].itemLeadingEdge,
              closeTo(baseline[i].itemLeadingEdge, 1e-10),
            );
            expect(
              optimized[i].itemTrailingEdge,
              closeTo(baseline[i].itemTrailingEdge, 1e-10),
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}

// Exercise a pinned header's paint offset inside SliverMainAxisGroup.
class _PositionTestPinnedHeader extends SliverPersistentHeaderDelegate {
  const _PositionTestPinnedHeader();

  @override
  double get minExtent => 25;

  @override
  double get maxExtent => 45;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => const SizedBox.expand();

  @override
  bool shouldRebuild(covariant _PositionTestPinnedHeader oldDelegate) => false;
}

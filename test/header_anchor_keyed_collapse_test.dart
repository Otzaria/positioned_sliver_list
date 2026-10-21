import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart"
    show SuperSliverListPerfFlags;

void main() {
  for (final compat in [false, true]) {
    for (final batched in [false, true]) {
      for (final largeGap in [false, true]) {
        testWidgets(
          "keyed collapse and expansion preserve the first painted header "
          "compat=$compat batched=$batched largeGap=$largeGap",
          (tester) async {
            final previous = SuperSliverListPerfFlags.batchLeadingChildShift;
            SuperSliverListPerfFlags.batchLeadingChildShift = batched;
            addTearDown(() {
              SuperSliverListPerfFlags.batchLeadingChildShift = previous;
            });
            final scroll = ScrollController();
            final list = ListController();
            final header = GlobalKey();
            addTearDown(scroll.dispose);
            addTearDown(list.dispose);
            var expanded = !largeGap;
            var builds = 0;
            late StateSetter rebuild;
            await tester.pumpWidget(
              MaterialApp(
                home: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 400,
                    height: 400,
                    child: StatefulBuilder(
                      builder: (_, setState) {
                        rebuild = setState;
                        final ids = [
                          for (var group = 0; group < 100; group++) ...[
                            "h$group",
                            if (expanded && (!largeGap || group == 19))
                              for (
                                var item = 0;
                                item < (largeGap ? 2000 : 5);
                                item++
                              )
                                "b$group-$item",
                          ],
                        ];
                        final indices = {
                          for (var i = 0; i < ids.length; i++)
                            ValueKey(ids[i]): i,
                        };
                        Widget buildItem(BuildContext context, int index) {
                          ++builds;
                          final id = ids[index];
                          return id.startsWith("h")
                              ? _SurvivorHeader(
                                  key: ValueKey(id),
                                  child: id == "h20"
                                      ? SizedBox(key: header)
                                      : null,
                                )
                              : SizedBox(
                                  key: ValueKey(id),
                                  height: largeGap ? 100 : 40,
                                );
                        }

                        if (compat) {
                          return ScrollablePositionedList.builder(
                            scrollController: scroll,
                            listController: list,
                            cacheExtentScreens: 1,
                            itemCount: ids.length,
                            findChildIndexCallback: (key) => indices[key],
                            itemBuilder: buildItem,
                          );
                        }
                        return CustomScrollView(
                          controller: scroll,
                          scrollCacheExtent: const ScrollCacheExtent.viewport(
                            1,
                          ),
                          slivers: [
                            SuperSliverList.builder(
                              listController: list,
                              itemCount: ids.length,
                              findChildIndexCallback: (key) => indices[key],
                              itemBuilder: buildItem,
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
            list.jumpToItem(
              index: largeGap ? 20 : 120,
              scrollController: scroll,
              alignment: 0.2,
            );
            await tester.pumpAndSettle();
            final before = tester.getTopLeft(find.byKey(header)).dy;
            expect(before, closeTo(70, 0.01));
            final survivor = tester.state(find.byKey(const ValueKey("h21")));
            for (final next in [largeGap, !largeGap]) {
              final handle = list.preserveHeader(
                header.currentContext!.findRenderObject()! as RenderBox,
              )!;
              rebuild(() => expanded = next);
              await tester.pump();
              expect(tester.takeException(), isNull);
              expect(
                builds,
                lessThan(300),
                reason:
                    "distant inserted content must not be built before correction",
              );
              expect(
                tester.getTopLeft(find.byKey(header)).dy,
                closeTo(before, 0.01),
                reason: "the first frame must already use the new keyed index",
              );
              expect(
                tester.state(find.byKey(const ValueKey("h21"))),
                same(survivor),
                reason: "a surviving nearby header must keep its State",
              );
              handle.cancel();
              await tester.pumpAndSettle();
              expect(
                tester.getTopLeft(find.byKey(header)).dy,
                closeTo(before, 0.01),
              );
            }
            expect(builds, lessThan(300));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}

class _SurvivorHeader extends StatefulWidget {
  const _SurvivorHeader({super.key, this.child});

  final Widget? child;

  @override
  State<_SurvivorHeader> createState() => _SurvivorHeaderState();
}

class _SurvivorHeaderState extends State<_SurvivorHeader> {
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 50, child: widget.child);
}

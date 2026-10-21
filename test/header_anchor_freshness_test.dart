import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

void main() {
  for (final moveIndex in [false, true]) {
    testWidgets("fixed-size header descendants stay current move=$moveIndex", (
      tester,
    ) async {
      final scroll = ScrollController();
      final list = ListController();
      final prefix = ValueNotifier(1700.0);
      final header = GlobalKey();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      addTearDown(prefix.dispose);
      var inserted = false;
      late StateSetter rebuild;
      final target = SizedBox(
        key: const ValueKey("15"),
        height: 2400,
        child: RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: prefix,
            builder: (_, height, child) => Column(
              children: [
                SizedBox(height: height),
                child!,
              ],
            ),
            child: SizedBox(key: header, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              final ids = [
                if (inserted) "inserted",
                for (var i = 0; i < 100; ++i) "$i",
              ];
              return CustomScrollView(
                controller: scroll,
                slivers: [
                  SuperSliverList.builder(
                    listController: list,
                    itemCount: ids.length,
                    findChildIndexCallback: (key) {
                      final index = ids.indexOf(
                        (key as ValueKey<String>).value,
                      );
                      return index < 0 ? null : index;
                    },
                    itemBuilder: (_, index) => ids[index] == "15"
                        ? target
                        : SizedBox(key: ValueKey(ids[index]), height: 100),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      list.jumpToItem(index: 15, scrollController: scroll, alignment: 0);
      await tester.pumpAndSettle();
      scroll.jumpTo(
        scroll.offset + tester.getTopLeft(find.byKey(header)).dy - 150,
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.byKey(header)).dy;
      expect(before, closeTo(150, 0.01));
      final handle = list.preserveHeader(
        header.currentContext!.findRenderObject()! as RenderBox,
      )!;
      prefix.value = 1500;
      if (moveIndex) rebuild(() => inserted = true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.byKey(header)).dy, closeTo(before, 0.01));
      handle.cancel();
      await tester.pumpWidget(const SizedBox());
    });
  }
}

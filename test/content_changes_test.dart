import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

Finder _text(String t) => find.text(t, skipOffstage: false);

void main() {
  testWidgets("AnimatedSize above the reading position: no per-frame drift", (
    tester,
  ) async {
    final c = ItemScrollController();
    var expanded = false;
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 600,
            child: StatefulBuilder(
              builder: (context, s) {
                set = s;
                return ScrollablePositionedList.builder(
                  itemCount: 1000,
                  itemScrollController: c,
                  itemBuilder: (_, i) => i == 498
                      ? AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          child: SizedBox(
                            height: expanded ? 500 : 40,
                            child: Text("Item $i"),
                          ),
                        )
                      : SizedBox(height: 40, child: Text("Item $i")),
                );
              },
            ),
          ),
        ),
      ),
    );
    c.jumpTo(index: 500, offset: -10);
    await tester.pump();
    expect(tester.getTopLeft(_text("Item 500")).dy, closeTo(-10, 0.01));
    set(() => expanded = true);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getTopLeft(_text("Item 500")).dy,
        closeTo(-10, 0.01),
        reason: "frame $i",
      );
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_text("Item 500")).dy, closeTo(-10, 0.01));
  });

  testWidgets("prepend items and restore the anchor in the same frame", (
    tester,
  ) async {
    final c = ItemScrollController();
    var offset = 0;
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, s) {
            set = s;
            return ScrollablePositionedList.builder(
              itemCount: 1000 + offset,
              itemScrollController: c,
              itemBuilder: (_, i) => SizedBox(
                height: 30.0 + (i - offset) % 5 * 10,
                child: Text("P ${i - offset}"),
              ),
            );
          },
        ),
      ),
    );
    c.jumpTo(index: 300, offset: -7);
    await tester.pump();
    final a = c.anchor!;
    set(() => offset = 200);
    c.jumpTo(index: a.index + 200, offset: -a.offsetInItem);
    await tester.pump();
    expect(tester.getTopLeft(_text("P 300")).dy, closeTo(-7, 0.01));
  });
}

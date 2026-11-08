import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

class _StatefulRow extends StatefulWidget {
  const _StatefulRow({required this.id, super.key});

  final int id;

  @override
  State<_StatefulRow> createState() => _StatefulRowState();
}

class _StatefulRowState extends State<_StatefulRow> {
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 40, child: Text("Row ${widget.id}"));
}

void main() {
  for (final logical in [false, true]) {
    testWidgets("sliver reorder logical=$logical", (tester) async {
      final ids = List<int>.generate(12, (index) => index);
      late StateSetter rebuild;

      Widget build() => MaterialApp(
        home: SizedBox(
          width: 400,
          height: 700,
          child: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              int? indexForKey(Key key) {
                final id = (key as ValueKey<int>).value;
                final index = ids.indexOf(id);
                return index == -1 ? null : index;
              }

              return CustomScrollView(
                slivers: [
                  SuperSliverList.separated(
                    itemCount: ids.length,
                    findItemIndexCallback: logical ? indexForKey : null,
                    findChildIndexCallback: logical
                        ? null
                        : (key) {
                            final index = indexForKey(key);
                            return index == null ? null : index * 2;
                          },
                    itemBuilder: (_, index) =>
                        _StatefulRow(key: ValueKey(ids[index]), id: ids[index]),
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                  ),
                ],
              );
            },
          ),
        ),
      );

      await tester.pumpWidget(build());
      final finder = find.byKey(const ValueKey(3));
      final originalState = tester.state<_StatefulRowState>(finder);
      rebuild(() {
        ids.remove(3);
        ids.insert(8, 3);
      });
      await tester.pumpAndSettle();

      expect(tester.state<_StatefulRowState>(finder), same(originalState));
      expect(find.text("Row 3"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test("sliver separated rejects conflicting callback conventions", () {
    expect(
      () => SuperSliverList.separated(
        itemCount: 2,
        itemBuilder: (_, _) => const SizedBox.shrink(),
        separatorBuilder: (_, _) => const SizedBox.shrink(),
        findItemIndexCallback: (_) => 0,
        findChildIndexCallback: (_) => 0,
      ),
      throwsAssertionError,
    );
  });
}

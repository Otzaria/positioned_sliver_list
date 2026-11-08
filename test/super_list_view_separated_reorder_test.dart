import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

class _TrackedRow extends StatefulWidget {
  const _TrackedRow({required this.id, super.key});

  final int id;

  @override
  State<_TrackedRow> createState() => _TrackedRowState();
}

class _TrackedRowState extends State<_TrackedRow> {
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 42, child: Text("Item ${widget.id}"));
}

void main() {
  for (final logicalCallback in [false, true]) {
    testWidgets("separated keyed reordering retains state "
        "with ${logicalCallback ? 'item' : 'child'} index callback", (
      tester,
    ) async {
      final ids = List<int>.generate(12, (index) => index);
      late StateSetter update;
      Widget build() => MaterialApp(
        home: SizedBox(
          width: 400,
          height: 700,
          child: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              int? indexForKey(Key key) {
                final id = (key as ValueKey<int>).value;
                final index = ids.indexOf(id);
                return index < 0 ? null : index;
              }

              return SuperListView.separated(
                itemCount: ids.length,
                findItemIndexCallback: logicalCallback ? indexForKey : null,
                findChildIndexCallback: logicalCallback
                    ? null
                    : (key) {
                        final index = indexForKey(key);
                        return index == null ? null : index * 2;
                      },
                itemBuilder: (_, index) =>
                    _TrackedRow(key: ValueKey(ids[index]), id: ids[index]),
                separatorBuilder: (_, _) => const SizedBox(height: 2),
              );
            },
          ),
        ),
      );

      await tester.pumpWidget(build());
      final target = find.byKey(const ValueKey(3));
      final originalState = tester.state<_TrackedRowState>(target);
      update(() {
        ids.remove(3);
        ids.insert(8, 3);
      });
      await tester.pumpAndSettle();

      expect(tester.state<_TrackedRowState>(target), same(originalState));
      expect(find.text("Item 3"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test("separated maps item and separator keys with the right convention", () {
    final legacy = SuperListView.separated(
      itemCount: 3,
      itemBuilder: (_, _) => const SizedBox.shrink(),
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      findChildIndexCallback: (key) {
        if (key == const ValueKey("separator")) {
          return 3;
        }
        return key == const ValueKey("item") ? 4 : null;
      },
    );
    expect(
      legacy.childrenDelegate.findIndexByKey(const ValueKey("separator")),
      3,
    );
    expect(legacy.childrenDelegate.findIndexByKey(const ValueKey("item")), 4);

    final logical = SuperListView.separated(
      itemCount: 3,
      itemBuilder: (_, _) => const SizedBox.shrink(),
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      findItemIndexCallback: (key) {
        return key == const ValueKey("item") ? 2 : null;
      },
    );
    expect(
      logical.childrenDelegate.findIndexByKey(const ValueKey("separator")),
      isNull,
    );
    expect(logical.childrenDelegate.findIndexByKey(const ValueKey("item")), 4);
  });

  test("separated cannot accept both index callback conventions", () {
    expect(
      () => SuperListView.separated(
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

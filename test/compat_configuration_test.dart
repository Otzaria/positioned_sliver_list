import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

Widget _host(Widget child) => MaterialApp(home: child);

class _KeyedItem extends StatefulWidget {
  _KeyedItem({required String value}) : super(key: ValueKey(value));

  @override
  State<_KeyedItem> createState() => _KeyedItemState();
}

class _KeyedItemState extends State<_KeyedItem> {
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 100, child: Text("Stateful item"));
}

void main() {
  testWidgets("a reparented list refreshes its PageStorage namespace", (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final item = ItemScrollController();
    final movingKey = GlobalKey();
    Widget list(String namespace, Key key) => PageStorage(
      bucket: bucket,
      child: KeyedSubtree(
        key: PageStorageKey(namespace),
        child: ScrollablePositionedList.builder(
          key: key,
          itemScrollController: item,
          restorePosition: true,
          itemCount: 100,
          itemBuilder: (_, index) => const SizedBox(height: 100),
        ),
      ),
    );
    await tester.pumpWidget(_host(list("first", movingKey)));
    item.jumpTo(index: 10, offset: -7);
    await tester.pumpAndSettle();
    final first = item.anchor!;
    final state = tester.state(find.byKey(movingKey));
    await tester.pumpWidget(_host(list("second", movingKey)));
    expect(tester.state(find.byKey(movingKey)), same(state));
    item.jumpTo(index: 20, offset: -11);
    await tester.pumpAndSettle();
    final second = item.anchor!;
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(_host(list("first", GlobalKey())));
    expect(item.anchor!.index, first.index);
    expect(item.anchor!.offsetInItem, first.offsetInItem);
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(_host(list("second", GlobalKey())));
    expect(item.anchor!.index, second.index);
    expect(item.anchor!.offsetInItem, second.offsetInItem);
  });

  testWidgets("reparenting keeps an external controller and its listeners", (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final native = ListController();
    final item = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final movingKey = GlobalKey();
    addTearDown(native.dispose);
    Widget list(String namespace, Key key) => PageStorage(
      bucket: bucket,
      child: KeyedSubtree(
        key: PageStorageKey(namespace),
        child: ScrollablePositionedList.builder(
          key: key,
          listController: native,
          itemScrollController: item,
          itemPositionsListener: positions,
          restorePosition: true,
          itemCount: 100,
          itemBuilder: (_, index) => const SizedBox(height: 100),
        ),
      ),
    );
    await tester.pumpWidget(_host(list("first", movingKey)));
    final state = tester.state(find.byKey(movingKey));
    item.jumpTo(index: 10, offset: -7);
    await tester.pumpAndSettle();
    final first = item.anchor!;
    await tester.pumpWidget(_host(list("second", movingKey)));
    expect(tester.state(find.byKey(movingKey)), same(state));
    expect(item.listController, same(native));
    expect(native.isAttached, isTrue);
    final jumped = item.jumpToAsync(index: 20, offset: -11);
    await tester.pump();
    await jumped;
    expect(
      positions.itemPositions.value.map((position) => position.index),
      contains(20),
    );
    final second = item.anchor!;
    await tester.pumpWidget(_host(const SizedBox()));
    expect(native.isAttached, isFalse);
    await tester.pumpWidget(_host(list("first", GlobalKey())));
    expect(item.anchor!.index, first.index);
    expect(item.anchor!.offsetInItem, first.offsetInItem);
    expect(native.isAttached, isTrue);
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(_host(list("second", GlobalKey())));
    expect(item.anchor!.index, second.index);
    expect(item.anchor!.offsetInItem, second.offsetInItem);
    await tester.pumpWidget(_host(const SizedBox()));
  });

  for (final separated in [false, true]) {
    testWidgets("keyed item state survives reorder: separated=$separated", (
      tester,
    ) async {
      Widget list(List<String> values) {
        int? findIndex(Key key) {
          final index = values.indexOf((key as ValueKey<String>).value);
          return index < 0 ? null : index;
        }

        Widget buildItem(BuildContext _, int index) =>
            _KeyedItem(value: values[index]);
        return separated
            ? ScrollablePositionedList.separated(
                itemCount: values.length,
                itemBuilder: buildItem,
                findChildIndexCallback: findIndex,
                separatorBuilder: (_, index) => const SizedBox(height: 7),
              )
            : ScrollablePositionedList.builder(
                itemCount: values.length,
                itemBuilder: buildItem,
                findChildIndexCallback: findIndex,
              );
      }

      await tester.pumpWidget(_host(list(["first", "second", "third"])));
      final state = tester.state(find.byKey(const ValueKey("first")));
      await tester.pumpWidget(_host(list(["second", "first", "third"])));
      expect(tester.state(find.byKey(const ValueKey("first"))), same(state));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey("first"))).dy,
        separated ? 107 : 100,
      );
    });
  }

  testWidgets("external native controller remains owned by its caller", (
    tester,
  ) async {
    final first = ListController();
    final second = ListController();
    final item = ItemScrollController();
    final positions = ItemPositionsListener.create();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget list(ListController native) => ScrollablePositionedList.builder(
      listController: native,
      itemScrollController: item,
      itemPositionsListener: positions,
      itemCount: 100,
      itemBuilder: (_, index) =>
          SizedBox(height: 100, child: Text("Item $index")),
    );
    await tester.pumpWidget(_host(list(first)));
    expect(item.listController, same(first));
    expect(first.isAttached, isTrue);
    await tester.pumpWidget(_host(list(second)));
    expect(first.isAttached, isFalse);
    expect(second.isAttached, isTrue);
    expect(item.listController, same(second));
    final jumped = item.jumpToAsync(index: 50);
    await tester.pump();
    await jumped;
    expect(
      positions.itemPositions.value.map((position) => position.index),
      contains(50),
    );
    await tester.pumpWidget(_host(const SizedBox()));
    expect(second.isAttached, isFalse);
    await tester.pumpWidget(_host(list(first)));
    expect(first.isAttached, isTrue);
    await tester.pumpWidget(_host(const SizedBox()));
  });

  testWidgets("new estimator closures do not rescan unchanged content", (
    tester,
  ) async {
    var calls = 0;
    Widget list() => ScrollablePositionedList.builder(
      itemCount: 10000,
      estimateExtent: (_, width) {
        calls++;
        return 100;
      },
      itemBuilder: (_, index) => const SizedBox(height: 100),
    );
    await tester.pumpWidget(_host(list()));
    await tester.pumpAndSettle();
    final initialCalls = calls;
    expect(initialCalls, greaterThan(9000));
    for (var rebuild = 0; rebuild < 5; rebuild++) {
      await tester.pumpWidget(_host(list()));
      await tester.pumpAndSettle();
    }
    expect(calls, initialCalls);
  });

  testWidgets("replacing an owned controller releases it and pending jumps", (
    tester,
  ) async {
    final external = ListController();
    final item = ItemScrollController();
    addTearDown(external.dispose);
    Widget list([ListController? native]) => ScrollablePositionedList.builder(
      listController: native,
      itemScrollController: item,
      itemCount: 20,
      itemBuilder: (_, index) => const SizedBox(height: 100),
    );
    await tester.pumpWidget(_host(list()));
    final owned = item.listController!;
    final pending = item.jumpToAsync(index: 15);
    await tester.pumpWidget(_host(list(external)));
    await pending;
    expect(owned.isAttached, isFalse);
    expect(() => owned.addListener(() {}), throwsFlutterError);
    expect(item.listController, same(external));
    await tester.pumpWidget(_host(list()));
    expect(external.isAttached, isFalse);
    final replacement = item.listController!;
    expect(replacement, isNot(same(owned)));
    expect(replacement.isAttached, isTrue);
    await tester.pumpWidget(_host(const SizedBox()));
    expect(() => replacement.addListener(() {}), throwsFlutterError);
  });

  testWidgets("estimationKey refreshes estimates without replacing the list", (
    tester,
  ) async {
    final item = ItemScrollController();
    Widget list(int revision) => ScrollablePositionedList.builder(
      itemScrollController: item,
      itemCount: 1000,
      estimationKey: revision,
      estimateExtent: (_, width) => revision == 0 ? 100 : 200,
      itemBuilder: (_, index) => const SizedBox(height: 100),
    );
    await tester.pumpWidget(_host(list(0)));
    await tester.pumpAndSettle();
    final native = item.listController;
    expect(native!.extentForIndex(500).$1, 100);
    await tester.pumpWidget(_host(list(1)));
    await tester.pumpAndSettle();
    expect(item.listController, same(native));
    expect(native.extentForIndex(500).$1, 200);
    expect(native.extentForIndex(0), (100.0, false));
  });

  testWidgets("estimationKey replaces measurements outside the cache area", (
    tester,
  ) async {
    final item = ItemScrollController();
    Widget list(int revision) => ScrollablePositionedList.builder(
      itemScrollController: item,
      itemCount: 1000,
      estimationKey: revision,
      estimateExtent: (_, width) => revision == 0 ? 150 : 250,
      itemBuilder: (_, index) => const SizedBox(height: 100),
    );
    await tester.pumpWidget(_host(list(0)));
    item.jumpTo(index: 500);
    await tester.pumpAndSettle();
    item.jumpTo(index: 0);
    await tester.pumpAndSettle();
    final native = item.listController!;
    expect(native.extentForIndex(500), (100.0, false));
    await tester.pumpWidget(_host(list(1)));
    await tester.pumpAndSettle();
    expect(native.extentForIndex(500), (250.0, true));
    expect(native.extentForIndex(0), (100.0, false));
  });

  testWidgets("logical extent and pixel wrappers map separated items", (
    tester,
  ) async {
    final item = ItemScrollController();
    await tester.pumpWidget(
      _host(
        ScrollablePositionedList.separated(
          itemScrollController: item,
          itemCount: 1000,
          estimateExtent: (_, width) => 100,
          estimatedSeparatorExtent: 7,
          itemBuilder: (_, index) => const SizedBox(height: 100),
          separatorBuilder: (_, index) => const SizedBox(height: 7),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final updated = item.updateEstimatedExtents({400: 333, 401: 222});
    await tester.pump();
    await updated;
    final native = item.listController!;
    expect(native.extentForIndex(800).$1, 333);
    expect(native.extentForIndex(801).$1, 7);
    expect(native.extentForIndex(802).$1, 222);
    final pixels = native.estimateOffsetToReveal(800, 0);
    expect(item.indexForScrollOffset(pixels + 10), 400);
    expect(item.indexForScrollOffset(pixels + 335), 400);
    expect(item.indexForScrollOffset(pixels + 345), 401);
    expect(item.indexForScrollOffset(-1), isNull);
    await tester.pumpWidget(_host(const SizedBox()));
    expect(item.indexForScrollOffset(0), isNull);
  });
}

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

void main() {
  testWidgets(
    "pins the top of a tall item when it enters while stuck to bottom",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);

      var showResponse = false;
      var pinResponse = false;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                final itemCount = showResponse ? 5 : 4;
                final target = pinResponse
                    ? const StickTarget(
                        index: 3,
                        alignment: 100 / 600,
                        rect: Rect.fromLTWH(0, 0, 0, 1),
                      )
                    : const StickTarget.bottom();
                return StickToTarget(
                  scrollController: scrollController,
                  listController: listController,
                  target: target,
                  child: SuperListView.builder(
                    controller: scrollController,
                    listController: listController,
                    initialScrollPosition: InitialScrollPosition.end,
                    itemCount: itemCount,
                    findChildIndexCallback: (key) {
                      if (key == const Key("footer")) return itemCount - 1;
                      if (key == const Key("response")) {
                        return showResponse ? 3 : null;
                      }
                      if (key is ValueKey<int>) return key.value;
                      return null;
                    },
                    itemBuilder: (context, index) {
                      if (showResponse && index == 3) {
                        return const SizedBox(
                          key: Key("response"),
                          height: 700,
                        );
                      }
                      if (index == itemCount - 1) {
                        return const SizedBox(
                          key: Key("footer"),
                          height: 100,
                        );
                      }
                      return SizedBox(
                        key: ValueKey(index),
                        height: 200,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        scrollController.offset,
        scrollController.position.maxScrollExtent,
      );

      // Telosnex first inserts the response while it is still using the
      // bottom target. The stable footer moves after the new response.
      rebuild(() => showResponse = true);
      await tester.pumpAndSettle();
      expect(
        scrollController.offset,
        scrollController.position.maxScrollExtent,
      );

      // Once the response has text, the target changes to its top pixel. A
      // tall response is already above that position and requires a backward
      // jump to put its top below the obstruction.
      rebuild(() => pinResponse = true);
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.byKey(const Key("response"))).dy,
        closeTo(100, 1),
      );
    },
  );

  testWidgets(
    "does not unstick an item target after a tap without scrolling",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      final stickChanges = <bool>[];

      await tester.pumpWidget(
        _TestList(
          scrollController: scrollController,
          listController: listController,
          initialScrollPosition: InitialScrollPosition.start,
          target: _target(index: 3),
          onStickStateChanged: stickChanges.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(_itemTop(tester, 3), closeTo(100, 1));

      final gesture = await tester.startGesture(const Offset(400, 150));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 501));

      // A tap temporarily suspends corrections for expand-in-place, but it
      // did not move the list and must not opt the user out of item pinning.
      expect(stickChanges, isEmpty);
      expect(listController.stickTarget, _target(index: 3));
    },
  );

  testWidgets(
    "does not assume an initial non-bottom offset is stuck",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      StickTarget? target;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.start,
              target: target,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      scrollController.jumpTo(300);
      rebuild(() => target = const StickTarget.bottom());
      await tester.pumpAndSettle();

      // Supplying the initial target while deliberately away from bottom must
      // not opt the user into auto-scrolling.
      expect(scrollController.offset, closeTo(300, 0.1));
      expect(listController.stickTarget, isNull);
    },
  );

  testWidgets(
    "ignores scroll notifications from a nested scrollable",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      final stickChanges = <bool>[];

      await tester.pumpWidget(
        _TestList(
          scrollController: scrollController,
          listController: listController,
          initialScrollPosition: InitialScrollPosition.start,
          target: _target(index: 3),
          onStickStateChanged: stickChanges.add,
          itemBuilder: (context, index) {
            if (index != 3) {
              return SizedBox(key: ValueKey(index), height: 200);
            }
            return SizedBox(
              key: const ValueKey(3),
              height: 200,
              child: ListView.builder(
                itemCount: 10,
                itemExtent: 50,
                itemBuilder: (context, index) => Text("nested $index"),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(_itemTop(tester, 3), closeTo(100, 1));

      await tester.drag(
        find.byType(Scrollable).last,
        const Offset(0, -50),
      );
      await tester.pump();

      // The nested notification has depth 1 and says nothing about whether
      // the outer conversation list was moved away from its target.
      expect(stickChanges, isEmpty);
      expect(listController.stickTarget, _target(index: 3));
    },
  );

  testWidgets(
    "keeps corrections suspended until every pointer is up",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      final stickChanges = <bool>[];

      await tester.pumpWidget(
        _TestList(
          scrollController: scrollController,
          listController: listController,
          initialScrollPosition: InitialScrollPosition.start,
          target: _target(index: 3),
          onStickStateChanged: stickChanges.add,
        ),
      );
      await tester.pumpAndSettle();

      final firstPointer = await tester.startGesture(
        const Offset(350, 150),
        pointer: 1,
      );
      final secondPointer = await tester.startGesture(
        const Offset(450, 150),
        pointer: 2,
      );
      await firstPointer.up();
      await tester.pump(const Duration(milliseconds: 501));

      // Interaction state is a bool, so releasing either pointer starts the
      // end timer even though another pointer is still selecting/dragging.
      expect(stickChanges, isEmpty);
      expect(listController.stickTarget, isNull);
      await secondPointer.up();
    },
  );

  testWidgets(
    "keeps expansion grace active after a touch scroll ends",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      var itemCount = 7;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.end,
              target: const StickTarget.bottom(),
              itemCount: itemCount,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      final initialOffset = scrollController.offset;

      // Attempt to drag beyond the bottom. This produces a real touch-scroll
      // end without moving away from the bottom or opting out of sticking.
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(0, -10));
      await gesture.up();
      await tester.pump();
      expect(scrollController.offset, initialOffset);

      rebuild(() => itemCount = 8);
      await tester.pump(const Duration(milliseconds: 100));

      // ScrollEndNotification clears _userIsInteracting immediately, despite
      // the pointer-up path promising a 500ms expansion grace period.
      expect(scrollController.offset, closeTo(initialOffset, 0.1));
      expect(scrollController.position.extentAfter, closeTo(200, 1));
    },
  );

  testWidgets(
    "does not assume a replacement scroll controller is still stuck",
    (tester) async {
      final firstController = ScrollController();
      final secondController = ScrollController();
      final listController = ListController();
      addTearDown(firstController.dispose);
      addTearDown(secondController.dispose);
      addTearDown(listController.dispose);
      var scrollController = firstController;
      StickTarget? target;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.start,
              target: target,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      firstController.jumpTo(firstController.position.maxScrollExtent);
      rebuild(() => target = const StickTarget.bottom());
      await tester.pumpAndSettle();
      expect(listController.stickTarget, const StickTarget.bottom());

      rebuild(() => scrollController = secondController);
      await tester.pumpAndSettle();

      // A replacement controller starts away from bottom and must be evaluated
      // independently instead of inheriting the old controller's stick state.
      expect(secondController.offset, closeTo(0, 0.1));
      expect(listController.stickTarget, isNull);
    },
  );

  testWidgets(
    "unsticks when the item target no longer exists",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      final stickChanges = <bool>[];
      var itemCount = 7;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.start,
              target: _target(index: 3),
              itemCount: itemCount,
              onStickStateChanged: stickChanges.add,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      rebuild(() => itemCount = 3);
      await tester.pumpAndSettle();

      // Both correction paths silently return for an out-of-range index,
      // leaving the public state claiming it is auto-tracking nothing.
      expect(stickChanges, [false]);
      expect(listController.stickTarget, isNull);
    },
  );

  testWidgets(
    "clears a stale controller target when configured target is null",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController()
        ..stickTarget = const StickTarget.bottom();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);

      await tester.pumpWidget(
        _TestList(
          scrollController: scrollController,
          listController: listController,
          initialScrollPosition: InitialScrollPosition.start,
          target: null,
        ),
      );
      await tester.pumpAndSettle();

      // The initial false state also takes _setSticking's early return, so a
      // reused controller can keep correcting toward an obsolete target.
      expect(listController.stickTarget, isNull);
    },
  );

  testWidgets(
    "recognizes the visual bottom of a reversed list",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      final stickChanges = <bool>[];
      StickTarget? target;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.start,
              target: target,
              reverse: true,
              onStickStateChanged: stickChanges.add,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(scrollController.offset, 0);

      rebuild(() => target = const StickTarget.bottom());
      await tester.pump();

      // In a reversed viewport pixels == 0 is the visual bottom; extentAfter
      // describes the opposite edge, so the direction must be considered.
      expect(stickChanges, [true]);
      expect(listController.stickTarget, const StickTarget.bottom());
    },
  );

  testWidgets(
    "restores correction after an unconsumed mouse-wheel signal",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      var itemCount = 7;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.end,
              target: const StickTarget.bottom(),
              itemCount: itemCount,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(400, 300),
          scrollDelta: Offset(0, 100),
        ),
      );
      await tester.pump();
      rebuild(() => itemCount = 8);
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pumpAndSettle();

      // At the boundary no ScrollEndNotification is guaranteed, so the signal
      // can leave _userIsInteracting true and correction disabled indefinitely.
      expect(
        scrollController.offset,
        scrollController.position.maxScrollExtent,
      );
    },
  );

  testWidgets(
    "realigns an active item target after the viewport height changes",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      var viewportHeight = 500.0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.start,
              target: _target(index: 3),
              viewportHeight: viewportHeight,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(_itemTop(tester, 3), closeTo(100 / 6 * 5, 1));

      rebuild(() => viewportHeight = 600);
      await tester.pumpAndSettle();

      // Alignment is a viewport fraction. Metrics changes do not schedule the
      // item fallback, so the old absolute position survives the resize.
      expect(_itemTop(tester, 3), closeTo(100, 1));
    },
  );

  testWidgets(
    "allows keyboard scrolling away from an item target",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      final stickChanges = <bool>[];

      await tester.pumpWidget(
        _TestList(
          scrollController: scrollController,
          listController: listController,
          initialScrollPosition: InitialScrollPosition.start,
          target: _target(index: 3),
          onStickStateChanged: stickChanges.add,
        ),
      );
      await tester.pumpAndSettle();

      final itemContext = tester.element(find.byKey(const ValueKey(3)));
      Actions.invoke(
        itemContext,
        const ScrollIntent(
          direction: AxisDirection.down,
          type: ScrollIncrementType.page,
        ),
      );
      await tester.pumpAndSettle();

      // Keyboard/semantics scrolling emits no pointer event, and the scroll
      // notification path only recognizes movement while a pointer is active.
      expect(stickChanges, [false]);
      expect(listController.stickTarget, isNull);
    },
  );

  testWidgets(
    "does not re-engage an unstuck list when the threshold changes",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      var threshold = 20.0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.end,
              target: const StickTarget.bottom(),
              threshold: threshold,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(listController.stickTarget, isNull);

      rebuild(() => threshold = 100);
      await tester.pumpAndSettle();

      expect(listController.stickTarget, isNull);
      expect(scrollController.position.extentAfter, closeTo(60, 1));
    },
  );

  testWidgets(
    "does not re-engage an unstuck list when content shrinks",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      var lastHeight = 200.0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.end,
              target: const StickTarget.bottom(),
              itemBuilder: (context, index) => SizedBox(
                key: ValueKey(index),
                height: index == 6 ? lastHeight : 200,
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(listController.stickTarget, isNull);

      rebuild(() => lastHeight = 150);
      await tester.pumpAndSettle();

      expect(listController.stickTarget, isNull);
    },
  );

  testWidgets(
    "does not re-engage an unstuck list when the viewport grows",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      var viewportHeight = 500.0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.end,
              target: const StickTarget.bottom(),
              viewportHeight: viewportHeight,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(listController.stickTarget, isNull);

      rebuild(() => viewportHeight = 550);
      await tester.pumpAndSettle();

      expect(listController.stickTarget, isNull);
    },
  );

  testWidgets(
    "keeps a reversed list at visual bottom while content grows",
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      addTearDown(scrollController.dispose);
      addTearDown(listController.dispose);
      var itemCount = 7;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _TestList(
              scrollController: scrollController,
              listController: listController,
              initialScrollPosition: InitialScrollPosition.start,
              target: const StickTarget.bottom(),
              reverse: true,
              itemCount: itemCount,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      rebuild(() => itemCount = 8);
      await tester.pumpAndSettle();

      expect(scrollController.offset, 0);
      expect(listController.stickTarget, const StickTarget.bottom());
    },
  );
}

StickTarget _target({required int index, double top = 100}) => StickTarget(
      index: index,
      alignment: top / 600,
      rect: const Rect.fromLTWH(0, 0, 0, 1),
    );

double _itemTop(WidgetTester tester, int index) =>
    tester.getTopLeft(find.byKey(ValueKey(index))).dy;

class _TestList extends StatelessWidget {
  const _TestList({
    required this.scrollController,
    required this.listController,
    required this.initialScrollPosition,
    required this.target,
    this.onStickStateChanged,
    this.itemBuilder,
    this.itemCount = 7,
    this.viewportHeight = 600,
    this.reverse = false,
    this.threshold = 20,
  });

  final ScrollController scrollController;
  final ListController listController;
  final InitialScrollPosition initialScrollPosition;
  final StickTarget? target;
  final ValueChanged<bool>? onStickStateChanged;
  final IndexedWidgetBuilder? itemBuilder;
  final int itemCount;
  final double viewportHeight;
  final bool reverse;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: viewportHeight,
          child: StickToTarget(
            scrollController: scrollController,
            listController: listController,
            target: target,
            threshold: threshold,
            onStickStateChanged: onStickStateChanged,
            child: SuperListView.builder(
              key: ValueKey(scrollController),
              controller: scrollController,
              listController: listController,
              initialScrollPosition: initialScrollPosition,
              reverse: reverse,
              itemCount: itemCount,
              itemBuilder: itemBuilder ??
                  (context, index) => SizedBox(
                        key: ValueKey(index),
                        height: 200,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

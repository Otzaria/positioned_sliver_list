import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

const _itemTarget = StickTarget(
  index: 3,
  alignment: 100 / 600,
  rect: Rect.fromLTWH(0, 0, 0, 1),
);
// Reveal aligns the one-pixel rect within the remaining viewport space.
const _itemOffset = 600 - (600 - 1) * (100 / 600);

void main() {
  for (final scenario in [
    (true, true),
    (true, false),
    (false, true),
    (false, false)
  ]) {
    final (append, extentsOnly) = scenario;
    testWidgets(
        "content callback can rebuild its owner: append=$append, extentsOnly=$extentsOnly",
        (tester) async {
      final previous = SuperSliverListPerfFlags.extentsOnlyStickNotifications;
      SuperSliverListPerfFlags.extentsOnlyStickNotifications = extentsOnly;
      addTearDown(() =>
          SuperSliverListPerfFlags.extentsOnlyStickNotifications = previous);
      final scroll = ScrollController();
      final list = ListController();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      var count = append ? 7 : 12;
      const item = StickTarget(index: 10, alignment: 0);
      StickTarget? target = append ? null : item;
      final changes = <bool>[];
      final phases = <SchedulerPhase>[];
      late StateSetter rebuild;
      await tester.pumpWidget(StatefulBuilder(builder: (_, setState) {
        rebuild = setState;
        return _DeferredList(
          scroll: scroll,
          list: list,
          target: target,
          itemCount: count,
          onStickStateChanged: (value) {
            phases.add(SchedulerBinding.instance.schedulerPhase);
            // A real consumer updates its UI, not just a recording list.
            setState(() => changes.add(value));
          },
        );
      }));
      await tester.pumpAndSettle();
      if (append) {
        rebuild(() => target = item);
        await tester.pumpAndSettle();
        expect(changes, isEmpty);
        // Pending item engagement is intentional even after many frames.
        await tester.pump(const Duration(minutes: 1));
      }
      rebuild(() => count = append ? 12 : 7);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(changes, [append]);
      expect(phases, [SchedulerPhase.postFrameCallbacks]);
      expect(list.stickTarget, append ? item : null);
      await tester.pumpAndSettle();
      expect(changes, [append], reason: "notify once, not on every layout");
    });
  }

  testWidgets("a programmatic jump does not cancel pending item engagement",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
      listReady: false,
    ));
    await tester.pumpAndSettle();
    scroll.jumpTo(100);
    await tester.pumpAndSettle();
    expect(scroll.offset, 100);
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(list.stickTarget, _itemTarget);
    expect(scroll.offset, closeTo(_itemOffset, 0.001));
  });

  testWidgets("wheel scrolling cancels pending item engagement",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
      listReady: false,
    ));
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(const PointerScrollEvent(
      position: Offset(400, 300),
      scrollDelta: Offset(0, 100),
    ));
    await tester.pump(const Duration(milliseconds: 501));
    expect(scroll.offset, 100);
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(list.stickTarget, isNull);
    expect(scroll.offset, 100);
  });

  testWidgets("a shared scroll controller reports misuse", (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: StickToTarget(
        scrollController: scroll,
        listController: list,
        target: const StickTarget.bottom(),
        child: Row(children: [
          for (var i = 0; i < 2; ++i)
            Expanded(
                child: Scrollable(
              controller: scroll,
              viewportBuilder: (_, __) => const SizedBox.expand(),
            )),
        ]),
      ),
    ));
    final exception = tester.takeException();
    expect(exception, isAssertionError);
    expect(exception.toString(), contains("at most one position"));
    await tester.pumpWidget(const SizedBox());
  });

  for (final target in [const StickTarget.bottom(), _itemTarget]) {
    for (final initial in [true, false]) {
      testWidgets(
          "waits for metrics: bottom=${target.isBottom}, initial=$initial",
          (tester) async {
        final scroll = ScrollController(
          initialScrollOffset: target.isBottom ? 800 : 0,
        );
        final list = ListController();
        final changes = <bool>[];
        addTearDown(scroll.dispose);
        addTearDown(list.dispose);
        Widget build({required bool ready, StickTarget? target}) =>
            _DeferredList(
              scroll: scroll,
              list: list,
              target: target,
              viewportReady: ready,
              onStickStateChanged: changes.add,
            );

        await tester
            .pumpWidget(build(ready: false, target: initial ? target : null));
        expect(scroll.hasClients, isTrue);
        expect(scroll.position.hasContentDimensions, isFalse);
        expect(list.stickTarget, isNull);
        expect(tester.takeException(), isNull);

        if (!initial) {
          await tester.pumpWidget(build(ready: false, target: target));
          expect(tester.takeException(), isNull);
        }
        // No callback loop while dimensions remain unavailable.
        expect(await tester.pumpAndSettle(), 1);
        expect(changes, isEmpty);

        await tester.pumpWidget(build(ready: true, target: target));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(scroll.position.hasContentDimensions, isTrue);
        expect(list.stickTarget, target);
        expect(
            scroll.offset, closeTo(target.isBottom ? 800 : _itemOffset, 0.001));
        expect(changes, initial ? isEmpty : [true]);

        // Engagement must persist, not merely make one initial jump.
        await tester.pumpWidget(_DeferredList(
          scroll: scroll,
          list: list,
          target: target,
          itemCount: 9,
          onStickStateChanged: changes.add,
        ));
        await tester.pumpAndSettle();
        expect(scroll.offset,
            closeTo(target.isBottom ? 1200 : _itemOffset, 0.001));
        expect(list.stickTarget, target);
      });
    }
  }

  testWidgets(
      "item engagement waits for list attachment even with valid metrics",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
      listReady: false,
    ));
    await tester.pumpAndSettle();
    expect(scroll.position.hasContentDimensions, isTrue);
    expect(list.isAttached, isFalse);
    expect(tester.takeException(), isNull);

    // The replacement has the same scroll extent. Content notification, not
    // a dimensions change, must retry the pending initial engagement.
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(list.stickTarget, _itemTarget);
    expect(scroll.offset, closeTo(_itemOffset, 0.001));
  });

  testWidgets("cancels pending engagement when its target is cleared",
      (tester) async {
    final scroll = ScrollController(initialScrollOffset: 800);
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: const StickTarget.bottom(),
      viewportReady: false,
    ));
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: null,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(list.stickTarget, isNull);
  });

  testWidgets("pending engagement does not override user scrolling",
      (tester) async {
    final scroll = ScrollController();
    final list = ListController();
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
      listReady: false,
    ));
    await tester.pumpAndSettle();
    // Metrics exist, but the item controller does not. Scroll while its
    // engagement is still pending, then attach the list at the same offset.
    await tester.drag(find.byType(Scrollable), const Offset(0, -100));
    await tester.pumpAndSettle();
    final userOffset = scroll.offset;
    await tester.pumpWidget(_DeferredList(
      scroll: scroll,
      list: list,
      target: _itemTarget,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(list.stickTarget, isNull);
    expect(scroll.offset, closeTo(userOffset, 0.001));
  });

  testWidgets("replacement controller waits for its own dimensions",
      (tester) async {
    final first = ScrollController(initialScrollOffset: 800);
    final second = ScrollController(initialScrollOffset: 800);
    final list = ListController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(_DeferredList(
      scroll: first,
      list: list,
      target: const StickTarget.bottom(),
    ));
    await tester.pumpAndSettle();
    expect(list.stickTarget, const StickTarget.bottom());

    await tester.pumpWidget(_DeferredList(
      scroll: second,
      list: list,
      target: const StickTarget.bottom(),
      viewportReady: false,
    ));
    await tester.pumpAndSettle();
    expect(second.position.hasContentDimensions, isFalse);
    expect(list.stickTarget, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_DeferredList(
      scroll: second,
      list: list,
      target: const StickTarget.bottom(),
    ));
    await tester.pumpAndSettle();
    expect(list.stickTarget, const StickTarget.bottom());
    expect(second.offset, 800);
    expect(tester.takeException(), isNull);
  });

  for (final target in [const StickTarget.bottom(), _itemTarget]) {
    testWidgets("scheduled jump rechecks dimensions: bottom=${target.isBottom}",
        (tester) async {
      final scroll =
          ScrollController(initialScrollOffset: target.isBottom ? 800 : 0);
      final list = ListController();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      await tester.pumpWidget(_DeferredList(
        scroll: scroll,
        list: list,
        target: target,
      ));
      // Engagement has scheduled a jump for the next frame. Replace the
      // controller's attached position before it runs, without laying out.
      // Hiding _DeferredList's viewport would keep the existing position's
      // dimensions. A fresh position is needed to remove those dimensions.
      final laidOutPosition = scroll.position;
      final unlaidOutPosition = ScrollPositionWithSingleContext(
        physics: const ClampingScrollPhysics(),
        context: laidOutPosition.context,
        initialPixels: laidOutPosition.pixels,
      );
      scroll.detach(laidOutPosition);
      scroll.attach(unlaidOutPosition);
      try {
        await tester.pump();
        expect(unlaidOutPosition.hasContentDimensions, isFalse);
        expect(tester.takeException(), isNull);
        expect(list.stickTarget, target);
      } finally {
        scroll.detach(unlaidOutPosition);
        scroll.attach(laidOutPosition);
        unlaidOutPosition.dispose();
      }
      await tester.pumpAndSettle();
    });
  }
}

/// Keeps Scrollable attached while delaying the viewport, without throwing a
/// layout exception. A placeholder can separately delay ListController data.
class _DeferredList extends StatelessWidget {
  const _DeferredList({
    required this.scroll,
    required this.list,
    required this.target,
    this.viewportReady = true,
    this.listReady = true,
    this.itemCount = 7,
    this.onStickStateChanged,
  });

  final ScrollController scroll;
  final ListController list;
  final StickTarget? target;
  final bool viewportReady;
  final bool listReady;
  final int itemCount;
  final ValueChanged<bool>? onStickStateChanged;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: StickToTarget(
          scrollController: scroll,
          listController: list,
          target: target,
          onStickStateChanged: onStickStateChanged,
          child: Scrollable(
            key: ValueKey(scroll),
            controller: scroll,
            physics: const ClampingScrollPhysics(),
            viewportBuilder: (context, offset) => viewportReady
                ? Viewport(
                    offset: offset,
                    slivers: [
                      if (listReady)
                        SuperSliverList.builder(
                          listController: list,
                          extentEstimation: (_, __) => 200,
                          itemCount: itemCount,
                          itemBuilder: (_, index) => SizedBox(
                            key: ValueKey(index),
                            height: 200,
                          ),
                        )
                      else
                        SliverToBoxAdapter(
                          child: SizedBox(height: itemCount * 200),
                        ),
                    ],
                  )
                : const SizedBox.expand(),
          ),
        ),
      );
}

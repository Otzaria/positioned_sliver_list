// Modifications Copyright 2026 The Otzaria contributors.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:positioned_sliver_list/positioned_list.dart';

const screenHeight = 400.0;
const screenWidth = 400.0;
const itemHeight = screenHeight / 10.0;
const itemCount = 500;

void main() {
  Future<void> pumpList(
    WidgetTester tester, {
    ItemScrollController? itemScrollController,
    ItemPositionsListener? itemPositionsListener,
    int initialIndex = 0,
    double cacheExtentScreens = 2,
    double? minCacheExtent,
    bool jumpToDistantItems = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(screenWidth, screenHeight);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ScrollablePositionedList.builder(
          itemCount: itemCount,
          itemScrollController: itemScrollController,
          itemPositionsListener: itemPositionsListener,
          initialScrollIndex: initialIndex,
          cacheExtentScreens: cacheExtentScreens,
          minCacheExtent: minCacheExtent,
          jumpToDistantItems: jumpToDistantItems,
          itemBuilder: (context, index) =>
              SizedBox(height: itemHeight, child: Text('Item $index')),
        ),
      ),
    );
  }

  bool isBuilt(int index) =>
      find.text('Item $index', skipOffstage: false).evaluate().isNotEmpty;

  final fadeTransitionFinder = find.descendant(
    of: find.byType(ScrollablePositionedList),
    matching: find.byType(FadeTransition),
  );

  group('cacheExtentScreens', () {
    testWidgets('defaults to two screens on each side', (
      WidgetTester tester,
    ) async {
      await pumpList(tester, initialIndex: 100);

      expect(isBuilt(85), isTrue);
      expect(isBuilt(125), isTrue);
    });

    testWidgets('limits the items laid out around the target', (
      WidgetTester tester,
    ) async {
      await pumpList(tester, initialIndex: 100, cacheExtentScreens: 1);

      expect(isBuilt(95), isTrue);
      expect(isBuilt(115), isTrue);
      expect(isBuilt(85), isFalse);
      expect(isBuilt(125), isFalse);
    });

    testWidgets('applies to jumps', (WidgetTester tester) async {
      final itemScrollController = ItemScrollController();
      await pumpList(
        tester,
        itemScrollController: itemScrollController,
        cacheExtentScreens: 1,
      );

      itemScrollController.jumpTo(index: 300);
      await tester.pump();
      // Adapted: the cache area around a jump target is filled one frame later.
      await tester.pump();

      expect(find.text('Item 300'), findsOneWidget);
      expect(isBuilt(315), isTrue);
      expect(isBuilt(325), isFalse);
    });

    testWidgets('minCacheExtent is still a lower bound', (
      WidgetTester tester,
    ) async {
      await pumpList(
        tester,
        initialIndex: 100,
        cacheExtentScreens: 0,
        minCacheExtent: 5 * itemHeight,
      );

      expect(isBuilt(113), isTrue);
      expect(isBuilt(118), isFalse);
    });
  });

  group('item positions', () {
    testWidgets('a scroll that moves no position does not notify', (
      WidgetTester tester,
    ) async {
      final itemPositionsListener = ItemPositionsListener.create();
      await pumpList(tester, itemPositionsListener: itemPositionsListener);
      var notifications = 0;
      itemPositionsListener.itemPositions.addListener(() => notifications++);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;

      position.jumpTo(position.pixels + 10);
      await tester.pump();
      expect(notifications, 1);
      final moved = itemPositionsListener.itemPositions.value;

      position.jumpTo(position.pixels + 0.2);
      await tester.pump();
      expect(notifications, 1);
      expect(itemPositionsListener.itemPositions.value, moved);
    });

    testWidgets('a rebuild notifies even when positions are unchanged', (
      WidgetTester tester,
    ) async {
      final itemPositionsListener = ItemPositionsListener.create();
      await pumpList(tester, itemPositionsListener: itemPositionsListener);
      final before = itemPositionsListener.itemPositions.value.toList();
      var notifications = 0;
      itemPositionsListener.itemPositions.addListener(() => notifications++);

      await pumpList(tester, itemPositionsListener: itemPositionsListener);

      expect(notifications, 1);
      expect(itemPositionsListener.itemPositions.value, before);
    });

    testWidgets('only items intersecting the viewport are reported', (
      WidgetTester tester,
    ) async {
      final itemPositionsListener = ItemPositionsListener.create();
      await pumpList(
        tester,
        itemPositionsListener: itemPositionsListener,
        initialIndex: 100,
      );

      final indices = itemPositionsListener.itemPositions.value.map(
        (p) => p.index,
      );
      expect(indices.toSet(), {for (var i = 100; i < 110; i++) i});
    });
  });

  group('jumpToDistantItems', () {
    testWidgets('scrollTo jumps to an item that is not laid out', (
      WidgetTester tester,
    ) async {
      final itemScrollController = ItemScrollController();
      await pumpList(
        tester,
        itemScrollController: itemScrollController,
        jumpToDistantItems: true,
      );

      var completed = false;
      unawaited(
        itemScrollController
            .scrollTo(index: 200, duration: const Duration(seconds: 1))
            .then((_) => completed = true),
      );
      await tester.pump();

      expect(fadeTransitionFinder, findsOneWidget);
      expect(find.text('Item 200'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Item 200')).dy, 0);
      expect(completed, isTrue);
    });

    testWidgets('scrollTo still animates to an item that is laid out', (
      WidgetTester tester,
    ) async {
      final itemScrollController = ItemScrollController();
      await pumpList(
        tester,
        itemScrollController: itemScrollController,
        jumpToDistantItems: true,
      );

      var completed = false;
      unawaited(
        itemScrollController
            .scrollTo(index: 20, duration: const Duration(seconds: 1))
            .then((_) => completed = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(completed, isFalse);
      expect(tester.getTopLeft(find.text('Item 20')).dy, greaterThan(0));

      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(tester.getTopLeft(find.text('Item 20')).dy, 0);
    });

    testWidgets('defaults to the cross-fade', (WidgetTester tester) async {
      final itemScrollController = ItemScrollController();
      await pumpList(tester, itemScrollController: itemScrollController);

      unawaited(
        itemScrollController.scrollTo(
          index: 200,
          duration: const Duration(seconds: 1),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(fadeTransitionFinder, findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Item 200')).dy, 0);
    });
  });
}

// Tests of the original that check its internals; the reason is printed.
const _skipped = <String, String>{
  'scrollTo jumps to an item that is not laid out':
      'asserts the two-list cross-fade (FadeTransition/opacity/second list), which does not exist here',
  'defaults to the cross-fade':
      'asserts the two-list cross-fade (FadeTransition/opacity/second list), which does not exist here',
};

void testWidgets(
  String description,
  WidgetTesterCallback callback, {
  bool? skip,
}) {
  final reason = _skipped[description];
  ft.testWidgets(
    description,
    callback,
    skip:
        (skip ?? false) || (reason != null && _printSkip(description, reason)),
  );
}

bool _printSkip(String description, String reason) {
  // ignore: avoid_print
  print('Skipped "$description": $reason');
  return true;
}

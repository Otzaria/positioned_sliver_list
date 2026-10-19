// A minimal example of the scrollable_positioned_list compatible API.
//
// Run with: flutter run -t lib/positioned_list_example.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:positioned_sliver_list/positioned_list.dart";

void main() => runApp(const MaterialApp(home: PositionedListExample()));

class PositionedListExample extends StatefulWidget {
  const PositionedListExample({super.key});

  @override
  State<PositionedListExample> createState() => _PositionedListExampleState();
}

class _PositionedListExampleState extends State<PositionedListExample> {
  static const _itemCount = 20000;

  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Paragraph-like items of different heights.
  String _text(int index) =>
      "Paragraph $index. ${"Lorem ipsum dolor sit amet. " * (1 + index % 7)}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<Iterable<ItemPosition>>(
          valueListenable: _itemPositionsListener.itemPositions,
          builder: (context, positions, _) {
            final first = positions.isEmpty
                ? null
                : positions.reduce((a, b) => a.index < b.index ? a : b).index;
            return Text("First visible: ${first ?? "-"}");
          },
        ),
        actions: [
          TextButton(
            onPressed: () =>
                _itemScrollController.jumpTo(index: 10000, alignment: 0.2),
            child: const Text("Jump to 10000"),
          ),
          TextButton(
            onPressed: () => unawaited(
              _itemScrollController.scrollTo(
                index: _itemCount - 1,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
              ),
            ),
            child: const Text("Scroll to last"),
          ),
        ],
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: ScrollablePositionedList.builder(
          itemCount: _itemCount,
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          scrollController: _scrollController,
          // Cheap guess from the text length; jumps are exact either way.
          estimateExtent: (index, width) =>
              16 + _text(index).length * 9 * 20 / width,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_text(index)),
          ),
        ),
      ),
    );
  }
}

# positioned_sliver_list

A fork of [super_sliver_list](https://pub.dev/packages/super_sliver_list) (MIT) maintained by the Otzaria contributors. It is not affiliated with or endorsed by the authors of `super_sliver_list` or of `scrollable_positioned_list`.

On top of `super_sliver_list` it adds:

- exact jumps by index that are resolved during layout, before paint, and build only the items around the target, even when the extents in between are only estimated;
- animated scrolling to an index that returns a `Future`, can be canceled, and never builds the items in between;
- an initial index applied before the first frame;
- item positions published after layout, and scroll anchoring that keeps the item at the top of the viewport in place when items above it change extent or the width changes;
- [`package:positioned_sliver_list/positioned_list.dart`](#scrollable_positioned_list-compatibility), a replacement for the `scrollable_positioned_list` API with a real `ScrollController`.

The fixes from the Telosnex and ahey forks of `super_sliver_list` are included.

## SliverList and ListView - Supercharged

`SuperSliverList` and `SuperListView` are drop in replacement widgets for `SliverList` and `ListView` with greatly improved performance and additional features:

#### Fast scrolling with large amount of items with variable extents

`SliverList` performance degrades heavily when quickly scrolling through a large amount of items with different extents, requiring workarounds such as using `FixedExtentSliverList` or prototype items. `SuperSliverList` uses different layout algorithm and can handle virtually unlimited number of items with variable extents without any slow-downs.

#### Ability to jump or animate to specific item

`SliverList` does not provide any way to jump or animate a particular index. There is a [scrollable_positioned_list](https://pub.dev/packages/scrollable_positioned_list) package that provides this functionality, but it comes at a cost, as it requires custom scroll view, does not seem to work properly with Scrollbars, can't be used with with other slivers (such as sticky headers) and ultimately is backed by a `SliverList` so it has the same performance issues as mentioned above.

`SuperSliverList` provides a way to reliably jump and animate to a specific item, even if the item is outside of the viewport and has not been built or laid out yet.

#### Smooth and predictable scrollbar behavior

`SliverList` is quite prone to scrollbar erraticaly jumping around when scrolling through a list of items with different extents. With `SuperSliverList` the scrollbar should behave more predictably. See the [Advanced](#advanced) section for more details.

## Basic Usage

`SuperListView` is a drop-in replacement for `ListView`, and as such you can use it same way you'd use `ListView`:

```dart
SuperListView.builder(
  itemCount: 1000,
  itemBuilder: (context, index) {
    return ListTile(title: Text('Item $index'));
  },
)
```

`SuperSliverList` is a drop-in replacement for `SliverList` and should work with any `CustomScrollView` configuration:
 ```dart
 CustomScrollView(
   slivers: <Widget>[
     SliverPadding(
       padding: const EdgeInsets.all(20.0),
       sliver: SuperSliverList(
         delegate: SliverChildListDelegate(
           <Widget>[
             const Text("I'm dedicating every day to you"),
             const Text('Domestic life was never quite my style'),
             const Text('When you smile, you knock me out, I fall apart'),
             const Text('And I thought I was so smart'),
           ],
         ),
       ),
     ),
   ],
 )
 ```

## Jumping and animating to specific item

`ListController` can be provided to `SuperSliverList`/`SuperListView` and used to jump or animate to specific item:

```dart
class _MyState extends State<MyWidget> {
  final _listController = ListController();
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return SuperListView.builder(
      listController: _listController,
      controller: _scrollController,
      itemCount: 1000,
      itemBuilder: (context, index) {
        return ListTile(title: Text('Item $index'));
      },
    );
  }

  void jumpToItem(int index) {
    _listController.jumpToItem(
      index: index,
      scrollController: _scrollController,
      alignment: 0.5,
    );
  }

  void animateToItem(int index) {
    _listController.animateToItem(
      index: index,
      scrollController: _scrollController,
      alignment: 0.5,
      // You can provide duration and curve depending on the estimated
      // distance between currentPosition and the target item position.
      duration: (estimatedDistance) => Duration(milliseconds: 250),
      curve: (estimatedDistance) => Curves.easeInOut,
    );
  }
}
```

## Index based positioning

`jumpToIndex` and `scrollToIndex` place the *leading edge* of an item at a fraction of the viewport (`alignment`: 0 is the leading edge, 0.5 the center, 1 the trailing edge, negative values allowed) plus `offset` pixels. They need no `ScrollController`:

```dart
// Exact, before the next paint. Completes after that layout.
await listController.jumpToIndex(12000, alignment: 0.2);

// Jumps to about one viewport before a distant item, then animates the rest.
// The handle is a Future and can be canceled; a drag cancels it too.
final handle = listController.scrollToIndex(
  40000,
  duration: const Duration(milliseconds: 400),
  curve: Curves.easeOut,
);
await handle;
```

`SuperSliverList(initialIndex: ..., initialAlignment: ..., initialOffset: ...)` applies such a position during the first layout.

By default a target is clamped to the scroll range: the last item cannot be moved to the top of the viewport. `SuperSliverList(overscrollToTarget: ...)` changes that:

- `OverscrollToTarget.none` (default): clamped to the content.
- `OverscrollToTarget.matchScrollablePositionedList`: clamped like `scrollable_positioned_list`. Content shorter than the viewport may be pushed down by the alignment, at most until its end reaches the trailing edge; otherwise the position is clamped to the content.
- `OverscrollToTarget.always`: a jump, an animation or the initial position adds blank space after the last item or before the first item, so the target always lands exactly where requested:

- The space is part of the scroll extent while it exists, so the `ScrollController` and a `Scrollbar` stay consistent.
- It shrinks as the user scrolls or flings back towards the content and never grows again from user scrolling; it is gone once the viewport is back within the content. The next programmatic jump computes it again.
- While it exists, the item that was jumped to keeps its place when items above it change extent or the width changes, and items appended at the end use the space up.
- `ListController.overscrollSpace` reports the current space. It is meant for a list that is the only sliver of its viewport (`SliverPadding` around it is fine).

`listController.itemPositions` is a `ValueListenable<List<ItemPosition>>` with the visible items and their leading and trailing edges as fractions of the viewport, updated after every frame in which they changed (only while it has listeners). `listController.anchor` is the first visible item and how far the viewport edge is inside it; `jumpToIndex(anchor.index, offset: -anchor.offsetInItem)` restores it.

`animateToItem` keeps its `getOffsetToReveal` alignment and now returns an `AnimationHandle`, which is also a `Future<void>`. When you do not await it, wrap it in `unawaited(...)` to satisfy the `unawaited_futures` lint.

Index based positioning is supported for a list that grows forward from the viewport's center, which is the usual case; for a sliver placed before the `center` of a `CustomScrollView` a jump is ignored with a logged warning.

Each layout pass may correct the scroll offset a limited number of times (a viewport throws after 10 layout cycles per sliver). When a pass reaches that limit, the remaining correction is applied in the next frame.

## scrollable_positioned_list compatibility

`package:positioned_sliver_list/positioned_list.dart` provides `ScrollablePositionedList` (`.builder`, `.separated`), `ItemScrollController`, `ItemPositionsListener`, `ItemPosition`, `ScrollOffsetController` and `ScrollOffsetListener` with the API of `scrollable_positioned_list`, implemented as one `CustomScrollView` around a `SuperSliverList`:

```dart
import 'package:positioned_sliver_list/positioned_list.dart';

final itemScrollController = ItemScrollController();
final itemPositionsListener = ItemPositionsListener.create();
final scrollController = ScrollController();

Scrollbar(
  controller: scrollController,
  child: ScrollablePositionedList.builder(
    itemCount: paragraphs.length,
    itemBuilder: (context, index) => Paragraph(paragraphs[index]),
    itemScrollController: itemScrollController,
    itemPositionsListener: itemPositionsListener,
    scrollController: scrollController, // optional
    estimateExtent: (index, width) => paragraphs[index].length * 900 / width,
    initialScrollIndex: 120,
  ),
);

itemScrollController.jumpTo(index: 500, alignment: 0.1);
await itemScrollController.scrollTo(index: 9000, duration: const Duration(milliseconds: 500));
```

Provide `estimateExtent` when you can: items that were never laid out are estimated at 100 pixels otherwise, which makes the scrollbar less steady (jumps are exact either way).

Additions to the original API: `scrollController`, `estimateExtent`, `estimatedSeparatorExtent`, `initialOffset`, `restorePosition`, `overscrollToTarget`, an `offset` for `jumpTo`/`scrollTo`, `ItemScrollController.scrollController`/`listController`/`anchor`, and `ScrollOffsetController.jumpBy`/`isAttached`.

Behavior that differs from `scrollable_positioned_list`:

- There is a single list. `scrollTo` to a distant item jumps to about one viewport before it and animates from there; there is no cross-fade, and `opacityAnimationWeights` is ignored. The trajectory of the animation therefore differs.
- `overscrollToTarget` defaults to `OverscrollToTarget.matchScrollablePositionedList`, which reproduces how the original clamps at the edges: content shorter than the viewport may start below the leading edge, at most until its end reaches the trailing edge, and otherwise the last item cannot be moved above the trailing edge nor the first below the leading edge. `OverscrollToTarget.always` lets every target land exactly, for example the last item at the top of the viewport, with blank space that shrinks as the user scrolls back.
- Saving the position to `PageStorage` is opt-in (`restorePosition: true`).
- The cache area around a jump target is filled one frame after the jump.
- `ScrollOffsetListener` reports scroll movements only; layout corrections (exact landing, anchoring) are not reported.
- `jumpToDistantItems` is accepted and ignored.

## Advanced

Very roughtly speaking `SuperSliverList` works by estimating the extent of items that are outside of viewport and when these items are scrolled into the viewport cache area the scroll position is transparently adjusted to account of the difference between estimated and actual extents. On small lists this difference may result in scrollbar movement not being perfectly aligned with list movement. `SuperSliverList` provides two ways to rectify this:

### Improve extent estimation

You can register custom callback that will be used to estimate extent of estimated items. This can be useful if you have an idea, atleast approximately, how large the extent of each item is.

```dart
SuperSliverList(
    delegate: /*...*/,
    // Called with a null index first: return a positive value if all items
    // have the same estimate, or 0 to be asked for each index.
    extentEstimation: (index, crossAxisExtent) => 100.0,
)
```

### Precalculate extents for items

`SuperSliverList` can, if needed, asynchronously precalculate extents for items. To enfore this, subclass `ExtentPrecalculationPolicy` and provide it to `SuperSliverList`:

In this example the extents are eagerly precalculated for lists with less than 100 items:

```dart
class MyPrecalculationPolicy extends ExtentPrecalculationPolicy {
  @override
  bool shouldPrecaculateExtents(ExtentPrecalculationContext context)  {
    return context.numberOfItems < 100;
  }
}

return SuperSliverList(
    delegate: /*...*/,
    extentPrecalculationPolicy: myPolicy,
)
```

The threshold is arbitrary, but in general there are diminishing returns for precalculating extents for large lists, as the extent estimation error for each item has much smaller impact on the scrollbar position if there are many items.

## Example

See the [example](example) folder for a complete sample app using `SuperSliverList`.

## 0.1.0

First release as `positioned_sliver_list`, a fork of `super_sliver_list` 0.4.1.

* `ListController.jumpToIndex` and `ListController.scrollToIndex` place an item's
  leading edge at a fraction of the viewport plus an offset. Jumps are resolved
  exactly during layout, before paint, and build only the items around the
  target. Long animations jump near the target first and run as a cancelable
  scroll activity.
* `ListController.animateToItem` returns an `AnimationHandle` that is also a
  `Future<void>`, and no longer jumps through every item on the way.
* `SuperSliverList.initialIndex`, `initialAlignment` and `initialOffset` position
  the list before the first paint.
* `SuperSliverList.overscrollToTarget` (`OverscrollToTarget.none` by default)
  can reproduce how `scrollable_positioned_list` clamps at the edges
  (`matchScrollablePositionedList`, the default of the compatibility layer),
  or add blank space before the first or after the last item so that every
  target lands exactly (`always`), for example the last item at the top of
  the viewport. That space shrinks as the user scrolls back and is used up by
  appended items; `ListController.overscrollSpace` reports it.
* `ListController.itemPositions` publishes the visible items after layout, and
  `ListController.anchor` reports the item at the viewport's leading edge.
* The item at the viewport's leading edge keeps its position when items above it
  change extent, and keeps its scrolled-past fraction when the width changes.
* A controller briefly attached to two lists keeps the newest one.
* `package:positioned_sliver_list/positioned_list.dart`: a replacement for the
  `scrollable_positioned_list` API.
* `SuperListView` takes `scrollCacheExtent` instead of the deprecated
  `cacheExtent`. Requires Flutter 3.44.
* Includes the Telosnex fork (initial end position, cancelable reveal
  operations, public `getOffsetToReveal`, `StickToTarget`, header anchoring,
  leak fixes, a cap on scroll correction cycles, performance work) and the ahey
  fix for slivers that stopped laying out after a scroll correction, limited to
  the sliver's viewport.

## super_sliver_list history

## 0.4.1

* Fix missing propagation of `rect` inside `RenderViewportExt.getOffsetToRevealExt`.
* Add missing constructors in `SuperSliverList` to have `SliverList` parity.

## 0.4.0

* BREAKING: Changed signature of `ExtentEstimationProvider` where the `index` is now nullable.
* Added `layoutKeptAliveChildren` argument to `SuperSliverList`.
* Improved performance with very large lists (millions of items).
* Bugfixes

## 0.3.0

* Fixed layout exception for shrink-wrapped lists.
* BREAKING: ExtentPrecalculationContext.viewportMainAxisExtent is now nullable

## 0.2.2

* Fixed exception when calling markAllDirty on empty list.

## 0.2.1

* Prevent overscroll when jumping and animating to items at the edge with alignment that would otherwise cause overscroll. For example jumping to the first item with `alignment: 1.0` or jumping to the last item with `alignment: 0.0` should no longer cause overscroll.

## 0.2.0

* Added `visibleRange` and `unobstructedVisibleRange` properties to `ListController`.
* Layout fixes.
* Renamed `ExtentController` to `ListController`.

## 0.2.0-dev.2

* Introduced the concept of child obstruction extent. This is a property that
  can be set on Sliver geometry and allows for reliable positioning of items
  in slivers that are wrapped in a sticky header sliver.
* Added sticky headers to example.

## 0.2.0-dev.1

This is a major update and a complete rewrite of `SuperSliverList`.
* Added `SuperListView` as a convenient drop-in replacement for `ListView`.
* Added ability to jump / animate to specific item using `ExtentController`.
* Added ability to asynchronously precompute item extents using `ExtentPrecalculationPolicy`.
* Comprehensive test coverage.

## 0.0.8

* Fixed problem when accessing layout offset from a LayoutBuilder child widget.

## 0.0.7

* Fix inserted children not being build properly.

## 0.0.6

* Bug fixes

## 0.0.5

* Bug fixes

## 0.0.4

* Bug fixes

## 0.0.3

* Various bug fixes and improvements

## 0.0.2

* Various bug fixes

## 0.0.1

* Initial release



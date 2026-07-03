/// Feature flags for performance optimizations in SuperSliverList.
///
/// Each flag gates one optimization so that its old and new code paths can be
/// benchmarked against each other in-process (see `test/perf/`). All flags
/// default to `true` (optimized behavior). Setting a flag to `false` restores
/// the previous behavior.
///
/// These flags are global and not thread-safe; they are intended for
/// benchmarking and as an escape hatch, not for per-list configuration.
abstract final class SuperSliverListPerfFlags {
  /// Win 1: `RenderSuperSliverList.childScrollOffset` used an O(n) linear
  /// scan over live children (called from O(n) loops during layout, giving
  /// O(n²) behavior). When enabled, an O(1) membership check is used instead.
  static bool fastChildScrollOffsetLookup = true;

  /// Win 2: When inserting k leading children during layout, each insertion
  /// shifted the layout offset of all subsequent children (O(k·n)). When
  /// enabled, the shift is accumulated and applied in a single O(n) pass.
  static bool batchLeadingChildShift = true;

  /// Win 3: The Fenwick tree used for offset/index queries was discarded and
  /// rebuilt from scratch (O(n)) whenever the item count changed. When
  /// enabled, appends are incremental (O(log n)) and truncations are O(1).
  static bool incrementalFenwick = true;

  /// Win 4: Extent precalculation invoked `invokeLayoutCallback` and
  /// `BuildOwner.buildScope` once *per measured item*. When enabled, a single
  /// layout callback and build scope wrap the whole measuring loop.
  static bool batchExtentPrecalculation = true;

  /// Win 5: `_firstWholeVisibleChild` walked all leading cache-area children
  /// on every layout, but its result is only consumed while the cross axis is
  /// resizing. When enabled, the walk only happens in that case.
  static bool lazyFirstVisibleChild = true;

  /// Win 6: `ExtentList.setExtent` reset the tracked clean range to a single
  /// index, forcing the lazy clean-range getters to re-walk the whole clean
  /// span (O(n), quadratic during extent precalculation). When enabled, the
  /// tracked range is extended incrementally when the cleaned index is inside
  /// or adjacent to it.
  static bool incrementalCleanRange = true;

  /// Win 7: `ExtentList.markDirty` discarded the entire tracked clean range.
  /// When enabled, the range is only shrunk to exclude the dirtied index
  /// (keeping the larger side when the index is inside the range).
  static bool preserveCleanRangeOnMarkDirty = true;

  /// Win 8: `addTrailingChild` computed `childScrollOffset + paintExtentOf`
  /// of the last child twice per inserted child. When enabled, the value is
  /// computed once and reused.
  static bool hoistTrailingChildValues = true;

  /// Win 9: `getActualPrecedingScrollExtent` walked this sliver's ancestor
  /// chain once per preceding viewport child (O(children * depth)). When
  /// enabled, a single upward walk finds the direct viewport child containing
  /// this sliver (O(children + depth)).
  static bool fastPrecedingScrollExtent = true;

  /// Win 10: [ListController] notified its listeners on every layout where
  /// anything changed, including pure visible-range changes during scrolling.
  /// When enabled, [StickToTarget] subscribes to the extents-only channel
  /// ([ListController.extentsChangedListenable]) so it is not invoked on
  /// every scroll frame. (The channel itself is always maintained.)
  static bool extentsOnlyStickNotifications = true;

  /// Win 11: The scrolled-past/not-reached layout path started a [Stopwatch]
  /// on every layout of every invisible sliver purely for logging. When
  /// enabled, the stopwatch is only created when FINER logging is active.
  static bool guardInvisibleLayoutLogging = true;

  /// Win 12: `_layoutKeptAliveChildren` made two full `visitChildren` passes
  /// over all children (live + kept alive) and converted constraints once per
  /// kept-alive child. When enabled, kept-alive children are collected during
  /// a single traversal and the constraints conversion is hoisted.
  static bool optimizedKeptAliveLayout = true;

  /// Win 13: `_shouldPrecalculateExtents` performed the viewport ancestor
  /// walk and allocated an [ExtentPrecalculationContext] on every call, even
  /// though the result is cached per layout pass (`??=`). When enabled, the
  /// work only happens when the cached value is absent. The method is invoked
  /// repeatedly per pass (including once per invisible sliver via the
  /// skip-precalculation check).
  static bool cachedShouldPrecalculateExtents = true;

  /// Win 14: `ResizableFloat64List._maybeTrim` trimmed capacity as soon as
  /// `capacity / 2 >= length`, so at a power-of-two boundary a single
  /// remove+insert cycle caused two full O(n) copies (trim, then re-grow).
  /// When enabled, trimming requires `capacity / 4 >= length` (hysteresis),
  /// leaving headroom after the trim.
  static bool trimHysteresis = true;

  /// Win 15: `ExtentList.insertAt`/`removeAt` unconditionally discarded the
  /// tracked clean range, even for pure appends / tail removals where it
  /// remains valid. When enabled, the range is shifted/clipped instead,
  /// keeping the precalculation anchor across structural changes (streaming
  /// chat: one O(n) clean-range re-walk per appended message avoided).
  static bool preserveCleanRangeOnStructuralChange = true;
}

import "package:flutter/foundation.dart";

/// Cumulative cost of refreshing estimated extents and rebuilding the offset
/// index of one list, read through `ListController.estimateRefreshStats`.
///
/// Both operations are linear in the number of items. Counters accumulate for
/// the lifetime of the list and survive attaching its controller again.
@immutable
class EstimateRefreshStats {
  const EstimateRefreshStats({
    this.refreshCount = 0,
    this.lastRefreshItemCount = 0,
    this.lastRefreshDuration = Duration.zero,
    this.deferredResizeCount = 0,
    this.skippedResizeCount = 0,
    this.indexRebuildCount = 0,
    this.lastIndexRebuildDuration = Duration.zero,
  });

  /// Number of passes over all items that replaced extents with new
  /// estimates: full refreshes, caused by a cross-axis extent change, an
  /// `estimationKey` change or `invalidateAllExtents`, and the refresh after
  /// a deferred cross-axis extent change settled.
  final int refreshCount;

  /// Number of items estimated by the most recent refresh.
  final int lastRefreshItemCount;

  /// Duration of the most recent refresh, excluding the offset index rebuild.
  final Duration lastRefreshDuration;

  /// Number of layouts that deferred the refresh after a cross-axis extent
  /// change until the extent stops changing.
  final int deferredResizeCount;

  /// Number of cross-axis extent changes that kept every extent because the
  /// list's `crossAxisLayoutKey` returned an equal value for the new extent.
  final int skippedResizeCount;

  /// Number of full rebuilds of the index that maps item indices to scroll
  /// offsets.
  final int indexRebuildCount;

  /// Duration of the most recent full offset index rebuild.
  final Duration lastIndexRebuildDuration;

  @override
  bool operator ==(Object other) =>
      other is EstimateRefreshStats &&
      other.refreshCount == refreshCount &&
      other.lastRefreshItemCount == lastRefreshItemCount &&
      other.lastRefreshDuration == lastRefreshDuration &&
      other.deferredResizeCount == deferredResizeCount &&
      other.skippedResizeCount == skippedResizeCount &&
      other.indexRebuildCount == indexRebuildCount &&
      other.lastIndexRebuildDuration == lastIndexRebuildDuration;

  @override
  int get hashCode => Object.hash(
    refreshCount,
    lastRefreshItemCount,
    lastRefreshDuration,
    deferredResizeCount,
    skippedResizeCount,
    indexRebuildCount,
    lastIndexRebuildDuration,
  );

  @override
  String toString() =>
      "EstimateRefreshStats(refreshCount: $refreshCount, "
      "lastRefreshItemCount: $lastRefreshItemCount, "
      "lastRefreshDuration: $lastRefreshDuration, "
      "deferredResizeCount: $deferredResizeCount, "
      "skippedResizeCount: $skippedResizeCount, "
      "indexRebuildCount: $indexRebuildCount, "
      "lastIndexRebuildDuration: $lastIndexRebuildDuration)";
}

/// Mutable counters behind [EstimateRefreshStats], owned by one list.
class EstimateRefreshCounters {
  // One running clock for all lists: a timed O(n) operation costs two reads.
  static final _clock = Stopwatch()..start();

  static int get nowMicros => _clock.elapsedMicroseconds;

  int refreshCount = 0;
  int lastRefreshItemCount = 0;
  int lastRefreshMicros = 0;
  int deferredResizeCount = 0;
  int skippedResizeCount = 0;
  int indexRebuildCount = 0;
  int lastIndexRebuildMicros = 0;

  void recordRefresh(int itemCount, int startMicros) {
    ++refreshCount;
    lastRefreshItemCount = itemCount;
    lastRefreshMicros = nowMicros - startMicros;
  }

  void recordIndexRebuild(int startMicros) {
    ++indexRebuildCount;
    lastIndexRebuildMicros = nowMicros - startMicros;
  }

  EstimateRefreshStats snapshot() => EstimateRefreshStats(
    refreshCount: refreshCount,
    lastRefreshItemCount: lastRefreshItemCount,
    lastRefreshDuration: Duration(microseconds: lastRefreshMicros),
    deferredResizeCount: deferredResizeCount,
    skippedResizeCount: skippedResizeCount,
    indexRebuildCount: indexRebuildCount,
    lastIndexRebuildDuration: Duration(microseconds: lastIndexRebuildMicros),
  );
}

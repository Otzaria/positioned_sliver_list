import "dart:math" as math;
import "dart:typed_data";

import "package:flutter/foundation.dart" show visibleForTesting;

/// Zero indexed Fenwick Tree
class FenwickTree {
  FenwickTree({required int size})
    : _size = size,
      _tree = Float64List(size + 1);

  FenwickTree.fromList({required Float64List list})
    : _size = list.length,
      _tree = Float64List(list.length + 1) {
    _build(_tree, list);
  }

  static void _build(Float64List tree, Float64List list) {
    final size = list.length;
    for (int i = 1; i <= size; ++i) {
      tree[i] += list[i - 1];
      if (i + (i & -i) <= size) {
        tree[i + (i & -i)] += tree[i];
      }
    }
  }

  /// Whether [rebuildFrom] with [size] elements keeps the backing store: it
  /// fits and stays more than a quarter full, as in [truncate].
  bool keepsBufferFor(int size) {
    final requiredLength = size + 1;
    return _tree.length >= requiredLength &&
        !(_tree.length > 16 && requiredLength <= _tree.length ~/ 4);
  }

  /// Rebuilds the tree from [list] in O(n); the result is bit-identical to
  /// [FenwickTree.fromList].
  void rebuildFrom(Float64List list) {
    final requiredLength = list.length + 1;
    if (keepsBufferFor(list.length)) {
      _tree.fillRange(0, requiredLength, 0.0);
    } else if (_tree.length < requiredLength) {
      // Headroom lets repeated middle insertions keep the new buffer.
      _tree = Float64List(requiredLength + (requiredLength >> 4));
    } else {
      _tree = Float64List(requiredLength);
    }
    _size = list.length;
    _build(_tree, list);
  }

  @visibleForTesting
  Float64List get debugBuffer => _tree;

  int get size => _size;

  /// Number of elements that fit without reallocating the backing store.
  int get capacity => _tree.length - 1;
  int _size;
  Float64List _tree;

  /// Update the value at index with delta. Index is 0 based.
  void update(int index, double delta) {
    final size = _size;
    ++index;
    while (index <= size) {
      _tree[index] += delta;
      index += index & -index;
    }
  }

  /// Returns the prefix sum of the elements from 0 to index-1. Index is 0 based.
  double query(int index) {
    double result = 0.0;
    while (index > 0) {
      result += _tree[index];
      index -= index & -index;
    }
    return result;
  }

  // Returns the index of last element whose prefix sum is less than or equal to prefixSum.
  int inverseQuery(double prefixSum) {
    final size = _size;
    if (size == 0) return 0;
    var index = 0;
    var bitmask = 1 << size.bitLength - 1;
    while (bitmask != 0 && index < size) {
      final nextIndex = index + bitmask;
      if (nextIndex <= size && _tree[nextIndex] <= prefixSum) {
        index = nextIndex;
        prefixSum -= _tree[index];
      }
      bitmask >>= 1;
    }
    return index;
  }

  /// Appends a new element at the end of the tree in O(log n).
  ///
  /// Amortized O(1) reallocation (backing store grows geometrically).
  void append(double value) {
    final index = _size + 1; // 1-based node index of the new element.
    if (index >= _tree.length) {
      final newTree = Float64List(math.max(_tree.length * 2, 16));
      newTree.setRange(0, _tree.length, _tree);
      _tree = newTree;
    }
    // Node `index` covers the range (index - lowbit(index), index]. Its value
    // is the new element plus the sum of the already-built nodes that tile
    // (index - lowbit(index), index - 1].
    double sum = value;
    final rangeStart = index - (index & -index);
    var j = index - 1;
    while (j > rangeStart) {
      sum += _tree[j];
      j -= j & -j;
    }
    _tree[index] = sum;
    _size = index;
  }

  /// Truncates to [newSize], releasing excess storage at quarter capacity.
  /// Existing prefix nodes remain valid; [append] recomputes discarded nodes.
  void truncate(int newSize) {
    assert(newSize >= 0 && newSize <= _size);
    _size = newSize;
    final requiredLength = newSize + 1;
    // Keep headroom so small shrink/grow cycles do not repeatedly allocate.
    if (_tree.length > 16 && requiredLength <= _tree.length ~/ 4) {
      final trimmed = Float64List(math.max(requiredLength * 2, 16));
      trimmed.setRange(0, requiredLength, _tree);
      _tree = trimmed;
    }
  }
}

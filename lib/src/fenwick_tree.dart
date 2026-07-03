import "dart:math" as math;
import "dart:typed_data";

/// Zero indexed Fenwick Tree
class FenwickTree {
  FenwickTree({
    required int size,
  })  : _size = size,
        _tree = Float64List(size + 1);

  FenwickTree.fromList({
    required Float64List list,
  })  : _size = list.length,
        _tree = Float64List(list.length + 1) {
    final size = _size;
    for (int i = 1; i <= size; ++i) {
      _tree[i] += list[i - 1];
      if (i + (i & -i) <= size) {
        _tree[i + (i & -i)] += _tree[i];
      }
    }
  }

  int get size => _size;
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

  /// Truncates the tree to [newSize] elements in O(1).
  ///
  /// Fenwick node `i` only depends on elements with index <= i, so nodes
  /// within the new size remain valid; stale nodes beyond it are ignored and
  /// fully recomputed by [append] if the tree grows again.
  void truncate(int newSize) {
    assert(newSize >= 0 && newSize <= _size);
    _size = newSize;
  }
}

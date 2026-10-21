import "dart:math" as math;
import "dart:typed_data";

import "package:positioned_sliver_list/src/fenwick_tree.dart";
import "package:test/test.dart";

void main() {
  test("large truncation releases memory and can grow again", () {
    final tree = FenwickTree(size: 1000000);
    for (var i = 0; i < 10; i++) {
      tree.update(i, i + 1.0);
    }
    tree.truncate(10);
    expect(tree.capacity, lessThanOrEqualTo(32));
    expect(tree.query(10), 55);
    tree.update(2, 7);
    for (var i = 0; i < 100; i++) {
      tree.append(2);
    }
    expect(tree.query(110), 262);
    expect(tree.inverseQuery(62), 10);
    tree.truncate(0);
    expect(tree.capacity, lessThanOrEqualTo(16));
    expect(tree.query(0), 0);
    expect(tree.inverseQuery(0), 0);
    tree.append(9);
    expect(tree.query(1), 9);
  });

  test("small changes keep capacity across shrink and regrowth", () {
    final tree = FenwickTree(size: 1024);
    final initialCapacity = tree.capacity;
    tree.truncate(800);
    expect(tree.capacity, initialCapacity);
    for (var i = 800; i < 1024; i++) {
      tree.append(1);
    }
    expect(tree.capacity, initialCapacity);
    expect(tree.query(1024), 224);
  });

  test("FenwickTree works", () {
    final tree = FenwickTree(size: 10);
    tree.update(0, 2);
    tree.update(1, 1);
    tree.update(2, 3);
    tree.update(3, 4);
    tree.update(4, 5);
    tree.update(5, 1);
    tree.update(6, 2);
    tree.update(7, 3);
    tree.update(8, 4);
    tree.update(9, 5);

    expect(tree.query(0), 0);
    expect(tree.query(3), 6);
    expect(tree.query(5), 15);
    expect(tree.query(6), 16);
    expect(tree.query(9), 25);
    expect(tree.query(10), 30);

    expect(tree.inverseQuery(0), 0);
    expect(tree.inverseQuery(1), 0);
    expect(tree.inverseQuery(2), 1);
    expect(tree.inverseQuery(5), 2);
    expect(tree.inverseQuery(6), 3);
    expect(tree.inverseQuery(25), 9);
    expect(tree.inverseQuery(29), 9);
    expect(tree.inverseQuery(30), 10);
    expect(tree.inverseQuery(300), 10);

    tree.update(5, 1);
    expect(tree.query(5), 15);
    expect(tree.query(6), 17);
    expect(tree.query(10), 31);
  });
  test("FenwickTree from list", () {
    final list = Float64List(10);
    list[0] = 2;
    list[1] = 1;
    list[2] = 3;
    list[3] = 4;
    list[4] = 5;
    list[5] = 1;
    list[6] = 2;
    list[7] = 3;
    list[8] = 4;
    list[9] = 5;
    final tree = FenwickTree.fromList(list: list);
    expect(tree.query(0), 0);
    expect(tree.query(3), 6);
    expect(tree.query(5), 15);
    expect(tree.query(6), 16);
    expect(tree.query(9), 25);
    expect(tree.query(10), 30);
  });
  test("large FenwickTree", () {
    const size = 10000000;
    final tree = FenwickTree(size: size);
    for (var i = 0; i < size; ++i) {
      tree.update(i, i.toDouble());
    }
    double total = 0;
    for (var i = 0; i < size; ++i) {
      expect(tree.query(i), total);
      total += i;
    }
    tree.update(0, 100);
    total = 0;
    for (var i = 0; i < size; ++i) {
      expect(tree.query(i), total);
      total += i == 0 ? 100 : i;
    }
  });
  test("FenwickTree append matches rebuild", () {
    final random = math.Random(42);
    final values = <double>[];
    final tree = FenwickTree(size: 0);
    for (var i = 0; i < 1000; ++i) {
      final value = random.nextInt(100).toDouble();
      values.add(value);
      tree.append(value);
      expect(tree.size, values.length);
    }
    final reference = FenwickTree.fromList(list: Float64List.fromList(values));
    double total = 0;
    for (var i = 0; i <= values.length; ++i) {
      expect(tree.query(i), reference.query(i));
      expect(tree.query(i), total);
      if (i < values.length) {
        total += values[i];
      }
    }
    for (var offset = 0.0; offset < total; offset += 13.0) {
      expect(tree.inverseQuery(offset), reference.inverseQuery(offset));
    }
  });
  test("FenwickTree truncate, update and re-append", () {
    final random = math.Random(7);
    final values = List.generate(500, (_) => random.nextInt(100).toDouble());
    final tree = FenwickTree.fromList(list: Float64List.fromList(values));

    // Truncate, mutate an element, then grow back with new values.
    tree.truncate(200);
    values.length = 200;
    tree.update(100, 5);
    values[100] += 5;
    for (var i = 0; i < 300; ++i) {
      final value = random.nextInt(100).toDouble();
      values.add(value);
      tree.append(value);
    }

    final reference = FenwickTree.fromList(list: Float64List.fromList(values));
    double total = 0;
    for (var i = 0; i <= values.length; ++i) {
      expect(tree.query(i), reference.query(i));
      expect(tree.query(i), total);
      if (i < values.length) {
        total += values[i];
      }
    }
    for (var offset = 0.0; offset < total; offset += 13.0) {
      expect(tree.inverseQuery(offset), reference.inverseQuery(offset));
    }
  });
  test("large FenwickTree from list", () {
    const size = 10000000;
    final list = Float64List(size);
    for (var i = 0; i < size; ++i) {
      list[i] = i.toDouble();
    }
    final tree = FenwickTree.fromList(list: list);
    double total = 0;
    for (var i = 0; i < size; ++i) {
      expect(tree.query(i), total);
      total += i;
    }
    tree.update(0, 100);
    total = 0;
    for (var i = 0; i < size; ++i) {
      expect(tree.query(i), total);
      total += i == 0 ? 100 : i;
    }
  });

  group("rebuildFrom", () {
    Float64List values(int n, double Function(int) f) =>
        Float64List.fromList([for (var i = 0; i < n; i++) f(i)]);

    test("reuses buffer", () {
      final tree = FenwickTree.fromList(list: values(1000, (i) => 1));
      final buffer = tree.debugBuffer;
      tree.rebuildFrom(values(600, (i) => 2));
      expect(tree.debugBuffer, same(buffer));
      expect(tree.size, 600);
      expect(tree.query(600), 1200);
      expect(tree.inverseQuery(1199), 599);
      tree.append(5);
      expect(tree.query(601), 1205);
    });

    test("trims at quarter capacity", () {
      final tree = FenwickTree.fromList(list: values(1000, (i) => 1));
      final buffer = tree.debugBuffer;
      tree.rebuildFrom(values(249, (i) => 1));
      expect(tree.debugBuffer, isNot(same(buffer)));
      expect(tree.capacity, 249);
      expect(tree.query(249), 249);
    });

    test("grows with a sixteenth of headroom", () {
      final tree = FenwickTree.fromList(list: values(10, (i) => 1));
      tree.rebuildFrom(values(5000, (i) => 3));
      expect(tree.capacity, 5001 + (5001 >> 4) - 1);
      expect(tree.query(5000), 15000);
      final buffer = tree.debugBuffer;
      tree.rebuildFrom(values(5001, (i) => 3));
      expect(tree.debugBuffer, same(buffer));
      expect(tree.query(5001), 15003);
    });

    test("matches fromList bit for bit", () {
      final random = math.Random(7);
      final tree = FenwickTree.fromList(
        list: values(4096, (i) => random.nextDouble() * 1e6),
      );
      for (final n in [4096, 3000, 1025, 1024, 17, 1, 0, 2000]) {
        final list = values(n, (i) => random.nextDouble() * 977.3 - 0.0);
        tree.rebuildFrom(list);
        final reference = FenwickTree.fromList(list: list);
        expect(tree.size, n);
        for (var i = 0; i <= n; i++) {
          expect(tree.debugBuffer[i], reference.debugBuffer[i]);
          expect(tree.query(i), reference.query(i));
        }
        final total = reference.query(n);
        for (var offset = 0.0; offset < total; offset += total / 97) {
          expect(tree.inverseQuery(offset), reference.inverseQuery(offset));
        }
      }
    });
  });
}

import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/src/layout_pass.dart";
import "package:positioned_sliver_list/src/render_object.dart";

class _StubSliver implements RenderSuperSliverList {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      "_StubSliver";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LayoutPass _pass(
  List<RenderSuperSliverList> slivers, {
  RenderSuperSliverList? estimated,
}) => LayoutPass(
  slivers: slivers,
  initialScrollPosition: 0,
  childScrollOffsetEstimation: estimated != null,
  sliverWithOffsetEstimation: estimated,
  maxCorrectionCount: 7,
);

void main() {
  test("first-layout order remains stable on repeated correction passes", () {
    final slivers = List<RenderSuperSliverList>.generate(
      64,
      (_) => _StubSliver(),
    );
    final pass = _pass(slivers);
    final visited = [
      slivers[30],
      slivers[12],
      slivers[60],
      slivers[7],
      slivers[30],
      slivers[7],
    ];
    for (final sliver in visited) {
      pass.recordLaidOutSliver(sliver);
    }
    expect(pass.sliversDuringLayout, [
      slivers[30],
      slivers[12],
      slivers[60],
      slivers[7],
    ]);
    expect(pass.layoutOrderOf(slivers[30]), 0);
    expect(pass.layoutOrderOf(slivers[7]), 3);
    expect(pass.layoutOrderOf(slivers[6]), -1);

    for (final sliver in slivers) {
      expect(
        pass.layoutOrderOf(sliver),
        pass.sliversDuringLayout.indexOf(sliver),
      );
    }
  });

  test("estimated sliver may be pending or already encountered", () {
    final slivers = List<RenderSuperSliverList>.generate(
      4,
      (_) => _StubSliver(),
    );
    final pass = _pass(slivers, estimated: slivers[2]);
    pass.recordLaidOutSliver(slivers[0]);
    pass.recordLaidOutSliver(slivers[1]);
    expect(pass.sliverIsBeforeSliverWithOffsetEstimation(slivers[0]), isTrue);
    expect(pass.sliverIsBeforeSliverWithOffsetEstimation(slivers[1]), isTrue);
    pass.recordLaidOutSliver(slivers[2]);
    expect(pass.sliverIsBeforeSliverWithOffsetEstimation(slivers[0]), isTrue);
    expect(pass.sliverIsBeforeSliverWithOffsetEstimation(slivers[1]), isTrue);
    expect(pass.sliverIsBeforeSliverWithOffsetEstimation(slivers[2]), isFalse);
    pass.recordLaidOutSliver(slivers[3]);
    expect(pass.sliverIsBeforeSliverWithOffsetEstimation(slivers[3]), isFalse);

    final noEstimation = _pass(slivers);
    noEstimation.recordLaidOutSliver(slivers[0]);
    expect(
      noEstimation.sliverIsBeforeSliverWithOffsetEstimation(slivers[0]),
      isFalse,
    );
  });

  test("delayed invalidation selection matches the old linear algorithm", () {
    final slivers = List<RenderSuperSliverList>.generate(
      512,
      (_) => _StubSliver(),
    );
    final pass = _pass(slivers);
    for (var i = 0; i < slivers.length; i += 3) {
      pass.recordLaidOutSliver(slivers[i]);
    }
    for (final current in [slivers[0], slivers[60], slivers[300]]) {
      final originalIndex = pass.sliversDuringLayout.indexOf(current);
      final indexedIndex = pass.layoutOrderOf(current);
      expect(indexedIndex, originalIndex);
      for (final other in slivers) {
        final original = pass.sliversDuringLayout.indexOf(other);
        final viaList = original == -1 || original >= originalIndex;
        final cached = pass.layoutOrderOf(other);
        final viaCache = cached == -1 || cached >= indexedIndex;
        expect(viaCache, viaList);
      }
    }
  });
}

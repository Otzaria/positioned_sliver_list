// Shared widget scenarios for the render-object perf tests.
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

/// Configuration for a scroll scenario.
///
/// Item heights are integer-valued ("heightBase + (index * 7) % heightSpread")
/// which keeps all double arithmetic exact, so different-but-equivalent
/// correction orders produce bit-identical scroll offsets.
class ScrollScenario {
  const ScrollScenario({
    required this.name,
    required this.itemCount,
    required this.cacheExtent,
    required this.step,
    required this.steps,
    this.heightBase = 15,
    this.heightSpread = 30,
  });

  final String name;
  final int itemCount;
  final double cacheExtent;

  /// Scroll delta per pump (absolute forward jump target increment, or
  /// upward step size).
  final double step;
  final int steps;
  final double heightBase;
  final int heightSpread;

  double itemHeightFor(int index) => heightBase + (index * 7) % heightSpread;

  /// Average number of live (visible + cache) children.
  int get approxLiveChildren =>
      ((600 + 2 * cacheExtent) / (heightBase + (heightSpread - 1) / 2)).round();

  @override
  String toString() =>
      "$name (items=$itemCount cache=$cacheExtent ~live=$approxLiveChildren)";
}

Future<ScrollController> _pumpList(
  WidgetTester tester,
  ScrollScenario s,
) async {
  final controller = ScrollController();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SuperListView.builder(
        controller: controller,
        // ignore: deprecated_member_use
        cacheExtent: s.cacheExtent,
        itemCount: s.itemCount,
        itemBuilder: (context, index) =>
            SizedBox(height: s.itemHeightFor(index)),
      ),
    ),
  );
  return controller;
}

Future<double> _teardown(
  WidgetTester tester,
  ScrollController controller,
  double checksum,
) async {
  checksum += controller.position.maxScrollExtent;
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  return checksum;
}

/// Scrolls forward through the list in jumps larger than the cache area, so
/// every pump garbage-collects all children and refills the whole cache via
/// `addTrailingChild` / leading fill. This is the hot path for the
/// `childScrollOffset` membership scan (win 1).
Future<double> runForwardJumpScenario(
  WidgetTester tester,
  ScrollScenario s,
) async {
  final controller = await _pumpList(tester, s);
  var checksum = 0.0;
  for (var i = 1; i <= s.steps; i++) {
    final target =
        (i * s.step).clamp(0.0, controller.position.maxScrollExtent);
    controller.jumpTo(target);
    await tester.pump();
    await tester.pump(); // settle delayed layout / corrections
    checksum += controller.position.pixels;
  }
  return _teardown(tester, controller, checksum);
}

/// Scrolls forward in steps smaller than the cache area, so children are
/// mostly retained and each pump re-runs the main layout loop over a large
/// live-children population (win 5: leading cache-area walk).
Future<double> runForwardStepScenario(
  WidgetTester tester,
  ScrollScenario s,
) async {
  final controller = await _pumpList(tester, s);
  var checksum = 0.0;
  for (var i = 0; i < s.steps; i++) {
    final target = (controller.position.pixels + s.step).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(target);
    await tester.pump();
    await tester.pump();
    checksum += controller.position.pixels;
  }
  return _teardown(tester, controller, checksum);
}

/// Jumps to the bottom of the list and then scrolls upward in steps smaller
/// than the cache area, so each pump inserts a batch of leading children
/// while many live children below them are subject to shifting (win 2).
Future<double> runUpwardScrollScenario(
  WidgetTester tester,
  ScrollScenario s,
) async {
  final controller = await _pumpList(tester, s);
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pump();
  await tester.pump();
  var checksum = 0.0;
  for (var i = 0; i < s.steps; i++) {
    final target = (controller.position.pixels - s.step).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(target);
    await tester.pump();
    await tester.pump(); // settle corrections from newly measured items
    checksum += controller.position.pixels;
  }
  return _teardown(tester, controller, checksum);
}

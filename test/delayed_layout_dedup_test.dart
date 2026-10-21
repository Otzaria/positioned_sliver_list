import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

class _CountingBinding extends AutomatedTestWidgetsFlutterBinding {
  int delayedLayoutCallbacks = 0;

  @override
  void addPostFrameCallback(
    FrameCallback callback, {
    String debugLabel = "callback",
  }) {
    if (StackTrace.current.toString().contains("_markNeedsLayoutDelayed")) {
      delayedLayoutCallbacks++;
    }
    super.addPostFrameCallback(callback, debugLabel: debugLabel);
  }
}

class _Precalculate extends ExtentPrecalculationPolicy {
  @override
  bool shouldPrecalculateExtents(_) => true;
}

class _EightItemsBudget extends SuperSliverListLayoutBudget {
  int _count = 0;

  @override
  void reset() => _count = 0;

  @override
  void beginLayout() {}

  @override
  void endLayout() {}

  @override
  bool shouldLayoutNextItem() => ++_count <= 8;
}

void main() {
  final binding = _CountingBinding();

  testWidgets("one delayed layout pass per sliver and frame", (tester) async {
    final saved = SuperSliverList.layoutBudget;
    SuperSliverList.layoutBudget = _EightItemsBudget();
    addTearDown(() => SuperSliverList.layoutBudget = saved);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final policy = _Precalculate();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          height: 500,
          child: CustomScrollView(
            controller: controller,
            slivers: [
              SuperSliverList.builder(
                extentPrecalculationPolicy: policy,
                extentEstimation: (_, _) => 10,
                itemCount: 2000,
                itemBuilder: (_, index) => const SizedBox(height: 100),
              ),
            ],
          ),
        ),
      ),
    );
    for (final pixels in [3000.0, 9000.0, 15000.0]) {
      binding.delayedLayoutCallbacks = 0;
      controller.jumpTo(pixels);
      await tester.pump();
      expect(binding.delayedLayoutCallbacks, 1, reason: "jump to $pixels");
    }
    expect(RendererBinding.instance, same(binding));
    var frames = 0;
    while (tester.binding.hasScheduledFrame && frames++ < 1000) {
      await tester.pump();
    }
    expect(
      controller.position.maxScrollExtent,
      2000 * 100.0 - controller.position.viewportDimension,
    );
  });
}

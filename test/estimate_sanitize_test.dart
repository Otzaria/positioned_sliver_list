import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_sliver_list.dart";

Widget _list(
  ListController controller, {
  required double width,
  ExtentEstimationProvider? estimate,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: 600,
      child: CustomScrollView(
        slivers: [
          SuperSliverList.builder(
            listController: controller,
            itemCount: 1000,
            extentEstimation:
                estimate ??
                (index, crossAxis) => index == null ? 0 : 40000 / crossAxis,
            itemBuilder: (_, index) => const SizedBox(height: 50),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets("infinite estimate at zero width keeps the total finite", (
    tester,
  ) async {
    final controller = ListController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_list(controller, width: 400));
    await tester.pumpWidget(_list(controller, width: 0));
    expect(tester.takeException(), isArgumentError);
    expect(controller.totalExtent.isFinite, isTrue);
    expect(controller.extentForIndex(900), (100.0, true));
    await tester.pumpWidget(_list(controller, width: 400));
    expect(tester.takeException(), isNull);
    expect(controller.extentForIndex(900), (100.0, true));
  });

  for (final invalid in [double.infinity, double.nan, -5.0]) {
    testWidgets("uniform estimate $invalid falls back per item", (
      tester,
    ) async {
      final controller = ListController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _list(controller, width: 400, estimate: (_, _) => invalid),
      );
      expect(tester.takeException(), isArgumentError);
      expect(controller.totalExtent.isFinite, isTrue);
      expect(controller.extentForIndex(900), (100.0, true));
    });
  }
}

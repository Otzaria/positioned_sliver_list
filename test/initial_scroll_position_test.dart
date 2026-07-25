import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:super_sliver_list/super_sliver_list.dart";

void main() {
  testWidgets(
    "initial end does not overscroll when estimated content is actually short",
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _buildList(controller: controller, itemExtent: 20),
      );

      expect(controller.position.pixels, 0);
      expect(controller.position.maxScrollExtent, 0);
      expect(await tester.pumpAndSettle(), 1);
    },
  );

  testWidgets(
    "initial end still reaches the end when measured content remains long",
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _buildList(controller: controller, itemExtent: 150),
      );

      expect(controller.position.pixels, 600);
      expect(controller.position.maxScrollExtent, 600);
      expect(await tester.pumpAndSettle(), 1);
    },
  );
}

Widget _buildList({
  required ScrollController controller,
  required double itemExtent,
}) {
  return MaterialApp(
    home: SuperListView.builder(
      controller: controller,
      physics: const BouncingScrollPhysics(),
      initialScrollPosition: InitialScrollPosition.end,
      itemCount: 8,
      itemBuilder: (context, index) => SizedBox(height: itemExtent),
    ),
  );
}

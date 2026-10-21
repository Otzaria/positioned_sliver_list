import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:positioned_sliver_list/positioned_list.dart";

int _inits = 0;
int _disposes = 0;

class _Item extends StatefulWidget {
  const _Item(this.index);

  final int index;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  @override
  void initState() {
    super.initState();
    _inits++;
  }

  @override
  void dispose() {
    _disposes++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text("${widget.index} ${"word " * (5 + widget.index % 400)}");
}

double _estimate(int index, double width) {
  final chars = "$index ".length + (5 + index % 400) * 5;
  final perLine = (width / 14).floor().clamp(1, 1000);
  return ((chars + perLine - 1) ~/ perLine) * 14.0;
}

void main() {
  for (final frames in [1, 18]) {
    testWidgets("width 1400 -> 1050 in $frames frames builds only the "
        "cache-area difference", (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _inits = _disposes = 0;
      final controller = ItemScrollController();
      var estimates = 0;
      var width = 1400.0;
      late StateSetter setWidth;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, set) {
                setWidth = set;
                return SizedBox(
                  width: width,
                  height: 900,
                  child: ScrollablePositionedList.builder(
                    itemScrollController: controller,
                    itemCount: 190000,
                    cacheExtentScreens: 1.5,
                    estimateExtent: (index, width) {
                      estimates++;
                      return _estimate(index, width);
                    },
                    itemBuilder: (_, index) => _Item(index),
                  ),
                );
              },
            ),
          ),
        ),
      );
      controller.jumpTo(index: 95000, offset: -5);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      final live = _inits - _disposes;
      final anchor = controller.anchor!;
      var created = 0;
      var disposed = 0;
      var estimatesDuringAnimation = 0;
      for (var frame = 1; frame <= frames; frame++) {
        _inits = _disposes = 0;
        final before = estimates;
        setWidth(() => width = 1400 - 350 * frame / frames);
        await tester.pump(const Duration(milliseconds: 16));
        created += _inits;
        disposed += _disposes;
        estimatesDuringAnimation += estimates - before;
      }
      // Wider items push cache items out; a frame never rebuilds them all.
      expect(created, lessThan(live ~/ 2));
      expect(disposed, lessThan(live));
      expect(estimatesDuringAnimation, 0);
      expect(controller.anchor!.index, anchor.index);
      _inits = _disposes = 0;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect((_inits, _disposes), (0, 0));
      expect(estimates, greaterThan(180000));
    });
  }
}

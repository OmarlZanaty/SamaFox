import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/widgets/app_scale.dart';

/// A phone with a large display size (~320 dp) and a large font must get the
/// same 360 dp layout as everyone else, just drawn smaller (19/10).
void main() {
  Future<Map<String, Object?>> pumpAt(WidgetTester tester, Size logical, {VoidCallback? onTap}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = logical * 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final seen = <String, Object?>{};
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppScale(child: child!),
      home: Builder(builder: (context) {
        seen['width'] = MediaQuery.sizeOf(context).width;
        seen['scaler'] = MediaQuery.textScalerOf(context);
        return Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Row(
              children: [
                const SizedBox(width: 300, height: 40),
                SizedBox(
                  width: 50,
                  height: 40,
                  child: GestureDetector(
                    key: const Key('edge'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ));
    return seen;
  }

  testWidgets('a 320 dp phone with a big font gets the 360 dp layout, scaled', (tester) async {
    var taps = 0;
    final seen = await pumpAt(tester, const Size(320, 700), onTap: () => taps++);

    expect(seen['width'], 360);
    expect(seen['scaler'], TextScaler.noScaling);
    expect(tester.takeException(), isNull); // 350 dp row: no overflow

    // The button sits at 300–350 of the 360 dp layout; on screen that is
    // 300–350 × 320/360. Tapping its centre must reach it.
    await tester.tapAt(const Offset(325 * 320 / 360, 20 * 320 / 360));
    expect(taps, 1);
  });

  testWidgets('a wide phone keeps its own width, still without font scaling', (tester) async {
    final seen = await pumpAt(tester, const Size(411, 800));
    expect(seen['width'], 411);
    expect(seen['scaler'], TextScaler.noScaling);
  });
}

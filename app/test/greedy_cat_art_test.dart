import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/screens/games/greedy_cat_art.dart';

/// Renders every piece of القط الجشع artwork to a PNG contact sheet.
///
/// The art is drawn in code rather than shipped as bitmaps, which means nobody
/// sees it until it runs. This test exists so it can be looked at: run
///
///     flutter test test/greedy_cat_art_test.dart
///
/// and open `build/greedy_cat_contact_sheet.png`. It also fails outright if a
/// painter throws, so a broken Path never reaches the screen.
///
/// Note the labels render as boxes — the test harness has no Arabic font — and
/// that is fine. This sheet is for checking shapes, colour and geometry.
void main() {
  const symbols = [
    'chicken', 'tomato', 'goat', 'pepper',
    'fish', 'carrot', 'shrimp', 'corn',
  ];

  testWidgets('every painter renders, and a contact sheet is written',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Container(
            width: 900,
            height: 1180,
            color: const Color(0xFF20BCEB),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: const BackgroundPatternPainter(drift: 0.2),
                  ),
                ),
                Column(
                  children: [
                    // Row 1 — the eight foods.
                    SizedBox(
                      height: 130,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final s in symbols)
                            Container(
                              width: 96,
                              height: 96,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: GreedyPalette.cream,
                              ),
                              child: Center(child: FoodIcon(s, size: 78)),
                            ),
                        ],
                      ),
                    ),
                    // Row 2 — the mascot in each mood, plus the UI furniture.
                    SizedBox(
                      height: 190,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final mood in CatMood.values)
                            SizedBox(
                              width: 150,
                              height: 170,
                              child: CustomPaint(
                                painter: CatMascotPainter(
                                  mood: mood,
                                  breath: 0.25,
                                  blink: mood == CatMood.lose ? 0.0 : 0.0,
                                ),
                              ),
                            ),
                          const SizedBox(
                              width: 90, height: 90, child: CoinEmblem(size: 90)),
                          const TreasureChest(size: 90),
                          const TreasureChest(size: 90, opened: false, locked: true),
                        ],
                      ),
                    ),
                    // Row 3 — the whole wheel scene, mid-spin.
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: 620,
                          height: 620,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: const WheelFramePainter(
                                    count: 8,
                                    cardRadius: 205,
                                    hubRadius: 93,
                                    glow: 0.3,
                                    rotation: 0.02,
                                    winningIndex: 0,
                                    winnerPulse: 0.8,
                                  ),
                                ),
                              ),
                              for (var i = 0; i < symbols.length; i++)
                                _card(symbols[i], i, 620, 205, 127),
                              const SizedBox(
                                width: 182,
                                height: 182,
                                child: CustomPaint(
                                  painter: CatMascotPainter(
                                    mood: CatMood.idle,
                                    breath: 0.25,
                                    blink: 0,
                                  ),
                                ),
                              ),
                              const Positioned(
                                top: 41,
                                child: SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: CustomPaint(
                                      painter: PointerPainter(pulse: 0.4)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('build/greedy_cat_contact_sheet.png');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });

    expect(tester.takeException(), isNull);
  });

  // Generates the games-hub banner from the same painters the game uses, so the
  // card can never drift from the artwork on the screen it opens.
  //
  // This writes into `assets/`, which is unusual for a test — it is the image
  // equivalent of assets/sounds/generate_greedy_sounds.py: generated rather than
  // sourced, so it stays original, reproducible and in the house style. Without
  // it the hub falls back to a gradient and a 🐱 emoji.
  testWidgets('generates the hub card banner', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 1200,
            height: 600,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: const BackgroundPatternPainter(drift: 0.4),
                  ),
                ),
                // The wheel sits to the right so the left third stays calm for
                // the title the hub draws over it.
                Positioned(
                  right: -20,
                  top: -25,
                  width: 640,
                  height: 640,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: const WheelFramePainter(
                            count: 8,
                            cardRadius: 211,
                            hubRadius: 96,
                            glow: 0.3,
                            winningIndex: 0,
                            winnerPulse: 0.9,
                          ),
                        ),
                      ),
                      for (var i = 0; i < symbols.length; i++)
                        _card(symbols[i], i, 640, 211, 131),
                      const SizedBox(
                        width: 187,
                        height: 187,
                        child: CustomPaint(
                          painter: CatMascotPainter(
                            mood: CatMood.win,
                            breath: 0.25,
                            blink: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // A few coins scattered into the calm left third.
                const Positioned(left: 70, top: 120, child: CoinEmblem(size: 74)),
                const Positioned(left: 176, top: 250, child: CoinEmblem(size: 52)),
                const Positioned(left: 56, top: 356, child: CoinEmblem(size: 40)),
                const Positioned(left: 236, top: 96, child: TreasureChest(size: 84)),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('assets/images/cards/card_greedy.png');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });

    expect(tester.takeException(), isNull);
    expect(File('assets/images/cards/card_greedy.png').existsSync(), isTrue);
  });
}


Widget _card(String symbol, int i, double side, double radius, double size) {
  final angle = WheelFramePainter.angleFor(i, 8, 0.02);
  return Positioned(
    left: side / 2 + radius * _cos(angle) - size / 2,
    top: side / 2 + radius * _sin(angle) - size / 2,
    width: size,
    height: size,
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GreedyPalette.cream,
        border: Border.all(color: GreedyPalette.woodOutline, width: 5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: GreedyPalette.warmPale,
            border: Border.all(color: GreedyPalette.woodHighlight, width: 4),
          ),
          child: Center(child: FoodIcon(symbol, size: size * 0.5)),
        ),
      ),
    ),
  );
}

double _cos(double a) => math.cos(a);
double _sin(double a) => math.sin(a);

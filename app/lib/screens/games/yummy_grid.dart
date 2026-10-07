import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'yummy_engine.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

class YummyGrid extends StatelessWidget {
  final List<String> grid;
  final List<YummyLineWin> wins;
  final YummyStrings strings;
  final double pulse;
  final bool spinning;
  const YummyGrid({
    super.key,
    required this.grid,
    required this.wins,
    required this.strings,
    this.pulse = 0,
    this.spinning = false,
  });
  @override
  Widget build(BuildContext context) {
    final winning = wins.expand((win) => win.cells).toSet();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF5AF), yummyGold, Color(0xFFFF9A25)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66043180),
              blurRadius: 18,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: AspectRatio(
          aspectRatio: 5 / 3,
          child: LayoutBuilder(
            builder: (context, constraints) => ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: Stack(
                children: [
                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                    ),
                    itemCount: 15,
                    itemBuilder: (context, index) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: winning.contains(index)
                            ? Color.lerp(
                                const Color(0xFFFFF8DC),
                                yummyGold,
                                .15 + pulse * .35,
                              )
                            : const Color(0xFFFFF8DC),
                        border: Border.all(
                          color: const Color(0xFFE7DDBF),
                          width: .7,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: spinning ? 0.7 : 1,
                            child: YummySymbol(
                              grid[index],
                              strings: strings,
                              size: constraints.maxWidth / 5 - 8,
                            ),
                          ),
                          if (winning.contains(index))
                            const Positioned(
                              right: 3,
                              top: 3,
                              child: Icon(
                                Icons.star,
                                size: 14,
                                color: yummyDeep,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _LinesPainter(wins, pulse),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  final List<YummyLineWin> wins;
  final double pulse;
  _LinesPainter(this.wins, this.pulse);
  static const colors = [
    Color(0xFFE72965),
    Color(0xFF0753BD),
    Color(0xFF5D249B),
    Color(0xFF007860),
    Color(0xFFB04A00),
    Color(0xFFB5119C),
    Color(0xFF153793),
    Color(0xFF337100),
    Color(0xFFAD2935),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    for (final win in wins) {
      final path = Path();
      for (var reel = 0; reel < 5; reel++) {
        final point = Offset(
          (reel + .5) * size.width / 5,
          (yummyPaylines[win.line][reel] + .5) * size.height / 3,
        );
        if (reel == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[win.line]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + math.min(pulse, 1),
      );
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) =>
      old.wins != wins || old.pulse != pulse;
}

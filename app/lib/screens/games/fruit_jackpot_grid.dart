import 'dart:ui';
import 'package:flutter/material.dart';
import 'fruit_jackpot_engine.dart';
import 'fruit_jackpot_symbols.dart';

class FruitJackpotGrid extends StatelessWidget {
  final List<String> grid;
  final FruitJackpotRound? round;
  final int revealed;
  final bool motion, arabic;
  const FruitJackpotGrid({
    super.key,
    required this.grid,
    this.round,
    required this.revealed,
    required this.motion,
    required this.arabic,
  });
  @override
  Widget build(BuildContext context) {
    final won = round?.wins.expand((w) => w.cells).toSet() ?? <int>{};
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AspectRatio(
        aspectRatio: 1.08,
        child: Stack(
          children: [
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: 9,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.08,
              ),
              itemBuilder: (context, i) {
                final spinning = i >= revealed;
                return TweenAnimationBuilder<double>(
                  key: ValueKey('$i:$spinning'),
                  tween: Tween(begin: spinning ? 0 : .82, end: 1),
                  duration: Duration(milliseconds: motion ? 360 : 0),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) => Transform.scale(
                    scale: spinning ? 1 : scale,
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: motion ? 250 : 0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: i == 4
                            ? const [Color(0xff9a2037), Color(0xff420d23)]
                            : const [Color(0xff304953), Color(0xff17162e)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: !spinning && won.contains(i)
                            ? const Color(0xff46d9ff)
                            : const Color(0xff9065ad),
                        width: 2,
                      ),
                      boxShadow: [
                        if (!spinning && won.contains(i))
                          const BoxShadow(
                            color: Color(0xff46d9ff),
                            blurRadius: 10,
                          ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaY: spinning && motion ? 5 : 0,
                              sigmaX: 0,
                            ),
                            child: fruitJackpotArt(grid[i], label: grid[i]),
                          ),
                        ),
                        // On 320 px phones a cell is ~48 px tall: the counter
                        // and label shrink to fit rather than overflow.
                        if (i == 4)
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                spinning
                                    ? '--'
                                    : '${round?.centreMultiplier ?? 1}'
                                        .padLeft(2, '0'),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  color: Color(0xffffac35),
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              grid[i] == 'multiplier'
                                  ? 'BONUS'
                                  : '${fruitJackpotPaytable[grid[i]]} ${arabic ? 'مرات' : 'times'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xfffff6db),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (revealed == 9 && won.isNotEmpty)
              IgnorePointer(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _Lines(round!.wins.map((w) => w.cells).toList()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Lines extends CustomPainter {
  final List<List<int>> lines;
  _Lines(this.lines);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x9946d9ff)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    Offset point(int c) => Offset(
          8 + (size.width - 16) / 3 * (c % 3 + .5),
          8 + (size.height - 16) / 3 * (c ~/ 3 + .5),
        );
    for (final line in lines) {
      canvas.drawLine(point(line.first), point(line.last), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Lines oldDelegate) =>
      oldDelegate.lines != lines;
}

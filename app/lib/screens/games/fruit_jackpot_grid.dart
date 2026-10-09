import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'fruit_jackpot_engine.dart';
import 'fruit_jackpot_symbols.dart';

/// The 3×3 reels. A cell still waiting for its result rolls through the
/// symbols under motion blur; when the server's symbol arrives it lands with a
/// bounce. Winning cells glow and the winning lines are drawn across them.
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
    final done = revealed == 9;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AspectRatio(
        aspectRatio: 1.08,
        child: Stack(
          children: [
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(6),
              itemCount: 9,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1.08,
              ),
              itemBuilder: (context, i) {
                final spinning = i >= revealed;
                final winner = !spinning && won.contains(i);
                final dim = done && won.isNotEmpty && !winner;
                return AnimatedOpacity(
                  duration: Duration(milliseconds: motion ? 250 : 0),
                  opacity: dim ? .55 : 1,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: motion ? 250 : 0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: i == 4
                            ? const [
                                Color(0xffc23a5c),
                                Color(0xff7d1238),
                                Color(0xff3e0720),
                              ]
                            : const [
                                Color(0xff7b48c4),
                                Color(0xff4a1f86),
                                Color(0xff26104c),
                              ],
                      ),
                      border: Border.all(
                        color: winner
                            ? const Color(0xff7ff3ff)
                            : const Color(0xccffd52b),
                        width: winner ? 2.5 : 1.5,
                      ),
                      boxShadow: [
                        if (winner)
                          const BoxShadow(
                            color: Color(0xcc46d9ff),
                            blurRadius: 14,
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Glass highlight on the upper half of the tile.
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: 26,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x44ffffff),
                                    Color(0x00ffffff),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: spinning && motion
                                ? _Rolling(seed: i)
                                : TweenAnimationBuilder<double>(
                                    key: ValueKey('$i:${grid[i]}:$spinning'),
                                    tween:
                                        Tween(begin: motion ? .6 : 1, end: 1),
                                    duration: Duration(
                                      milliseconds: motion ? 420 : 0,
                                    ),
                                    curve: Curves.elasticOut,
                                    builder: (_, s, child) => Transform.scale(
                                      scale: winner ? s * 1.06 : s,
                                      child: child,
                                    ),
                                    child: fruitJackpotArt(
                                      grid[i],
                                      label: grid[i],
                                    ),
                                  ),
                          ),
                          if (i == 4)
                            Positioned(
                              right: 4,
                              bottom: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xcc1a0410),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xffffac35),
                                  ),
                                ),
                                child: Text(
                                  spinning
                                      ? '--'
                                      : '×${round?.centreMultiplier ?? 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: Color(0xffffac35),
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (done && won.isNotEmpty)
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

/// A cell still spinning: symbols roll past under vertical motion blur.
class _Rolling extends StatefulWidget {
  final int seed;
  const _Rolling({required this.seed});
  @override
  State<_Rolling> createState() => _RollingState();
}

class _RollingState extends State<_Rolling> {
  late int _index = widget.seed * 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (mounted) setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = fruitJackpotSymbolIds[_index % fruitJackpotSymbolIds.length];
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaY: 6),
      child: Transform.translate(
        offset: Offset(0, (_index.isEven ? -1 : 1) * 6),
        child: fruitJackpotArt(symbol, label: symbol),
      ),
    );
  }
}

class _Lines extends CustomPainter {
  final List<List<int>> lines;
  _Lines(this.lines);
  @override
  void paint(Canvas canvas, Size size) {
    Offset point(int c) => Offset(
          6 + (size.width - 12) / 3 * (c % 3 + .5),
          6 + (size.height - 12) / 3 * (c ~/ 3 + .5),
        );
    for (final line in lines) {
      final a = point(line.first), b = point(line.last);
      // A soft glow under a bright core.
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0x6646d9ff)
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xffbff8ff)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Lines oldDelegate) =>
      oldDelegate.lines != lines;
}

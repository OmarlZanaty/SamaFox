import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'yummy_engine.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

/// The 5×3 machine: a gold cabinet with chasing bulbs, reels that blur while
/// they spin and bounce as they land, and glowing win lines that draw in.
///
/// [revealedReels] counts reels (left to right) that already show the server
/// result while [spinning]; the rest are still blurring. [spinId] changes once
/// per round so landing bounces and the line draw-in replay every time.
/// [ambient] is a 0..1 loop for the bulbs; [pulse] a 0..1 ping-pong for wins.
class YummyGrid extends StatelessWidget {
  final List<String> grid;
  final List<YummyLineWin> wins;
  final YummyStrings strings;
  final double pulse;
  final double ambient;
  final bool spinning;
  final int revealedReels;
  final int spinId;
  const YummyGrid({
    super.key,
    required this.grid,
    required this.wins,
    required this.strings,
    this.pulse = 0,
    this.ambient = 0,
    this.spinning = false,
    this.revealedReels = 5,
    this.spinId = 0,
  });

  @override
  Widget build(BuildContext context) {
    final winning = wins.expand((win) => win.cells).toSet();
    final dim = !spinning && winning.isNotEmpty;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        foregroundPainter: _BulbsPainter(ambient),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF6B8),
                yummyGold,
                Color(0xFFFFA726),
                Color(0xFFE67A00),
              ],
              stops: [0, .35, .75, 1],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x88043180),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
              BoxShadow(
                color: Color(0x55FFE57A),
                blurRadius: 30,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A2A6B), Color(0xFF1176DC)],
              ),
            ),
            child: AspectRatio(
              aspectRatio: 5 / 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cell = constraints.maxWidth / 5;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFFFDF2),
                                  Color(0xFFFFF3CF),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var reel = 0; reel < 5; reel++)
                              Expanded(
                                child: _Reel(
                                  key: ValueKey('reel-$spinId-$reel'),
                                  symbols: [
                                    for (var row = 0; row < 3; row++)
                                      grid[row * 5 + reel],
                                  ],
                                  indexes: [
                                    for (var row = 0; row < 3; row++)
                                      row * 5 + reel,
                                  ],
                                  blurred: spinning && reel >= revealedReels,
                                  landed: !spinning || reel < revealedReels,
                                  winning: winning,
                                  dim: dim,
                                  pulse: pulse,
                                  size: cell,
                                  strings: strings,
                                  divider: reel < 4,
                                ),
                              ),
                          ],
                        ),
                        // Top and bottom shading sells the curved drum.
                        const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x33000000),
                                  Color(0x00000000),
                                  Color(0x00000000),
                                  Color(0x2A000000),
                                ],
                                stops: [0, .16, .84, 1],
                              ),
                            ),
                            child: SizedBox.expand(),
                          ),
                        ),
                        if (!spinning && wins.isNotEmpty)
                          IgnorePointer(
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey('lines-$spinId'),
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              builder: (context, progress, _) => CustomPaint(
                                size: Size.infinite,
                                painter: _LinesPainter(wins, pulse, progress),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Reel extends StatelessWidget {
  final List<String> symbols;
  final List<int> indexes;
  final bool blurred, landed, dim, divider;
  final Set<int> winning;
  final double pulse, size;
  final YummyStrings strings;
  const _Reel({
    super.key,
    required this.symbols,
    required this.indexes,
    required this.blurred,
    required this.landed,
    required this.winning,
    required this.dim,
    required this.pulse,
    required this.size,
    required this.strings,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    Widget column = Column(
      children: [
        for (var row = 0; row < 3; row++)
          Expanded(
            child: _Cell(
              symbol: symbols[row],
              win: winning.contains(indexes[row]),
              dim: dim && !winning.contains(indexes[row]),
              pulse: pulse,
              size: size,
              strings: strings,
            ),
          ),
      ],
    );
    if (blurred) {
      column = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaY: 7, tileMode: TileMode.decal),
        child: column,
      );
    } else if (landed) {
      // A short overshoot as the reel locks in.
      column = TweenAnimationBuilder<double>(
        tween: Tween(begin: -.16, end: 0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        builder: (context, shift, child) => FractionalTranslation(
          translation: Offset(0, shift / 3),
          child: child,
        ),
        child: column,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider
            ? const Border(
                right: BorderSide(color: Color(0xFFE9D9A8), width: 1),
              )
            : null,
      ),
      child: column,
    );
  }
}

class _Cell extends StatelessWidget {
  final String symbol;
  final bool win, dim;
  final double pulse, size;
  final YummyStrings strings;
  const _Cell({
    required this.symbol,
    required this.win,
    required this.dim,
    required this.pulse,
    required this.size,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          if (win)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: RadialGradient(
                      colors: [
                        Colors.white,
                        Color.lerp(
                          const Color(0xFFFFE880),
                          yummyGold,
                          pulse,
                        )!,
                      ],
                    ),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFB300)
                            .withValues(alpha: .55 + pulse * .4),
                        blurRadius: 10 + pulse * 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: dim ? .45 : 1,
            child: Transform.scale(
              scale: win ? 1.02 + pulse * .1 : 1,
              child: YummySymbol(symbol, strings: strings, size: size - 10),
            ),
          ),
          if (win)
            // A shape badge too, so a win never relies on colour alone.
            const Positioned(
              right: 4,
              top: 4,
              child: CircleAvatar(
                radius: 8,
                backgroundColor: yummyDeep,
                child: Icon(Icons.star, size: 11, color: yummyGold),
              ),
            ),
        ],
      );
}

/// Bulbs around the cabinet. Every third bulb is lit, and the pattern chases.
class _BulbsPainter extends CustomPainter {
  final double phase;
  _BulbsPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 6.5;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    ).deflate(inset);
    final metric = (Path()..addRRect(rect)).computeMetrics().first;
    final count = (metric.length / 22).floor();
    final shift = (phase * 3).floor() % 3;
    for (var i = 0; i < count; i++) {
      final at = metric.getTangentForOffset(metric.length * i / count)!;
      final lit = (i + shift) % 3 == 0;
      if (lit) {
        canvas.drawCircle(
          at.position,
          5.5,
          Paint()
            ..color = const Color(0xCCFFFFFF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(
        at.position,
        2.6,
        Paint()..color = lit ? Colors.white : const Color(0xFFB8620A),
      );
    }
  }

  @override
  bool shouldRepaint(_BulbsPainter old) =>
      (old.phase * 3).floor() != (phase * 3).floor();
}

class _LinesPainter extends CustomPainter {
  final List<YummyLineWin> wins;
  final double pulse, progress;
  _LinesPainter(this.wins, this.pulse, this.progress);
  static const colors = [
    Color(0xFFFF2D6F),
    Color(0xFF1E7BFF),
    Color(0xFF9B4DFF),
    Color(0xFF00B386),
    Color(0xFFFF7A00),
    Color(0xFFE81FC6),
    Color(0xFF2E55D9),
    Color(0xFF55B800),
    Color(0xFFE5373F),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final win in wins) {
      final full = Path();
      for (var reel = 0; reel < 5; reel++) {
        final point = Offset(
          (reel + .5) * size.width / 5,
          (yummyPaylines[win.line][reel] + .5) * size.height / 3,
        );
        reel == 0
            ? full.moveTo(point.dx, point.dy)
            : full.lineTo(point.dx, point.dy);
      }
      final path = Path();
      for (final metric in full.computeMetrics()) {
        path.addPath(
          metric.extractPath(0, metric.length * progress),
          Offset.zero,
        );
      }
      final color = colors[win.line % colors.length];
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4 + math.min(pulse, 1) * 1.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) =>
      old.wins != wins || old.pulse != pulse || old.progress != progress;
}

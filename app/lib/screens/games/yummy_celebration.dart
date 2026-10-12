import 'dart:async';
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'yummy_fx.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

enum YummyWinTier { none, big, mega, jackpot }

/// Big wins are measured against the whole stake, not the line bet.
YummyWinTier yummyWinTier(int prize, int totalBet, bool jackpot) {
  if (jackpot) return YummyWinTier.jackpot;
  if (totalBet <= 0) return YummyWinTier.none;
  if (prize >= totalBet * 30) return YummyWinTier.mega;
  if (prize >= totalBet * 10) return YummyWinTier.big;
  return YummyWinTier.none;
}

/// Full-screen celebration: confetti, a title that pops in and the prize
/// counting up. Tapping anywhere, or a few seconds passing, dismisses it.
class YummyCelebration extends StatefulWidget {
  final YummyWinTier tier;
  final int prize;
  final YummyStrings strings;
  final bool reduced, lite;
  final VoidCallback onDone;
  const YummyCelebration({
    super.key,
    required this.tier,
    required this.prize,
    required this.strings,
    required this.onDone,
    this.reduced = false,
    this.lite = false,
  });

  @override
  State<YummyCelebration> createState() => _YummyCelebrationState();
}

class _YummyCelebrationState extends State<YummyCelebration> {
  Timer? _timer;
  late final ConfettiController _confetti = ConfettiController(
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduced) _confetti.play();
    _timer = Timer(
      Duration(
        milliseconds: widget.tier == YummyWinTier.jackpot ? 5000 : 3600,
      ),
      () {
        if (mounted) widget.onDone();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  String get _title => switch (widget.tier) {
        YummyWinTier.jackpot => widget.strings.text('jackpot'),
        YummyWinTier.mega => widget.strings.text('megaWin'),
        _ => widget.strings.text('bigWin'),
      };

  @override
  Widget build(BuildContext context) {
    final jackpot = widget.tier == YummyWinTier.jackpot;
    final countUp = Duration(milliseconds: widget.reduced ? 1 : 1800);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDone,
      child: Semantics(
        liveRegion: true,
        label: '$_title ${widget.prize}',
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      (jackpot ? const Color(0xFF5B1A8C) : yummyDeep)
                          .withValues(alpha: .82),
                      const Color(0xE6050B24),
                    ],
                  ),
                ),
              ),
            ),
            if (!widget.reduced && !widget.lite)
              const Positioned.fill(child: _Rays()),
            if (!widget.reduced)
              Positioned.fill(
                child: YummyCoinRain(
                  seconds: jackpot ? 4 : 2.6,
                  perSecond: jackpot ? 36 : 24,
                  lite: widget.lite,
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confetti,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: .06,
                numberOfParticles: jackpot ? 40 : 24,
                gravity: .25,
                colors: const [
                  yummyGold,
                  Color(0xFFFF4B86),
                  Color(0xFF08B9F2),
                  Colors.white,
                  Color(0xFFFF9A25),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: widget.reduced ? 1 : .3, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.elasticOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (jackpot)
                    YummySymbol(
                      'jackpot',
                      strings: widget.strings,
                      size: 150,
                    ),
                  _OutlinedText(
                    _title,
                    size: jackpot ? 52 : 58,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: yummyGold, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.toll, color: yummyGold, size: 34),
                        const SizedBox(width: 10),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: widget.prize.toDouble()),
                          duration: countUp,
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => Text(
                            '${value.round()}',
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    widget.strings.text('tapToContinue'),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedText extends StatelessWidget {
  final String text;
  final double size;
  const _OutlinedText(this.text, {required this.size});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
    );
    return Stack(
      children: [
        Text(
          text,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 9
              ..color = const Color(0xFF0A2A6B),
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFBD0), yummyGold, Color(0xFFFF9A25)],
          ).createShader(bounds),
          child: Text(
            text,
            style: base.copyWith(
              color: Colors.white,
              shadows: const [Shadow(color: Color(0x66000000), blurRadius: 12)],
            ),
          ),
        ),
      ],
    );
  }
}

/// Slowly turning sun rays behind the title.
class _Rays extends StatefulWidget {
  const _Rays();
  @override
  State<_Rays> createState() => _RaysState();
}

class _RaysState extends State<_Rays> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _spin,
        builder: (context, _) =>
            CustomPaint(painter: _RaysPainter(_spin.value)),
      );
}

class _RaysPainter extends CustomPainter {
  final double turn;
  _RaysPainter(this.turn);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.longestSide;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          yummyGold.withValues(alpha: .35),
          yummyGold.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * .6));
    const rays = 14;
    for (var i = 0; i < rays; i++) {
      final a = turn * 2 * pi + i * 2 * pi / rays;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + cos(a - .09) * radius,
          center.dy + sin(a - .09) * radius,
        )
        ..lineTo(
          center.dx + cos(a + .09) * radius,
          center.dy + sin(a + .09) * radius,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.turn != turn;
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'olympus_strings.dart';
import 'olympus_symbols.dart';

const Map<String, Color> kOlympusTierColors = {
  'NICE_WIN': Color(0xFF6FE0A8),
  'BIG_WIN': Color(0xFFFFD24A),
  'MEGA_WIN': Color(0xFFFFB020),
  'EPIC_WIN': Color(0xFFFF7A3D),
};

/// The full-screen win celebration.
///
/// Recreates the presentation the brief asks for: large gold lettering, a green
/// radial burst behind it, coins and sparks flying toward the viewer, a golden
/// horn on each side, and a win counter that races up to the real total.
///
/// Two rules it must never break, both from the acceptance criteria: the amount
/// stays readable the whole time, and the player can skip. Skip is available
/// after 500 ms — long enough that it is not dismissed by the tap that started
/// the spin, short enough that it never feels like a wall.
class OlympusCelebration extends StatefulWidget {
  const OlympusCelebration({
    super.key,
    required this.tier,
    required this.amount,
    required this.bet,
    required this.strings,
    required this.onDone,
    this.capped = false,
    this.reducedMotion = false,
    this.art,
  });

  final String tier;
  final int amount;
  final int bet;
  final OlympusStrings strings;
  final VoidCallback onDone;

  /// Set when the round hit the 5,000× ceiling, so the overlay can say so
  /// rather than quietly showing a number smaller than the math produced.
  final bool capped;
  final bool reducedMotion;
  final OlympusArt? art;

  @override
  State<OlympusCelebration> createState() => _OlympusCelebrationState();
}

class _OlympusCelebrationState extends State<OlympusCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 400 : _countMs),
  )..forward();

  late final AnimationController _particles = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 150 : 520),
  )..forward();

  bool _canSkip = false;

  /// Bigger wins count for longer — an EPIC_WIN that finished in 400 ms would
  /// throw away the whole point of the counter.
  int get _countMs => switch (widget.tier) {
        'EPIC_WIN' => 3000,
        'MEGA_WIN' => 2300,
        'BIG_WIN' => 1700,
        _ => 1100,
      };

  @override
  void initState() {
    super.initState();
    if (!widget.reducedMotion) _particles.repeat();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _canSkip = true);
    });
  }

  @override
  void dispose() {
    _count.dispose();
    _particles.dispose();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final color = kOlympusTierColors[widget.tier] ?? const Color(0xFFFFD24A);
    final ratio = widget.bet > 0 ? widget.amount / widget.bet : 0;

    return Semantics(
      liveRegion: true,
      label: '${s.tier(widget.tier)} ${widget.amount}',
      child: GestureDetector(
        onTap: _canSkip ? widget.onDone : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!widget.reducedMotion)
                AnimatedBuilder(
                  animation: _particles,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _BurstPainter(
                      t: _particles.value,
                      accent: color,
                      coin: widget.art?.forFx('fx_coin'),
                      spark: widget.art?.forFx('fx_particle_spark'),
                      burst: widget.art?.forFx('fx_burst_green'),
                    ),
                  ),
                ),

              // Horns, aimed inward from the sides.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _HornPainter(art: widget.art?.forFx('fx_trumpet')),
                  ),
                ),
              ),

              ScaleTransition(
                scale: Tween(begin: 0.6, end: 1.0).animate(
                  CurvedAnimation(parent: _entry, curve: Curves.elasticOut),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _title(s.tier(widget.tier), color),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: _count,
                      builder: (context, _) {
                        final shown = (widget.amount *
                                Curves.easeOutCubic.transform(_count.value))
                            .round();
                        return Text(
                          '$shown',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 2)),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '×${ratio.toStringAsFixed(ratio >= 10 ? 0 : 1)} ${s.totalBet}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    if (widget.capped) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          s.cappedNotice,
                          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (_canSkip)
                Positioned(
                  bottom: 32,
                  child: TextButton(
                    onPressed: widget.onDone,
                    child: Text(
                      s.skip,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Gold 3D-ish lettering: a dark extruded copy behind a gold-gradient face.
  Widget _title(String text, Color color) {
    final style = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
      height: 1.1,
      foreground: Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(0, 46),
          [const Color(0xFFFFF3B0), color, const Color(0xFF9A6B12)],
          const [0.0, 0.5, 1.0],
        ),
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            height: 1.1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..color = const Color(0xFF2B1206),
          ),
        ),
        Text(text, textAlign: TextAlign.center, style: style),
      ],
    );
  }
}

/// The green radial burst, plus coins and sparks blown toward the viewer.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.t,
    required this.accent,
    this.coin,
    this.spark,
    this.burst,
  });

  final double t;
  final Color accent;
  final ui.Image? coin, spark, burst;

  void _blit(Canvas canvas, ui.Image img, Offset pos, double size, double opacity) {
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: pos, width: size, height: size * img.height / img.width),
      Paint()
        ..blendMode = BlendMode.plus
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.44);

    // Emerald radial burst behind everything.
    if (burst != null) {
      _blit(canvas, burst!, center, size.shortestSide * 1.6, 0.65);
    } else {
      canvas.drawCircle(
        center,
        size.shortestSide * 0.62,
        Paint()
          ..shader = ui.Gradient.radial(center, size.shortestSide * 0.62, [
            const Color(0x5527C07A),
            const Color(0x1127C07A),
            const Color(0x0027C07A),
          ], const [0.0, 0.55, 1.0],),
      );
    }

    // Rotating god-rays.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * math.pi * 0.35);
    final ray = Paint()..color = accent.withValues(alpha: 0.10);
    for (var i = 0; i < 16; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.shortestSide * 0.9, -size.shortestSide * 0.045)
          ..lineTo(size.shortestSide * 0.9, size.shortestSide * 0.045)
          ..close(),
        ray,
      );
      canvas.rotate(math.pi * 2 / 16);
    }
    canvas.restore();

    // Coins and sparks, thrown outward and toward the viewer.
    final rnd = math.Random(19);
    for (var i = 0; i < 34; i++) {
      final angle = rnd.nextDouble() * math.pi * 2;
      final speed = 70 + rnd.nextDouble() * 190;
      final phase = (t + i / 34) % 1.0;
      final r = phase * speed * 2.1;
      final pos = center +
          Offset(math.cos(angle) * r, math.sin(angle) * r * 0.62 - phase * 46);
      final opacity = (1 - phase).clamp(0.0, 1.0);
      final scale = 0.7 + phase * 1.1;

      final useCoin = i % 3 != 0;
      final img = useCoin ? coin : spark;
      if (img != null) {
        _blit(canvas, img, pos, (12 + rnd.nextDouble() * 14) * scale, 0.9 * opacity);
      } else if (useCoin) {
        // Painted coin: a gold ellipse that squashes as if tumbling.
        final spin = math.sin((phase * 6 + i) * math.pi);
        canvas.drawOval(
          Rect.fromCenter(
            center: pos,
            width: (9 + rnd.nextDouble() * 5) * scale * spin.abs().clamp(0.25, 1.0),
            height: (9 + rnd.nextDouble() * 5) * scale,
          ),
          Paint()..color = const Color(0xFFFFD24A).withValues(alpha: 0.9 * opacity),
        );
      } else {
        canvas.drawCircle(
          pos,
          (1.8 + rnd.nextDouble() * 2.2) * scale,
          Paint()..color = Colors.white.withValues(alpha: 0.75 * opacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

/// Two golden horns angled in from the edges.
class _HornPainter extends CustomPainter {
  const _HornPainter({this.art});
  final ui.Image? art;

  @override
  void paint(Canvas canvas, Size size) {
    final len = size.width * 0.30;
    final y = size.height * 0.30;

    for (final left in [true, false]) {
      canvas.save();
      canvas.translate(left ? 0 : size.width, y);
      canvas.scale(left ? 1 : -1, 1);
      canvas.rotate(0.32);

      if (art != null) {
        canvas.drawImageRect(
          art!,
          Rect.fromLTWH(0, 0, art!.width.toDouble(), art!.height.toDouble()),
          Rect.fromLTWH(0, -len * 0.16, len, len * 0.32),
          Paint()
            ..blendMode = BlendMode.plus
            ..filterQuality = FilterQuality.medium,
        );
      } else {
        // A tapering gold cone with a flared bell — enough to read as a horn.
        final gold = Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, -len * 0.1),
            Offset(0, len * 0.12),
            [const Color(0xFFFFEFB8), const Color(0xFFD9A32B), const Color(0xFF7A5410)],
          );
        canvas.drawPath(
          Path()
            ..moveTo(0, -len * 0.16)
            ..lineTo(len * 0.86, -len * 0.045)
            ..lineTo(len * 0.86, len * 0.045)
            ..lineTo(0, len * 0.16)
            ..close(),
          gold,
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(0, 0), width: len * 0.10, height: len * 0.33),
          gold,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HornPainter old) => old.art != art;
}

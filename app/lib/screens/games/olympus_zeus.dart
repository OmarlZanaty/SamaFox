import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'olympus_symbols.dart';

/// What Zeus is doing. The screen sets this and the stage animates itself.
enum ZeusMood {
  /// Standing over the clouds, breathing, watching nothing in particular.
  idle,

  /// The board is resolving — he leans toward it.
  watching,

  /// A win landed.
  reacting,

  /// Multipliers are about to be collected: the air charges around his hand.
  charging,

  /// The bolt is out.
  striking,

  /// Free spins.
  bonus,
}

const _gold = Color(0xFFE3B84A);
const _boltBlue = Color(0xFF9FD8FF);

/// Zeus, to the right of the board.
///
/// Uses `zeus.png` / `zeus_strike.png` when the artwork is delivered (see
/// OLYMPUS_ARTWORK_BRIEF.md); until then it paints a stylised robed, bearded
/// figure over the clouds so the composition — grid centre, god right — is
/// correct from the first build rather than an empty box.
///
/// The stage never overlaps the grid: the screen gives it its own column, and
/// the strike effect is drawn by [LightningStrike] on a separate layer above
/// the board so the symbols underneath stay readable.
class ZeusStage extends StatefulWidget {
  const ZeusStage({
    super.key,
    required this.mood,
    this.reducedMotion = false,
    this.reducedFlash = false,
    this.art,
  });

  final ZeusMood mood;
  final bool reducedMotion;
  final bool reducedFlash;
  final OlympusArt? art;

  @override
  State<ZeusStage> createState() => _ZeusStageState();
}

class _ZeusStageState extends State<ZeusStage> with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  late final AnimationController _energy = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _syncEnergy();
  }

  @override
  void didUpdateWidget(covariant ZeusStage old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _syncEnergy();
  }

  void _syncEnergy() {
    final hot = widget.mood == ZeusMood.charging ||
        widget.mood == ZeusMood.striking ||
        widget.mood == ZeusMood.bonus;
    if (hot && !widget.reducedMotion) {
      if (!_energy.isAnimating) _energy.repeat(reverse: true);
    } else {
      _energy.stop();
      _energy.value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _energy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strike = widget.mood == ZeusMood.striking;
    final celebrating =
        widget.mood == ZeusMood.reacting || widget.mood == ZeusMood.bonus;

    // Pick the delivered pose for the mood, falling back through to the neutral
    // one so a partial art delivery still shows Zeus rather than nothing.
    final poseName = strike
        ? 'zeus_strike'
        : (celebrating ? 'zeus_celebrate' : 'zeus');
    final art = widget.art?.forScene(poseName) ?? widget.art?.forScene('zeus');
    final pedestal = widget.art?.forScene('zeus_pedestal');

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _energy]),
      builder: (context, _) {
        final breath = widget.reducedMotion ? 0.5 : _breath.value;
        final energy = _energy.value;

        // He leans a few degrees toward the board while it resolves, and stands
        // up straight again when it stops. Small, but it is what makes him feel
        // like he is watching the game rather than posted next to it.
        final lean = switch (widget.mood) {
          ZeusMood.idle => 0.0,
          ZeusMood.watching => -0.035,
          ZeusMood.reacting => -0.05,
          ZeusMood.charging || ZeusMood.striking => -0.07,
          ZeusMood.bonus => -0.02,
        };

        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // The marble column he stands on, behind and below him.
                if (pedestal != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      widthFactor: 0.72,
                      heightFactor: 0.34,
                      child: RawImage(image: pedestal, fit: BoxFit.contain),
                    ),
                  ),
                if (!widget.reducedFlash && (strike || energy > 0))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              _boltBlue.withValues(alpha: 0.30 * (strike ? 1 : energy)),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Transform.rotate(
                  angle: lean,
                  alignment: Alignment.bottomCenter,
                  child: Transform.translate(
                    offset: Offset(0, -breath * 4),
                    child: art != null
                        ? RawImage(image: art, fit: BoxFit.contain)
                        : CustomPaint(
                            size: Size(constraints.maxWidth, constraints.maxHeight),
                            painter: _ZeusPainter(
                              mood: widget.mood,
                              breath: breath,
                              energy: strike ? 1.0 : energy,
                              showArcs: !widget.reducedFlash,
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A stylised Zeus: robed body, white beard, laurel, and a raised arm holding a
/// thunderbolt. Deliberately a silhouette with a strong rim light rather than a
/// detailed portrait — it reads at phone size, and it is honest about being a
/// placeholder for the painted character.
class _ZeusPainter extends CustomPainter {
  const _ZeusPainter({
    required this.mood,
    required this.breath,
    required this.energy,
    required this.showArcs,
  });

  final ZeusMood mood;
  final double breath, energy;
  final bool showArcs;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final cx = w * 0.5;

    // ── Clouds under him ───────────────────────────────────────────────────
    final cloud = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, h * 0.86),
        Offset(0, h),
        [const Color(0x88C9B6FF), const Color(0x11C9B6FF)],
      );
    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      canvas.drawCircle(
        Offset(w * (0.15 + t * 0.7), h * (0.90 + math.sin(t * math.pi) * -0.03)),
        w * 0.16,
        cloud,
      );
    }

    // ── Robe ───────────────────────────────────────────────────────────────
    final robe = Path()
      ..moveTo(cx - w * 0.10, h * 0.40)
      ..lineTo(cx + w * 0.12, h * 0.40)
      ..lineTo(cx + w * 0.26, h * 0.90)
      ..lineTo(cx - w * 0.24, h * 0.90)
      ..close();
    canvas.drawPath(
      robe,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - w * 0.24, h * 0.4),
          Offset(cx + w * 0.26, h * 0.9),
          [const Color(0xFFFDFBF4), const Color(0xFFB9AFCB), const Color(0xFF6E6486)],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Robe folds.
    final fold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x55574C6E);
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(
        Offset(cx + i * w * 0.05, h * 0.44),
        Offset(cx + i * w * 0.09, h * 0.89),
        fold,
      );
    }

    // Gold sash and shoulder armour.
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.10, h * 0.45)
        ..lineTo(cx + w * 0.12, h * 0.45)
        ..lineTo(cx + w * 0.15, h * 0.53)
        ..lineTo(cx - w * 0.12, h * 0.53)
        ..close(),
      Paint()..color = _gold.withValues(alpha: 0.9),
    );

    // ── Raised arm with the thunderbolt ────────────────────────────────────
    final armLift = mood == ZeusMood.charging ||
            mood == ZeusMood.striking ||
            mood == ZeusMood.bonus
        ? 1.0
        : (mood == ZeusMood.reacting ? 0.45 : 0.12);
    final handX = cx - w * 0.22 - armLift * w * 0.06;
    final handY = h * 0.40 - armLift * h * 0.16;

    canvas.drawLine(
      Offset(cx - w * 0.09, h * 0.44),
      Offset(handX, handY),
      Paint()
        ..strokeWidth = w * 0.075
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE8D2B4),
    );

    // The bolt itself, brightening with the charge.
    final boltPaint = Paint()
      ..color = Color.lerp(const Color(0xFFFFE9A8), Colors.white, energy)!
      ..maskFilter = MaskFilter.blur(BlurStyle.solid, 2 + energy * 5);
    canvas.drawPath(_boltPath(Offset(handX, handY), w * 0.13), boltPaint);

    // ── Head ───────────────────────────────────────────────────────────────
    final headC = Offset(cx, h * 0.30);
    final headR = w * 0.105;
    canvas.drawCircle(headC, headR, Paint()..color = const Color(0xFFE8D2B4));

    // Beard — the single most identifying feature at this size.
    final beard = Path()
      ..moveTo(headC.dx - headR * 0.95, headC.dy + headR * 0.15)
      ..quadraticBezierTo(
        headC.dx - headR * 0.8,
        headC.dy + headR * 2.6,
        headC.dx,
        headC.dy + headR * 2.9,
      )
      ..quadraticBezierTo(
        headC.dx + headR * 0.8,
        headC.dy + headR * 2.6,
        headC.dx + headR * 0.95,
        headC.dy + headR * 0.15,
      )
      ..quadraticBezierTo(
        headC.dx,
        headC.dy + headR * 1.1,
        headC.dx - headR * 0.95,
        headC.dy + headR * 0.15,
      )
      ..close();
    canvas.drawPath(beard, Paint()..color = const Color(0xFFF6F3EC));

    // Hair.
    canvas.drawArc(
      Rect.fromCircle(center: headC, radius: headR * 1.06),
      math.pi * 1.06,
      math.pi * 0.88,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = headR * 0.55
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFF6F3EC),
    );

    // Glowing eyes — brighter the more charged he is.
    final eyeGlow = 0.45 + energy * 0.55;
    for (final dx in [-headR * 0.36, headR * 0.36]) {
      canvas.drawCircle(
        Offset(headC.dx + dx, headC.dy - headR * 0.08),
        headR * (0.13 + energy * 0.05),
        Paint()
          ..color = Color.lerp(const Color(0xFF3E6EA8), _boltBlue, eyeGlow)!
          ..maskFilter = MaskFilter.blur(BlurStyle.solid, 1.5 + energy * 3.5),
      );
    }

    // Laurel crown.
    final laurel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = headR * 0.16
      ..strokeCap = StrokeCap.round
      ..color = _gold;
    canvas.drawArc(
      Rect.fromCircle(center: headC, radius: headR * 1.16),
      math.pi * 1.12,
      math.pi * 0.76,
      false,
      laurel,
    );

    // ── Charge arcs around the hand ────────────────────────────────────────
    if (showArcs && energy > 0.02) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _boltBlue.withValues(alpha: 0.55 + energy * 0.45);
      final rnd = math.Random(11);
      for (var i = 0; i < 5; i++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final r = w * (0.10 + rnd.nextDouble() * 0.10) * (0.6 + energy);
        final p = Path()..moveTo(handX, handY);
        var cur = Offset(handX, handY);
        for (var k = 0; k < 3; k++) {
          cur += Offset(
            math.cos(a + rnd.nextDouble() - 0.5) * r / 3,
            math.sin(a + rnd.nextDouble() - 0.5) * r / 3,
          );
          p.lineTo(cur.dx, cur.dy);
        }
        canvas.drawPath(p, arc);
      }
    }
  }

  Path _boltPath(Offset c, double s) => Path()
    ..moveTo(c.dx + s * 0.15, c.dy - s)
    ..lineTo(c.dx - s * 0.30, c.dy + s * 0.10)
    ..lineTo(c.dx + s * 0.02, c.dy + s * 0.10)
    ..lineTo(c.dx - s * 0.18, c.dy + s)
    ..lineTo(c.dx + s * 0.34, c.dy - s * 0.16)
    ..lineTo(c.dx + s * 0.00, c.dy - s * 0.16)
    ..close();

  @override
  bool shouldRepaint(covariant _ZeusPainter old) =>
      old.mood != mood || old.breath != breath || old.energy != energy;
}

// ── Strike layer ─────────────────────────────────────────────────────────────

/// A bolt travelling from Zeus's hand to a point on the board.
///
/// Drawn on its own layer above the grid, so it can cross the board without the
/// symbols underneath being covered by an opaque widget. [progress] runs 0→1;
/// the screen drives it once per multiplier collection.
class LightningStrike extends StatelessWidget {
  const LightningStrike({
    super.key,
    required this.from,
    required this.to,
    required this.progress,
    this.reducedFlash = false,
  });

  /// Both are fractions of the overlay's size, so the caller does not need to
  /// know the pixel geometry of the stage.
  final Alignment from, to;
  final double progress;
  final bool reducedFlash;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _StrikePainter(
            from: from,
            to: to,
            progress: progress,
            reducedFlash: reducedFlash,
          ),
        ),
      );
}

class _StrikePainter extends CustomPainter {
  const _StrikePainter({
    required this.from,
    required this.to,
    required this.progress,
    required this.reducedFlash,
  });

  final Alignment from, to;
  final double progress;
  final bool reducedFlash;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final a = from.alongSize(size);
    final b = to.alongSize(size);

    // The bolt draws itself in over the first 40% and fades over the rest.
    final draw = (progress / 0.4).clamp(0.0, 1.0);
    final fade = progress < 0.4 ? 1.0 : 1 - ((progress - 0.4) / 0.6);

    final rnd = math.Random(((progress * 6).floor()) + 3);
    final path = Path()..moveTo(a.dx, a.dy);
    const segments = 7;
    for (var i = 1; i <= segments; i++) {
      final t = i / segments;
      if (t > draw) break;
      final base = Offset.lerp(a, b, t)!;
      final jitter = (1 - t) * size.shortestSide * 0.06;
      path.lineTo(
        base.dx + (rnd.nextDouble() - 0.5) * jitter,
        base.dy + (rnd.nextDouble() - 0.5) * jitter,
      );
    }

    if (!reducedFlash) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..color = _boltBlue.withValues(alpha: 0.35 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.95 * fade),
    );
  }

  @override
  bool shouldRepaint(covariant _StrikePainter old) =>
      old.progress != progress || old.to != to;
}

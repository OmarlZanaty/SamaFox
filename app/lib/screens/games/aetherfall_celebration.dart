import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'aetherfall_symbols.dart';

/// The four original celebration tiers for أثيرفول — deliberately not named
/// "BIG WIN" / "MEGA WIN" / etc. per the game's creative-distinction brief.
const Map<String, String> kCelebrationLabels = {
  'BRIGHT_HIT': 'ضربة ساطعة',
  'SKYFIRE_SURGE': 'اندفاع سماوي',
  'CELESTIAL_BREAK': 'انفجار كوني',
  'AETHERFALL': 'أثيرفول',
};

const Map<String, Color> kCelebrationColors = {
  'BRIGHT_HIT': Color(0xFF4DD8E6),
  'SKYFIRE_SURGE': Color(0xFFFF8A3D),
  'CELESTIAL_BREAK': Color(0xFF9C7BE8),
  'AETHERFALL': Color(0xFFFFD08A),
};

/// A dimmed overlay with a central counter that ticks up to the win amount,
/// light-ribbon particles, and a skip button that appears after 500ms. Never
/// obscures the numeric result, per the QA acceptance criteria.
class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.tier,
    required this.amount,
    required this.onDone,
    this.reducedMotion = false,
    this.art,
  });

  final String tier;
  final int amount;
  final VoidCallback onDone;
  final bool reducedMotion;

  /// Effect textures. Null leaves the painter on its painted-dot fallback.
  final AetherfallArt? art;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 400 : 1400),
  )..forward();

  late final AnimationController _particles = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  bool _canSkip = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _canSkip = true);
    });
  }

  @override
  void dispose() {
    _count.dispose();
    _particles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = kCelebrationColors[widget.tier] ?? const Color(0xFF4DD8E6);
    final label = kCelebrationLabels[widget.tier] ?? widget.tier;

    return GestureDetector(
      onTap: _canSkip ? widget.onDone : null,
      child: Container(
        color: Colors.black.withValues(alpha: 0.15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (!widget.reducedMotion)
              AnimatedBuilder(
                animation: _particles,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _ParticlePainter(
                    t: _particles.value,
                    color: color,
                    spark: widget.art?.forFx('fx_particle_spark'),
                    ember: widget.art?.forFx('fx_particle_ember'),
                    ribbon: widget.art?.forFx('fx_ribbon_compass'),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 24)],
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: _count,
                  builder: (context, _) {
                    final shown =
                        (widget.amount * Curves.easeOutCubic.transform(_count.value)).round();
                    return Text(
                      shown.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 46,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                const Text(
                  'ربح السلسلة',
                  style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2),
                ),
              ],
            ),
            if (_canSkip)
              Positioned(
                bottom: 40,
                child: TextButton(
                  onPressed: widget.onDone,
                  child: const Text('تخطّي', style: TextStyle(color: Colors.white70)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Celebration particles.
///
/// With textures loaded these are real sparks and meteor embers blown outward
/// from the counter, plus a couple of slow compass-line ribbons sweeping behind
/// them. The textures are additive light rendered on black, so they composite
/// with [BlendMode.plus] — which also means the black they carry contributes
/// nothing and no matte is needed. Without them it falls back to the original
/// painted dots, so the celebration still reads if the art is missing.
class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.t,
    required this.color,
    this.spark,
    this.ember,
    this.ribbon,
  });

  final double t;
  final Color color;
  final ui.Image? spark;
  final ui.Image? ember;
  final ui.Image? ribbon;

  void _blit(Canvas canvas, ui.Image img, Offset pos, double size, double opacity) {
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromCenter(center: pos, width: size, height: size * img.height / img.width);
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()
        ..blendMode = BlendMode.plus
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final center = Offset(size.width / 2, size.height * 0.42);

    // Ribbons sit behind the sparks and drift on a slower cycle.
    if (ribbon != null) {
      for (var i = 0; i < 2; i++) {
        final phase = (t + i * 0.5) % 1.0;
        final drift = (phase - 0.5) * size.width * 0.9;
        final fade = math.sin(phase * math.pi);
        canvas.save();
        canvas.translate(center.dx + drift, center.dy + (i == 0 ? -60 : 70));
        canvas.rotate(i == 0 ? -0.18 : 0.14);
        _blit(canvas, ribbon!, Offset.zero, size.width * 0.75, 0.5 * fade);
        canvas.restore();
      }
    }

    for (var i = 0; i < 26; i++) {
      final angle = rnd.nextDouble() * 2 * math.pi;
      final speed = 60 + rnd.nextDouble() * 140;
      final phase = (t + i / 26) % 1.0;
      final r = phase * speed * 2;
      final pos = center + Offset(math.cos(angle) * r, math.sin(angle) * r * 0.6 - phase * 40);
      final opacity = (1 - phase).clamp(0.0, 1.0);

      // Roughly a third are embers, the rest sparks — enough variety to read as
      // debris rather than a uniform particle system.
      final useEmber = ember != null && i % 3 == 0;
      final img = useEmber ? ember : spark;
      if (img != null) {
        _blit(canvas, img, pos, 16 + rnd.nextDouble() * 20, 0.85 * opacity);
      } else {
        canvas.drawCircle(
          pos,
          2.2 + rnd.nextDouble() * 2,
          Paint()..color = color.withValues(alpha: 0.55 * opacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.spark != spark;
}

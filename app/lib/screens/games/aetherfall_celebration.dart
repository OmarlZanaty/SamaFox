import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The four original celebration tiers for أثيرفول — deliberately not named
/// "BIG WIN" / "MEGA WIN" / etc. per the game's creative-distinction brief.
const Map<String, String> kCelebrationLabels = {
  'BRIGHT_HIT': 'BRIGHT HIT',
  'SKYFIRE_SURGE': 'SKYFIRE SURGE',
  'CELESTIAL_BREAK': 'CELESTIAL BREAK',
  'AETHERFALL': 'AETHERFALL',
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
  });

  final String tier;
  final int amount;
  final VoidCallback onDone;
  final bool reducedMotion;

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
                  painter: _ParticlePainter(t: _particles.value, color: color),
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
                  'SEQUENCE WIN',
                  style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2),
                ),
              ],
            ),
            if (_canSkip)
              Positioned(
                bottom: 40,
                child: TextButton(
                  onPressed: widget.onDone,
                  child: const Text('Skip', style: TextStyle(color: Colors.white70)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final center = Offset(size.width / 2, size.height * 0.42);
    for (var i = 0; i < 26; i++) {
      final angle = rnd.nextDouble() * 2 * math.pi;
      final speed = 60 + rnd.nextDouble() * 140;
      final phase = (t + i / 26) % 1.0;
      final r = phase * speed * 2;
      final pos = center + Offset(math.cos(angle) * r, math.sin(angle) * r * 0.6 - phase * 40);
      final opacity = (1 - phase).clamp(0.0, 1.0);
      final paint = Paint()..color = color.withValues(alpha: 0.55 * opacity);
      canvas.drawCircle(pos, 2.2 + rnd.nextDouble() * 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => oldDelegate.t != t;
}

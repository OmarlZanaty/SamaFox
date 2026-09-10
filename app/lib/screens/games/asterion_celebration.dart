import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'asterion_art.dart';

/// The four original celebration tiers for أستيريون. Deliberately not "BIG WIN"
/// / "MEGA WIN" — see ASTERION_ARTWORK_BRIEF.md for the naming rationale.
const Map<String, String> kTierLabels = {
  'NICE_WIN': 'ومضة',
  'GREAT_SURGE': 'اندفاع الرعد',
  'EPIC_STORM': 'عاصفة الآلهة',
  'DIVINE_SURGE': 'صاعقة أستيريون',
};

const Map<String, Color> kTierColours = {
  'NICE_WIN': AsterionPalette.cyan,
  'GREAT_SURGE': AsterionPalette.tide,
  'EPIC_STORM': AsterionPalette.magenta,
  'DIVINE_SURGE': AsterionPalette.amber,
};

/// A dimmed overlay with a counter that ticks up to the win, shard particles and
/// a skip control that appears after half a second.
///
/// Two rules it must never break: the numeric amount stays legible the entire
/// time, and the player is never trapped — Skip settles the counter instantly.
class AsterionCelebration extends StatefulWidget {
  const AsterionCelebration({
    super.key,
    required this.tier,
    required this.amount,
    required this.bet,
    required this.onDone,
    this.reducedMotion = false,
  });

  final String tier;
  final int amount;
  final int bet;
  final VoidCallback onDone;
  final bool reducedMotion;

  @override
  State<AsterionCelebration> createState() => _AsterionCelebrationState();
}

class _AsterionCelebrationState extends State<AsterionCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 400 : 1500),
  )..forward();

  late final AnimationController _particles = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  )..repeat();

  bool _canSkip = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _canSkip = true);
    });
    // The overlay closes itself; the player skipping only gets there sooner.
    _count.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        Future.delayed(
          Duration(milliseconds: widget.reducedMotion ? 300 : 1100),
          () {
            if (mounted) widget.onDone();
          },
        );
      }
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
    final colour = kTierColours[widget.tier] ?? AsterionPalette.cyan;
    final label = kTierLabels[widget.tier] ?? '';
    final ratio = widget.bet > 0 ? widget.amount / widget.bet : 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: Stack(
          children: [
            if (!widget.reducedMotion)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _particles,
                  builder: (_, __) => CustomPaint(
                    painter: _ShardPainter(progress: _particles.value, colour: colour),
                  ),
                ),
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: colour,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      shadows: [
                        Shadow(color: colour.withValues(alpha: 0.8), blurRadius: 22),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${ratio.toStringAsFixed(ratio >= 100 ? 0 : 1)}× الرهان',
                    style: const TextStyle(color: AsterionPalette.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _count,
                    builder: (_, __) {
                      final shown = (widget.amount * Curves.easeOutCubic.transform(_count.value))
                          .round();
                      return Text(
                        '$shown',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 54,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Colors.black, blurRadius: 12)],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  const Text('عملة', style: TextStyle(color: AsterionPalette.amber, fontSize: 15)),
                  const SizedBox(height: 22),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _canSkip ? 1 : 0,
                    child: TextButton(
                      onPressed: _canSkip ? widget.onDone : null,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('متابعة'),
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

class _ShardPainter extends CustomPainter {
  const _ShardPainter({required this.progress, required this.colour});

  final double progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (var i = 0; i < 42; i++) {
      final x = rnd.nextDouble() * size.width;
      final speed = 0.4 + rnd.nextDouble();
      final y = ((progress * speed + rnd.nextDouble()) % 1.0) * size.height;
      final s = 2.0 + rnd.nextDouble() * 4;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * 6 + i);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: s, height: s * 2.2),
        Paint()..color = (i.isEven ? colour : Colors.white).withValues(alpha: 0.55),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ShardPainter old) => old.progress != progress;
}

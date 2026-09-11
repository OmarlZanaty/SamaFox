import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'asterion_art.dart';

/// The entry into تجارب السماء (Skyfall Trials): the crest opens into a portal,
/// Asterion raises the staff, and the free-spin count is stated plainly before
/// play resumes.
///
/// It closes itself after a beat, and a tap closes it sooner — no player should
/// have to sit through the same transition on their fortieth trial.
class TrialTransition extends StatefulWidget {
  const TrialTransition({
    super.key,
    required this.spins,
    required this.crests,
    required this.onDone,
    this.reducedMotion = false,
  });

  final int spins;
  final int crests;
  final VoidCallback onDone;
  final bool reducedMotion;

  @override
  State<TrialTransition> createState() => _TrialTransitionState();
}

class _TrialTransitionState extends State<TrialTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 700 : 2100),
  )..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GestureDetector(
        onTap: widget.onDone,
        child: Material(
          color: Colors.black.withValues(alpha: 0.86),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_c.value);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PortalPainter(progress: t)),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: (t * 1.6).clamp(0.0, 1.0),
                        child: SymbolIcon('CREST', size: 88 + 18 * t),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'تجارب السماء',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          shadows: [Shadow(color: AsterionPalette.cyan, blurRadius: 22)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.crests} شعارات فتحت البوابة',
                        style: const TextStyle(color: AsterionPalette.muted, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AsterionPalette.cyan),
                          color: AsterionPalette.cyan.withValues(alpha: 0.14),
                        ),
                        child: Text(
                          '${widget.spins} لفة مجانية',
                          style: const TextStyle(
                            color: AsterionPalette.cyanPale,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'مضاعف التجارب لا يُصفّر حتى تنتهي اللفّات',
                        style: TextStyle(color: AsterionPalette.amber, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PortalPainter extends CustomPainter {
  const _PortalPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * (0.15 + 0.55 * progress);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AsterionPalette.cyan.withValues(alpha: 0.0),
            AsterionPalette.cyan.withValues(alpha: 0.30 * progress),
            AsterionPalette.magenta.withValues(alpha: 0.0),
          ],
          stops: const [0.35, 0.72, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Clouds spiralling inward.
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8 + progress * 2.4;
      final rr = r * (1.15 - 0.5 * progress);
      canvas.drawCircle(
        Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a) * 0.6),
        6 + 10 * (1 - progress),
        Paint()
          ..color = AsterionPalette.silver.withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(_PortalPainter old) => old.progress != progress;
}

/// What the trial paid, shown once the last free spin resolves.
///
/// It states the arithmetic rather than only the total, because the meter is
/// the whole feature: a player should leave knowing that 15 spins × a 62x meter
/// is where the number came from.
class TrialSummarySheet extends StatelessWidget {
  const TrialSummarySheet({
    super.key,
    required this.totalCoins,
    required this.spins,
    required this.retriggers,
    required this.finalMultiplier,
  });

  final int totalCoins;
  final int spins;
  final int retriggers;
  final int finalMultiplier;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16204A), Color(0xFF080B1E)],
          ),
          border: Border.all(color: AsterionPalette.cyan.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'انتهت تجارب السماء',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              '$totalCoins',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: AsterionPalette.amber,
                fontSize: 40,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text('عملة', style: TextStyle(color: AsterionPalette.muted, fontSize: 13)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('اللفّات', '$spins'),
                _stat('لفّات إضافية', '${retriggers * 5}'),
                _stat('المضاعف النهائي', '${finalMultiplier}x'),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AsterionPalette.cyanDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('تحصيل'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: AsterionPalette.cyanPale,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AsterionPalette.muted, fontSize: 11)),
        ],
      );
}

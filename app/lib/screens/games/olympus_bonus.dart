import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'olympus_strings.dart';
import 'olympus_symbols.dart';

const _gold = Color(0xFFE3B84A);
const _boltBlue = Color(0xFF9FD8FF);
const _violetDeep = Color(0xFF1A0838);

/// The transition into free spins.
///
/// Darkens the screen, throws a storm of bolts, and announces the award. It
/// calls [onDone] when it finishes, or immediately on tap — the player is never
/// held here, which matters because this fires roughly once every 200 spins and
/// a player grinding autoplay will see it a lot.
class OlympusFreeSpinsIntro extends StatefulWidget {
  const OlympusFreeSpinsIntro({
    super.key,
    required this.spins,
    required this.scatters,
    required this.strings,
    required this.onDone,
    this.reducedMotion = false,
    this.reducedFlash = false,
    this.art,
  });

  final int spins, scatters;
  final OlympusStrings strings;
  final VoidCallback onDone;
  final bool reducedMotion, reducedFlash;
  final OlympusArt? art;

  @override
  State<OlympusFreeSpinsIntro> createState() => _OlympusFreeSpinsIntroState();
}

class _OlympusFreeSpinsIntroState extends State<OlympusFreeSpinsIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 700 : 2400),
  );

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return GestureDetector(
      onTap: _finish,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final appear = Curves.easeOutBack.transform((t / 0.35).clamp(0.0, 1.0));
          return Container(
            color: _violetDeep.withValues(alpha: 0.90),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!widget.reducedFlash)
                  CustomPaint(size: Size.infinite, painter: _StormPainter(t: t)),
                Transform.scale(
                  scale: appear.clamp(0.1, 1.4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.electric_bolt_rounded,
                        size: 58,
                        color: _boltBlue,
                        shadows: [
                          Shadow(color: _boltBlue.withValues(alpha: 0.9), blurRadius: 26),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.scattersLanded(widget.scatters),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.freeSpinsAwarded(widget.spins),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          shadows: [Shadow(color: Color(0xAAE3B84A), blurRadius: 22)],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 34),
                        child: Text(
                          s.bonusMeterNote,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StormPainter extends CustomPainter {
  const _StormPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(5);
    for (var i = 0; i < 9; i++) {
      final phase = ((t * 2.2) + i / 9) % 1.0;
      if (phase > 0.35) continue;
      final alpha = (1 - phase / 0.35).clamp(0.0, 1.0);
      final x = rnd.nextDouble() * size.width;
      final path = Path()..moveTo(x, 0);
      var cur = Offset(x, 0);
      while (cur.dy < size.height) {
        cur = Offset(
          cur.dx + (rnd.nextDouble() - 0.5) * size.width * 0.10,
          cur.dy + size.height * 0.14,
        );
        path.lineTo(cur.dx, cur.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _boltBlue.withValues(alpha: 0.6 * alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StormPainter old) => old.t != t;
}

// ── In-feature HUD ───────────────────────────────────────────────────────────

/// Spins left and the running multiplier meter, shown beside the board for the
/// whole feature.
///
/// The meter is the feature, so it is the biggest number on the strip and it
/// animates when it grows — a player needs to see that a ×25 they just
/// collected is now part of every remaining win.
class OlympusBonusHud extends StatelessWidget {
  const OlympusBonusHud({
    super.key,
    required this.spinsLeft,
    required this.meter,
    required this.strings,
    this.compact = false,
  });

  final int spinsLeft, meter;
  final OlympusStrings strings;

  /// Landscape puts this in a narrow rail beside the board; portrait gives it a
  /// full-width strip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final content = [
      _stat(s.freeSpinsShort, '$spinsLeft', Colors.white),
      _meterChip(),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: 8),
      decoration: BoxDecoration(
        color: _violetDeep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: compact
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              content[0],
              const SizedBox(height: 10),
              content[1],
            ],)
          : Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: content),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1),
          ),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      );

  Widget _meterChip() => TweenAnimationBuilder<double>(
        tween: Tween(begin: meter.toDouble(), end: meter.toDouble()),
        duration: const Duration(milliseconds: 400),
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.multiplier,
              style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1),
            ),
            AnimatedScale(
              duration: const Duration(milliseconds: 260),
              scale: meter > 0 ? 1.0 : 0.9,
              child: Text(
                '×$meter',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: meter > 0 ? _gold : Colors.white30,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  shadows: meter > 0
                      ? const [Shadow(color: Color(0x99E3B84A), blurRadius: 14)]
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Summary ──────────────────────────────────────────────────────────────────

/// What the bonus paid, shown once it ends.
///
/// States the multiplier rule again in the same words as the help sheet: a
/// player who just watched a ×83 meter build has every reason to wonder whether
/// the numbers multiplied or added, and this is the moment they will ask.
class OlympusBonusSummary extends StatelessWidget {
  const OlympusBonusSummary({
    super.key,
    required this.totalCoins,
    required this.spinsPlayed,
    required this.finalMultiplier,
    required this.retriggers,
    required this.strings,
  });

  final int totalCoins, spinsPlayed, finalMultiplier, retriggers;
  final OlympusStrings strings;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Directionality(
      textDirection: s.direction,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1258), _violetDeep],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.bonusOver,
              style: const TextStyle(
                color: _gold,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '$totalCoins',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              s.bonusTotal,
              style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat(s.spinsPlayed, '$spinsPlayed'),
                _stat(s.highestMultiplier, '×$finalMultiplier'),
                if (retriggers > 0) _stat(s.freeSpins, '+${retriggers * 5}'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              s.multipliersAdd,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _gold),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(
                  s.close,
                  style: const TextStyle(
                    color: Color(0xFF2B1206),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: _boltBlue, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      );
}

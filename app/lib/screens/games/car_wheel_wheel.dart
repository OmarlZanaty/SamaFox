import 'dart:math';
import 'package:flutter/material.dart';
import 'car_wheel_art.dart';
import 'car_wheel_engine.dart';

/// The wheel stage: a rotating disk under fixed light, rim, bulbs, hub and
/// pointer. Everything that moves repaints through [angle] or [ambient], so a
/// spin never rebuilds the rest of the screen.
class CarWheelWheel extends StatelessWidget {
  final double size;
  final ValueNotifier<double> angle;
  final Animation<double> ambient;

  /// Seconds left in betting, refreshed by the screen's 1-second clock.
  final ValueNotifier<double> secondsLeft;
  final String phase;
  final String? result;
  final Map<String, int> myStakes;
  final bool reduced;
  final GlobalKey diskKey;
  final ValueChanged<String>? onBet;

  const CarWheelWheel({
    super.key,
    required this.size,
    required this.angle,
    required this.ambient,
    required this.secondsLeft,
    required this.phase,
    required this.result,
    required this.myStakes,
    required this.reduced,
    required this.diskKey,
    this.onBet,
  });

  @override
  Widget build(BuildContext context) {
    final winner = phase == 'result' ? result : null;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // A soft halo so the wheel sits in light, not on a flat background.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      cwPink.withValues(alpha: .45),
                      cwPink.withValues(alpha: .12),
                      Colors.transparent,
                    ],
                    stops: const [
                      .55,
                      .78,
                      1,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Disk: wedges rotate; hit testing happens in disk coordinates.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: angle,
              builder: (_, child) =>
                  Transform.rotate(angle: angle.value, child: child),
              child: GestureDetector(
                key: diskKey,
                behavior: HitTestBehavior.opaque,
                onTapUp: onBet == null
                    ? null
                    : (d) {
                        // Transform already un-rotates this local position.
                        final key = carWheelKeyAt(d.localPosition, size);
                        if (key != null) onBet!(key);
                      },
                child: ExcludeSemantics(
                  child: CustomPaint(
                    size: Size.square(size),
                    painter: _DiskPainter(winner: winner, stakes: myStakes),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _MotionPainter(angle, ambient, phase, reduced),
                ),
              ),
            ),
          ),
          // Labels orbit with the disk but stay upright, so nothing is ever
          // read upside down.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: angle,
                  builder: (_, __) => Stack(
                    children: [
                      for (final (i, s) in carWheelSegments.indexed)
                        _label(
                          s,
                          i * carWheelSegmentAngle + angle.value,
                          winner == s.key,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Fixed light: a gloss that does not turn with the disk.
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _GlossPainter())),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: carWheelImage(
                'rim',
                const CustomPaint(painter: _RimPainter()),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BulbPainter(
                    ambient: ambient,
                    phase: phase,
                    reduced: reduced,
                  ),
                ),
              ),
            ),
          ),
          _hub(winner),
          Positioned(
            top: -size * .035,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: angle,
                  builder: (_, child) => Transform.rotate(
                    alignment: Alignment.topCenter,
                    angle: phase == 'spinning' && !reduced
                        ? _pointerKick(angle.value)
                        : 0,
                    child: child,
                  ),
                  child: SizedBox(
                    width: size * .11,
                    height: size * .155,
                    child: carWheelImage(
                      'pointer',
                      const CustomPaint(painter: _PointerPainter()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The pointer is knocked back as each divider passes, then springs home.
  double _pointerKick(double wheel) {
    final f = ((wheel + carWheelSegmentAngle / 2) % carWheelSegmentAngle) /
        carWheelSegmentAngle;
    return -.32 * pow(1 - f, 6);
  }

  Widget _label(CarWheelSegment s, double a, bool winner) {
    final c = size / 2;
    Offset polar(double r) => Offset(c + sin(a) * r, c - cos(a) * r);
    final emblem = size * .11, at = polar(size * .285);
    final stake = myStakes[s.key] ?? 0;
    return Positioned(
      left: at.dx - size * .09,
      top: at.dy - size * .105,
      width: size * .18,
      height: size * .19,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CarWheelEmblem(segment: s.key, size: emblem),
              if (stake > 0)
                Positioned(
                  right: -5,
                  bottom: 0,
                  child:
                      CarWheelChip(amount: _chipFor(stake), size: emblem * .4),
                ),
            ],
          ),
          Text(
            'x${s.multiplier}',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: winner ? cwGoldLight : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * .05,
              height: 1.1,
              shadows: const [
                Shadow(color: Color(0xAA3A0010), offset: Offset(0, 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _chipFor(int stake) =>
      carWheelChips.lastWhere((c) => c <= stake, orElse: () => 100);

  Widget _hub(String? winner) {
    final d = size * .27;
    return SizedBox.square(
      dimension: d,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RingPainter(
                  secondsLeft: secondsLeft,
                  ambient: ambient,
                  phase: phase,
                  reduced: reduced,
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: d * .8,
            child: carWheelImage(
              'hub',
              const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [cwPurple, cwPurpleDark]),
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: d * .56,
            child: FittedBox(child: _hubContent(winner)),
          ),
        ],
      ),
    );
  }

  Widget _hubContent(String? winner) {
    const style = TextStyle(
      color: cwGoldLight,
      fontWeight: FontWeight.w900,
      fontSize: 40,
      height: 1,
      fontFeatures: [FontFeature.tabularFigures()],
      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
    );
    if (winner != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CarWheelEmblem(segment: winner, size: 34),
          Text(
            'x${carWheelBet(winner)!.multiplier}',
            textDirection: TextDirection.ltr,
            style: style.copyWith(fontSize: 22),
          ),
        ],
      );
    }
    return switch (phase) {
      'betting' => ValueListenableBuilder<double>(
          valueListenable: secondsLeft,
          builder: (_, s, __) => Text(
            '${s.ceil()}',
            textDirection: TextDirection.ltr,
            style: style,
          ),
        ),
      'closing' => const Text('?', style: style),
      _ => const Icon(Icons.sync_rounded, color: cwGoldLight, size: 40),
    };
  }
}

/// Wedges in two jewel tones, lit from the centre, with gold dividers.
class _DiskPainter extends CustomPainter {
  final String? winner;
  final Map<String, int> stakes;
  const _DiskPainter({this.winner, required this.stakes});

  static const _tones = [
    [Color(0xFFF45379), Color(0xFFB91F4C), Color(0xFF430B29)],
    [Color(0xFFDC5C97), Color(0xFF8D1D57), Color(0xFF2F0A27)],
  ];

  @override
  void paint(Canvas c, Size size) {
    final center = size.center(Offset.zero), r = size.width * .455;
    final disk = Rect.fromCircle(center: center, radius: r);
    for (var i = 0; i < 8; i++) {
      final start = -pi / 2 + (i - .5) * carWheelSegmentAngle;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(disk, start, carWheelSegmentAngle, false)
        ..close();
      final tone = _tones[i % 2];
      c.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(colors: tone, stops: const [0, .55, 1])
              .createShader(disk),
      );
      c.drawArc(
          Rect.fromCircle(center: center, radius: r * .87),
          start + .035,
          carWheelSegmentAngle - .07,
          false,
          Paint()
            ..color = cwGoldLight.withValues(alpha: .3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,);
      if ((stakes[carWheelSegments[i].key] ?? 0) > 0) {
        c.drawPath(path, Paint()..color = cwGold.withValues(alpha: .12));
        c.drawPath(
          path,
          Paint()
            ..color = cwGoldLight.withValues(alpha: .6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (carWheelSegments[i].key == winner) {
        c.drawPath(
          path,
          Paint()
            ..shader = RadialGradient(
              colors: [
                cwGoldLight.withValues(alpha: .85),
                cwGold.withValues(alpha: .55),
                cwGold.withValues(alpha: .2),
              ],
            ).createShader(disk),
        );
      }
    }
    // Dividers: a dark groove with a gold inlay.
    for (var i = 0; i < 8; i++) {
      final a = -pi / 2 + (i - .5) * carWheelSegmentAngle;
      final edge = center + Offset(cos(a), sin(a)) * r;
      c.drawLine(
        center,
        edge,
        Paint()
          ..color = const Color(0x99400014)
          ..strokeWidth = size.width * .014,
      );
      c.drawLine(
        center,
        edge,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFFFF1B8),
              cwGold,
              Color(0xFFA8681B),
            ],
          ).createShader(Rect.fromPoints(center, edge))
          ..strokeWidth = size.width * .006,
      );
    }
    // Inner bezel around the hub.
    c.drawCircle(
      center,
      size.width * .15,
      Paint()..color = const Color(0xFF3A0618),
    );
    c.drawCircle(
      center,
      size.width * .15,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .008
        ..color = cwGold,
    );
  }

  @override
  bool shouldRepaint(_DiskPainter old) =>
      winner != old.winner || stakes != old.stakes;
}

/// Light that stays put while the disk turns under it.
class _GlossPainter extends CustomPainter {
  const _GlossPainter();
  @override
  void paint(Canvas c, Size size) {
    final center = size.center(Offset.zero), r = size.width * .455;
    final rect = Rect.fromCircle(center: center, radius: r);
    c.save();
    c.clipPath(Path()..addOval(rect));
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .22),
            Colors.white.withValues(alpha: .04),
            Colors.transparent,
            Colors.black.withValues(alpha: .22),
          ],
          stops: const [0, .35, .6, 1],
        ).createShader(rect),
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_GlossPainter old) => false;
}

/// Bulbs around the rim: a chase while betting, alternate flashing while the
/// wheel spins, all lit for the result.
class _BulbPainter extends CustomPainter {
  final Animation<double> ambient;
  final String phase;
  final bool reduced;
  _BulbPainter({
    required this.ambient,
    required this.phase,
    required this.reduced,
  }) : super(repaint: ambient);

  /// Where the studs sit on rim.png (degrees clockwise from the top), so the
  /// light lands on the art instead of beside it. The painted rim uses the same.
  static const studs = [
    0.0, 28, 57, 79.4, 100.8, 123, 147, 180, //
    213, 237, 259.2, 280.6, 303, 332,
  ];
  static const radius = .455;

  @override
  void paint(Canvas c, Size size) {
    final center = size.center(Offset.zero), r = size.width * radius;
    final t = reduced ? 0.0 : ambient.value;
    final n = studs.length;
    for (var i = 0; i < n; i++) {
      final double on = switch (phase) {
        'betting' => () {
            final d = ((t * n - i) % n + n) % n;
            return d < 3 ? 1 - d / 3 : 0.0;
          }(),
        'spinning' || 'closing' => ((t * 12).floor() + i).isEven ? 1.0 : 0.0,
        _ => .5 + .5 * sin(t * 2 * pi * 2),
      };
      if (on <= .02) continue;
      final a = studs[i] * pi / 180;
      final p = center + Offset(sin(a), -cos(a)) * r;
      final b = size.width * .02;
      c.drawCircle(
        p,
        b * 2.8,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFF3C4).withValues(alpha: .8 * on),
              cwGold.withValues(alpha: .35 * on),
              Colors.transparent,
            ],
            stops: const [
              0,
              .35,
              1,
            ],
          ).createShader(Rect.fromCircle(center: p, radius: b * 2.8)),
      );
      c.drawCircle(
        p,
        b * .55,
        Paint()..color = Colors.white.withValues(alpha: on),
      );
    }
  }

  @override
  bool shouldRepaint(_BulbPainter old) =>
      old.phase != phase || old.reduced != reduced;
}

/// Countdown around the hub: drains over the betting window, turns red and
/// pulses for the last three seconds.
class _RingPainter extends CustomPainter {
  final ValueNotifier<double> secondsLeft;
  final Animation<double> ambient;
  final String phase;
  final bool reduced;
  _RingPainter({
    required this.secondsLeft,
    required this.ambient,
    required this.phase,
    required this.reduced,
  }) : super(repaint: Listenable.merge([secondsLeft, ambient]));

  static const window = 25.0;

  @override
  void paint(Canvas c, Size size) {
    final center = size.center(Offset.zero),
        r = size.width / 2 - size.width * .05;
    final w = size.width * .085;
    c.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = const Color(0xCC1A0410),
    );
    if (phase == 'spinning' && !reduced) {
      c.drawArc(
        Rect.fromCircle(center: center, radius: r),
        ambient.value * 4 * pi,
        pi * .65,
        false,
        Paint()
          ..color = cwGoldLight
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }
    if (phase != 'betting') return;
    final s = secondsLeft.value;
    final urgent = s <= 3;
    final pulse =
        urgent && !reduced ? .75 + .25 * sin(ambient.value * 2 * pi * 4) : 1.0;
    final color = urgent ? const Color(0xFFFF4D5E) : cwGold;
    c.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -pi / 2,
      2 * pi * (s / window).clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w * pulse
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.phase != phase || old.reduced != reduced;
}

class _RimPainter extends CustomPainter {
  const _RimPainter();
  @override
  void paint(Canvas c, Size s) {
    final p = s.center(Offset.zero), r = s.width / 2;
    c.drawCircle(
      p,
      r * .95,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF4A1C86),
            Color(0xFF8B54D6),
            Color(0xFF4A1C86),
            Color(0xFF8B54D6),
            Color(0xFF4A1C86),
          ],
        ).createShader(Rect.fromCircle(center: p, radius: r))
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .09,
    );
    c.drawCircle(
      p,
      r * .905,
      Paint()
        ..color = cwGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .02,
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => false;
}

class _MotionPainter extends CustomPainter {
  final ValueNotifier<double> angle;
  final Animation<double> ambient;
  final String phase;
  final bool reduced;
  _MotionPainter(this.angle, this.ambient, this.phase, this.reduced)
      : super(repaint: Listenable.merge([angle, ambient]));
  @override
  void paint(Canvas c, Size s) {
    if (reduced) return;
    final center = s.center(Offset.zero);
    if (phase == 'spinning') {
      for (var i = 0; i < 8; i++) {
        c.drawArc(
          Rect.fromCircle(center: center, radius: s.width * (.18 + i * .03)),
          angle.value + i * .8,
          1.0,
          false,
          Paint()
            ..color = cwGoldLight.withValues(alpha: .15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    } else if (phase == 'result') {
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(s.width * .36, s.height * .12)
        ..lineTo(s.width * .64, s.height * .12)
        ..close();
      c.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              cwGoldLight.withValues(alpha: .12 + .22 * ambient.value),
              cwGoldLight.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromLTWH(
              s.width * .36,
              s.height * .12,
              s.width * .28,
              s.height * .38,
            ),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_MotionPainter old) =>
      old.phase != phase || old.reduced != reduced;
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter();
  @override
  void paint(Canvas c, Size s) {
    final path = Path()
      ..moveTo(s.width * .1, 0)
      ..lineTo(s.width * .9, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    c.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [cwGoldLight, cwGold, Color(0xFFA8681B)],
        ).createShader(Offset.zero & s),
    );
    c.drawCircle(
      Offset(s.width / 2, s.width * .35),
      s.width * .2,
      Paint()..color = cwPink,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) => false;
}

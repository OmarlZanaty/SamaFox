import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'roulette_engine.dart';

/// Colours and artwork for الروليت.
///
/// Generated artwork lives in assets/images/games/roulette/ (see
/// ROULETTE_ARTWORK_BRIEF.md); every image has a painted stand-in. The wheel
/// face, numbers, ball and table are always painted so they match the
/// single-zero order exactly.
const rlBlack = Color(0xFF080B14);
const rlNavy = Color(0xFF111634);
const rlNavy2 = Color(0xFF1D2454);
const rlPurple = Color(0xFF601BA3);
const rlPurpleDark = Color(0xFF260C4C);
const rlFelt = Color(0xFF087448);
const rlFeltDark = Color(0xFF035B38);
const rlFeltBorder = Color(0xFF41C47E);
const rlGold = Color(0xFFF5BD45);
const rlGoldLight = Color(0xFFFFE29A);
const rlWood = Color(0xFF8B4E28);
const rlWoodLight = Color(0xFFC88A48);
const rlRed = Color(0xFFC91F2A);
const rlPocketBlack = Color(0xFF111319);
const rlZero = Color(0xFF087C4D);
const rlMuted = Color(0xFFA99FBA);
const rlPink = Color(0xFFE5338F);

const _dir = 'assets/images/games/roulette';

Color roulettePaint(int n) => switch (rouletteColor(n)) {
      RouletteColor.green => rlZero,
      RouletteColor.red => rlRed,
      RouletteColor.black => rlPocketBlack,
    };

/// A generated image, or [fallback] when the file is missing.
class RouletteArt extends StatelessWidget {
  final String name;
  final double size;
  final Widget fallback;
  const RouletteArt(this.name,
      {super.key, required this.size, required this.fallback,});
  @override
  Widget build(BuildContext context) => Image.asset(
        '$_dir/$name.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: (size * 2.5).round().clamp(24, 512),
        errorBuilder: (_, __, ___) =>
            SizedBox.square(dimension: size, child: fallback),
      );
}

const _chipColors = {
  100: (Color(0xFF8D55C9), rlGold),
  500: (Color(0xFFE8572A), Colors.white),
  1000: (Color(0xFF1E9E5A), rlGold),
  5000: (Color(0xFF1F75CF), Color(0xFFB98CF0)),
  10000: (Color(0xFF1A1A1F), rlGold),
};
String _chipAsset(int v) => switch (v) {
      500 => 'chip_500',
      1000 => 'chip_1k',
      5000 => 'chip_5k',
      10000 => 'chip_10k',
      _ => 'chip_100',
    };

/// The denomination closest at or below [amount], for a stack's top chip.
int rouletteChipFor(int amount) => rouletteChips.lastWhere((c) => c <= amount,
    orElse: () => rouletteChips.first,);

/// A casino chip with its value written on it.
class RouletteChip extends StatelessWidget {
  final int value;
  final double size;
  final String? label;
  const RouletteChip(
      {super.key, required this.value, required this.size, this.label,});
  @override
  Widget build(BuildContext context) {
    final denom = rouletteChipFor(value);
    final (body, edge) = _chipColors[denom]!;
    final painted = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: body,
        border: Border.all(color: edge, width: size * .1),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 2)),
        ],
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RouletteArt(_chipAsset(denom), size: size, fallback: painted),
          Padding(
            padding: EdgeInsets.all(size * .24),
            child: FittedBox(
              child: Text(
                label ?? rouletteCompact(value),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The wheel: wood bowl, ball track, 37 pockets with numbers, ball.
class RouletteWheelPainter extends CustomPainter {
  final double wheelAngle, ballAngle, ballLift;
  final int? highlight;
  final double glow;
  final bool showBall;
  RouletteWheelPainter({
    required this.wheelAngle,
    required this.ballAngle,
    required this.ballLift,
    this.highlight,
    this.glow = 0,
    this.showBall = true,
  });

  static final Map<int, ui.Picture> _faces = {};

  /// Pockets and numbers drawn once per size, then only rotated.
  static ui.Picture _face(double s) => _faces.putIfAbsent(s.round(), () {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final r = s / 2;
        final seg = roulettePocketAngle;
        final outer = Rect.fromCircle(center: Offset.zero, radius: r * .80);
        for (var i = 0; i < rouletteWheel.length; i++) {
          final n = rouletteWheel[i];
          canvas.drawArc(outer, -pi / 2 + i * seg, seg, true,
              Paint()..color = roulettePaint(n),);
        }
        // Inner cone covers the middle of the pocket wedges.
        canvas.drawCircle(
          Offset.zero,
          r * .62,
          Paint()
            ..shader = const RadialGradient(
                    colors: [rlWoodLight, rlWood, Color(0xFF4A2812)],
                    stops: [0, .6, 1],)
                .createShader(
                    Rect.fromCircle(center: Offset.zero, radius: r * .62),),
        );
        final divider = Paint()
          ..color = const Color(0xFFD9D9E0)
          ..strokeWidth = max(1, s * .004);
        for (var i = 0; i < rouletteWheel.length; i++) {
          final a = -pi / 2 + i * seg;
          canvas.drawLine(Offset(cos(a), sin(a)) * r * .62,
              Offset(cos(a), sin(a)) * r * .80, divider,);
        }
        canvas.drawCircle(
          Offset.zero,
          r * .80,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * .012
            ..color = rlGold,
        );
        canvas.drawCircle(
          Offset.zero,
          r * .62,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * .01
            ..color = rlGold,
        );
        for (var i = 0; i < rouletteWheel.length; i++) {
          final tp = TextPainter(
            text: TextSpan(
              text: '${rouletteWheel[i]}',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: s * .036,
                  fontWeight: FontWeight.w800,),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          canvas.save();
          canvas.rotate((i + .5) * seg);
          canvas.translate(0, -r * .735);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
        }
        return recorder.endRecording();
      });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final r = s / 2;
    final c = Offset(r, r);
    // Shadow and wood bowl.
    canvas.drawCircle(
      c.translate(0, s * .015),
      r * .99,
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const SweepGradient(colors: [
          rlWood,
          rlWoodLight,
          rlWood,
          Color(0xFF5E3018),
          rlWood,
        ],).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * .985,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .018
        ..shader = const SweepGradient(colors: [
          rlGold,
          rlGoldLight,
          rlGold,
          Color(0xFFA9762A),
          rlGold,
        ],).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Ball track.
    canvas.drawCircle(
      c,
      r * .88,
      Paint()
        ..shader = const RadialGradient(
                colors: [Color(0xFF3A2010), Color(0xFF6B3D1E)], stops: [.9, 1],)
            .createShader(Rect.fromCircle(center: c, radius: r * .88)),
    );
    // Turning face.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(wheelAngle);
    canvas.drawPicture(_face(s));
    if (highlight != null && glow > 0) {
      final i = rouletteWheel.indexOf(highlight!);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * .80),
        -pi / 2 + i * roulettePocketAngle,
        roulettePocketAngle,
        true,
        Paint()..color = rlGoldLight.withValues(alpha: .55 * glow),
      );
    }
    canvas.restore();
    if (!showBall) return;
    // Ball: outer track (lift 1) down to the pocket ring (lift 0).
    final br = r * (.68 + (.84 - .68) * ballLift);
    final a = ballAngle - pi / 2;
    final p = c + Offset(cos(a), sin(a)) * br;
    canvas.drawCircle(
        p.translate(1, 2), s * .022, Paint()..color = Colors.black45,);
    canvas.drawCircle(
      p,
      s * .022,
      Paint()
        ..shader = const RadialGradient(
                center: Alignment(-.4, -.4),
                colors: [Colors.white, Color(0xFFCFCFD8)],)
            .createShader(Rect.fromCircle(center: p, radius: s * .022)),
    );
  }

  @override
  bool shouldRepaint(RouletteWheelPainter old) =>
      old.wheelAngle != wheelAngle ||
      old.ballAngle != ballAngle ||
      old.ballLift != ballLift ||
      old.highlight != highlight ||
      old.glow != glow ||
      old.showBall != showBall;
}

/// Painted stand-in for the centre turret.
class RouletteTurretPainter extends CustomPainter {
  const RouletteTurretPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final gold = Paint()
      ..shader = const RadialGradient(
              center: Alignment(-.3, -.3),
              colors: [rlGoldLight, rlGold, Color(0xFF8A5A14)],)
          .createShader(Offset.zero & size);
    for (var i = 0; i < 4; i++) {
      final a = i * pi / 2;
      canvas.drawLine(
        c,
        c + Offset(cos(a), sin(a)) * s * .42,
        Paint()
          ..color = rlGold
          ..strokeWidth = s * .07
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * s * .44, s * .07, gold);
    }
    canvas.drawCircle(c, s * .2, gold);
  }

  @override
  bool shouldRepaint(RouletteTurretPainter old) => false;
}

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

//// The wheel, seen from above under one fixed light (top left):
///
///   1.00–.92  lacquered wood rim with gold trims        (static)
///   .92–.75   ball track sloping into the bowl, eight
///             gold deflectors                            (static)
///   .75–.61   number ring                                (turns)
///   .61–.49   pockets with gold frets                    (turns)
///   .49–0     wooden cone; the turret image sits on top  (turns)
///
/// Both the bowl and the face are recorded once per size; a frame only
/// rotates the face and draws the ball and the light on top.
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

  static const numberOuter = .75, numberInner = .61, pocketInner = .49;

  /// Ball distance from the centre: [pocket] when it rests, [track] when it runs.
  static const pocket = .55, track = .845;

  static final Map<int, ui.Picture> _bowls = {}, _faces = {};

  static Shader _metal(double r) => const SweepGradient(
        colors: [
          Color(0xFFFFF1C1),
          rlGold,
          Color(0xFF9A6A1E),
          rlGold,
          Color(0xFFFFF1C1),
          rlGold,
          Color(0xFF8A5A14),
          rlGold,
          Color(0xFFFFF1C1),
        ],
        transform: GradientRotation(-pi / 4),
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));

  static void _ring(Canvas canvas, double radius, double width, double r) =>
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = _metal(r),
      );

  /// Rim, track and deflectors: everything that does not turn.
  static ui.Picture _bowl(double s) => _bowls.putIfAbsent(s.round(), () {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final r = s / 2;
        final all = Rect.fromCircle(center: Offset.zero, radius: r);
        // Lacquered wood: a warm radial body with fine concentric grain.
        canvas.drawCircle(
          Offset.zero,
          r,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(-.3, -.35),
              radius: .9,
              colors: [Color(0xFFB8702F), Color(0xFF7A3E17), Color(0xFF3E1C08)],
              stops: [.55, .85, 1],
            ).createShader(all),
        );
        final grain = Random(7);
        for (var i = 0; i < 26; i++) {
          final gr = r * (.925 + grain.nextDouble() * .07);
          final start = grain.nextDouble() * 2 * pi;
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: gr),
            start,
            .6 + grain.nextDouble() * 2.2,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(.6, s * .0022)
              ..color = (grain.nextBool() ? const Color(0xFF2A1205) : const Color(0xFFE0A15E))
                  .withValues(alpha: .18 + grain.nextDouble() * .2),
          );
        }
        _ring(canvas, r * .992, s * .012, r);
        _ring(canvas, r * .918, s * .014, r);
        // The track: bright at the lip, darker as it slopes into the bowl.
        canvas.drawCircle(
          Offset.zero,
          r * .91,
          Paint()
            ..shader = const RadialGradient(
              colors: [
                Color(0xFF0B0503),
                Color(0xFF1E0E05),
                Color(0xFF3E1E0B),
                Color(0xFF6B3C1A),
                Color(0xFFC58A4E),
                Color(0xFF2A1407),
              ],
              stops: [.80, .835, .88, .945, .978, 1],
            ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * .91)),
        );
        // Eight deflectors, alternating along and across the track.
        for (var i = 0; i < 8; i++) {
          canvas.save();
          canvas.rotate(i * pi / 4 + pi / 8);
          canvas.translate(0, -r * .80);
          if (i.isOdd) canvas.rotate(pi / 2);
          final w = s * .018, h = s * .042;
          final diamond = Path()
            ..moveTo(0, -h / 2)
            ..lineTo(w / 2, 0)
            ..lineTo(0, h / 2)
            ..lineTo(-w / 2, 0)
            ..close();
          canvas.drawPath(
            diamond.shift(Offset(s * .003, s * .004)),
            Paint()..color = Colors.black.withValues(alpha: .45),
          );
          canvas.drawPath(
            diamond,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF4CC), rlGold, Color(0xFF7A4E10)],
              ).createShader(Rect.fromCenter(center: Offset.zero, width: w, height: h)),
          );
          canvas.restore();
        }
        return recorder.endRecording();
      });

  /// Numbers, pockets and cone: everything that turns.
  static ui.Picture _face(double s) => _faces.putIfAbsent(s.round(), () {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final r = s / 2;
        final seg = roulettePocketAngle;
        final numbers = Rect.fromCircle(center: Offset.zero, radius: r * numberOuter);
        final pockets = Rect.fromCircle(center: Offset.zero, radius: r * numberInner);
        Color shade(Color c, double k) => Color.lerp(c, Colors.black, k)!;
        for (var i = 0; i < rouletteWheel.length; i++) {
          final base = roulettePaint(rouletteWheel[i]);
          final from = -pi / 2 + i * seg;
          // Number band: lit towards the outside edge.
          canvas.drawArc(
            numbers,
            from,
            seg,
            true,
            Paint()
              ..shader = RadialGradient(
                colors: [shade(base, .25), base, Color.lerp(base, Colors.white, .12)!],
                stops: const [numberInner / numberOuter, .9, 1],
              ).createShader(numbers),
          );
          // Pocket: darker and deeper.
          canvas.drawArc(
            pockets,
            from,
            seg,
            true,
            Paint()
              ..shader = RadialGradient(
                colors: [shade(base, .7), shade(base, .35), shade(base, .55)],
                stops: const [pocketInner / numberInner, .8, 1],
              ).createShader(pockets),
          );
        }
        // Gold frets between the pockets, fine lines between the numbers.
        final fret = Paint()
          ..shader = _metal(r)
          ..strokeWidth = max(1.2, s * .006)
          ..strokeCap = StrokeCap.round;
        final line = Paint()
          ..color = rlGoldLight.withValues(alpha: .55)
          ..strokeWidth = max(.6, s * .0025);
        for (var i = 0; i < rouletteWheel.length; i++) {
          final d = Offset(cos(-pi / 2 + i * seg), sin(-pi / 2 + i * seg));
          canvas.drawLine(d * r * pocketInner, d * r * (numberInner + .005), fret);
          canvas.drawLine(d * r * numberInner, d * r * numberOuter, line);
        }
        _ring(canvas, r * numberOuter, s * .008, r);
        _ring(canvas, r * numberInner, s * .007, r);
        // The cone: polished wood with a gold collar.
        canvas.drawCircle(
          Offset.zero,
          r * pocketInner,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0xFFE09A55), Color(0xFFA85E2A), Color(0xFF6A3412), Color(0xFF3A1A06)],
              stops: [0, .5, .85, 1],
            ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * pocketInner)),
        );
        // A soft sheen ring across the polished wood.
        canvas.drawCircle(
          Offset.zero,
          r * .37,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * .05
            ..color = const Color(0xFFFFD9A0).withValues(alpha: .07),
        );
        _ring(canvas, r * (pocketInner - .01), s * .012, r);
        _ring(canvas, r * .26, s * .006, r);
        for (var i = 0; i < rouletteWheel.length; i++) {
          final tp = TextPainter(
            text: TextSpan(
              text: '${rouletteWheel[i]}',
              style: TextStyle(
                color: Colors.white,
                fontSize: s * .034,
                fontWeight: FontWeight.w900,
                letterSpacing: -s * .001,
                shadows: [Shadow(color: Colors.black54, blurRadius: s * .006)],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          canvas.save();
          canvas.rotate((i + .5) * seg);
          canvas.translate(0, -r * (numberInner + numberOuter) / 2);
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
    canvas.drawCircle(
      c.translate(0, s * .02),
      r * .98,
      Paint()
        ..color = Colors.black.withValues(alpha: .6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .03),
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.drawPicture(_bowl(s));
    canvas.save();
    canvas.rotate(wheelAngle);
    canvas.drawPicture(_face(s));
    if (highlight != null && glow > 0) {
      final i = rouletteWheel.indexOf(highlight!);
      final seg = roulettePocketAngle;
      final from = -pi / 2 + i * seg;
      final band = Path()
        ..addArc(Rect.fromCircle(center: Offset.zero, radius: r * numberOuter), from, seg)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r * pocketInner), from + seg, -seg, false)
        ..close();
      canvas.drawPath(
        band,
        Paint()
          ..color = rlGoldLight.withValues(alpha: .45 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .006),
      );
      canvas.drawPath(
        band,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.5, s * .007)
          ..color = rlGoldLight.withValues(alpha: glow),
      );
    }
    canvas.restore();
    // The turning part sits below the track: shade its outer edge.
    canvas.drawCircle(
      Offset.zero,
      r * numberOuter,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: .35)],
          stops: const [.9, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * numberOuter)),
    );
    canvas.restore();
    if (showBall) {
      // On the track (lift 1) down to the pocket ring (lift 0).
      final br = r * (pocket + (track - pocket) * ballLift);
      final a = ballAngle - pi / 2;
      final p = c + Offset(cos(a), sin(a)) * br;
      final ball = s * .021;
      canvas.drawCircle(
        p.translate(ball * .35, ball * .5),
        ball * 1.05,
        Paint()
          ..color = Colors.black.withValues(alpha: .55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ball * .45),
      );
      canvas.drawCircle(
        p,
        ball,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-.35, -.4),
            radius: .9,
            colors: [Colors.white, Color(0xFFE9E9F0), Color(0xFF9C9CAB)],
            stops: [0, .45, 1],
          ).createShader(Rect.fromCircle(center: p, radius: ball)),
      );
      canvas.drawCircle(
        p.translate(-ball * .35, -ball * .4),
        ball * .28,
        Paint()..color = Colors.white.withValues(alpha: .9),
      );
    }
    // One fixed light from the top left, over everything.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.45, -.55),
          radius: .85,
          colors: [
            Colors.white.withValues(alpha: .16),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: .18),
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
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

// Painted stand-in for the centre turret.
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

import 'dart:math';
import 'package:flutter/material.dart';
import 'fruit_wheel_engine.dart';

/// Colours and artwork for عجلة الفواكه.
///
/// Generated artwork lives in assets/images/games/fruit_wheel/ (see
/// FRUIT_WHEEL_ARTWORK_BRIEF.md). Every image has a painted stand-in, so a
/// missing or late file never breaks the screen. The wheel itself is always
/// painted: segments, rim and bulbs must line up with the server's geometry.
const fwBlack = Color(0xFF080B15);
const fwPurpleDeep = Color(0xFF260D55);
const fwPurple = Color(0xFF55129A);
const fwPurpleLight = Color(0xFF8C3BE0);
const fwBlue = Color(0xFF087AD9);
const fwBlueBright = Color(0xFF19BFFF);
const fwGold = Color(0xFFFFD332);
const fwGoldDark = Color(0xFFA75F0D);
const fwPink = Color(0xFFF531B8);
const fwPinkDark = Color(0xFF9F147E);
const fwRed = Color(0xFFED303F);
const fwCream = Color(0xFFFFF3BF);
const fwMuted = Color(0xFFCAB8DF);
const fwGreen = Color(0xFF39D26B);

const _dir = 'assets/images/games/fruit_wheel';

/// A generated image, or its painted stand-in when the file is missing.
class FruitArt extends StatelessWidget {
  final String name;
  final double size;
  const FruitArt(this.name, {super.key, required this.size});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Image.asset(
          '$_dir/$name.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          cacheWidth: (size * 2.5).round().clamp(32, 512),
          errorBuilder: (_, __, ___) => painted(name, size),
        ),
      );

  static Widget painted(String name, double size) => switch (name) {
        'sevens' || 'capsule_sevens' => _capsuleOr(name, size, _Sevens(size)),
        _ => _capsuleOr(
            name,
            size,
            CustomPaint(size: Size.square(size), painter: _SymbolPainter(name)),
          ),
      };

  static Widget _capsuleOr(String name, double size, Widget inner) {
    if (!name.startsWith('capsule_')) return inner;
    final symbol = name.substring(8);
    return CustomPaint(
      size: Size.square(size),
      painter: const _CapsulePainter(),
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: size * .12),
          child: symbol == 'sevens'
              ? _Sevens(size * .55)
              : CustomPaint(
                  size: Size.square(size * .55),
                  painter: _SymbolPainter(symbol),
                ),
        ),
      ),
    );
  }
}

class _Sevens extends StatelessWidget {
  final double size;
  const _Sevens(this.size);
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: FittedBox(
          child: Stack(
            children: [
              Text(
                '777',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 6
                    ..color = fwRed,
                ),
              ),
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [fwCream, fwGold, fwGoldDark],
                ).createShader(r),
                child: const Text(
                  '777',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SymbolPainter extends CustomPainter {
  final String name;
  const _SymbolPainter(this.name);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    switch (name) {
      case 'watermelon':
        final rect = Rect.fromCircle(center: c.translate(0, -s * .1), radius: s * .42);
        canvas.drawArc(rect, 0, pi, true, Paint()..color = const Color(0xFF1E8A3A));
        canvas.drawArc(rect.deflate(s * .04), 0, pi, true, Paint()..color = const Color(0xFFE8F5C8));
        canvas.drawArc(
          rect.deflate(s * .07),
          0,
          pi,
          true,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(0, -.6),
              colors: [Color(0xFFFF6B7A), Color(0xFFE0203A)],
            ).createShader(rect),
        );
        final seed = Paint()..color = const Color(0xFF1A1A1A);
        for (final p in const [Offset(-.18, .05), Offset(0, .12), Offset(.18, .05), Offset(-.08, .22), Offset(.1, .22)]) {
          canvas.drawOval(
            Rect.fromCenter(center: c.translate(p.dx * s, p.dy * s - s * .08), width: s * .045, height: s * .07),
            seed,
          );
        }
      case 'plum':
        final body = Rect.fromCircle(center: c.translate(0, s * .05), radius: s * .36);
        canvas.drawOval(
          body,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(-.35, -.4),
              colors: [Color(0xFFD38BFF), Color(0xFF7A1FC2), Color(0xFF3B0A6B)],
              stops: [0, .55, 1],
            ).createShader(body),
        );
        final leaf = Path()
          ..moveTo(c.dx, c.dy - s * .28)
          ..quadraticBezierTo(c.dx + s * .3, c.dy - s * .48, c.dx + s * .34, c.dy - s * .3)
          ..quadraticBezierTo(c.dx + s * .14, c.dy - s * .2, c.dx, c.dy - s * .28);
        canvas.drawPath(leaf, Paint()..color = fwGreen);
        canvas.drawLine(
          c.translate(0, -s * .28),
          c.translate(-s * .03, -s * .42),
          Paint()
            ..color = const Color(0xFF6B3A12)
            ..strokeWidth = s * .035
            ..strokeCap = StrokeCap.round,
        );
      case 'bonus':
        final box = Rect.fromCenter(center: c.translate(0, s * .08), width: s * .74, height: s * .5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, Radius.circular(s * .08)),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [fwPurpleLight, fwPurpleDeep],
            ).createShader(box),
        );
        final band = Paint()..color = fwGold;
        canvas.drawRect(Rect.fromCenter(center: box.center, width: s * .12, height: box.height), band);
        canvas.drawRect(Rect.fromCenter(center: box.center.translate(0, -s * .08), width: box.width, height: s * .07), band);
        _star(canvas, c.translate(0, -s * .28), s * .16, Paint()..color = fwGold);
      case 'orb':
        final orb = Rect.fromCircle(center: c, radius: s * .42);
        canvas.drawOval(
          orb,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(-.35, -.4),
              colors: [fwCream, fwGold, fwGoldDark],
              stops: [0, .45, 1],
            ).createShader(orb),
        );
        _star(canvas, c, s * .18, Paint()..color = fwPurple);
      case 'crown':
        final p = Path()
          ..moveTo(s * .1, s * .75)
          ..lineTo(s * .15, s * .3)
          ..lineTo(s * .35, s * .52)
          ..lineTo(s * .5, s * .2)
          ..lineTo(s * .65, s * .52)
          ..lineTo(s * .85, s * .3)
          ..lineTo(s * .9, s * .75)
          ..close();
        canvas.drawPath(
          p,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [fwCream, fwGold, fwGoldDark],
            ).createShader(Offset.zero & size),
        );
        canvas.drawCircle(Offset(s * .5, s * .6), s * .07, Paint()..color = fwPink);
        canvas.drawCircle(Offset(s * .28, s * .64), s * .05, Paint()..color = fwBlueBright);
        canvas.drawCircle(Offset(s * .72, s * .64), s * .05, Paint()..color = fwBlueBright);
    }
  }

  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final rr = i.isEven ? r : r * .45;
      final p = c + Offset(cos(a) * rr, sin(a) * rr);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.name != name;
}

class _CapsulePainter extends CustomPainter {
  const _CapsulePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final glass = RRect.fromRectAndCorners(
      Rect.fromLTWH(s * .18, s * .08, s * .64, s * .72),
      topLeft: Radius.circular(s * .32),
      topRight: Radius.circular(s * .32),
      bottomLeft: Radius.circular(s * .08),
      bottomRight: Radius.circular(s * .08),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fwBlueBright.withValues(alpha: .55), fwBlue.withValues(alpha: .25)],
        ).createShader(glass.outerRect),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .02
        ..color = Colors.white.withValues(alpha: .6),
    );
    final base = Rect.fromLTWH(s * .12, s * .78, s * .76, s * .12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(base, Radius.circular(s * .05)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fwCream, fwGold, fwGoldDark],
        ).createShader(base),
    );
  }

  @override
  bool shouldRepaint(_CapsulePainter old) => false;
}

/// Segment fill per outcome: blues for fruit, pink for 777, purple for BONUS.
Color fruitSegmentColor(int index) => switch (fruitSegments[index]) {
      'sevens' => fwPink,
      'bonus' => const Color(0xFF8F2CC7),
      _ => index.isEven ? const Color(0xFF087EDB) : const Color(0xFF0B5FC4),
    };

/// The wheel face, rim and bulbs. [angle] turns only the face.
class FruitWheelPainter extends CustomPainter {
  final double angle;
  final int? highlight;
  final double glow;
  final double bulbPhase;
  const FruitWheelPainter({
    required this.angle,
    this.highlight,
    this.glow = 0,
    this.bulbPhase = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final outer = s / 2;
    final face = outer * .84;
    final seg = fruitSegmentAngle;

    // Halo behind the machine.
    canvas.drawCircle(
      c,
      outer,
      Paint()
        ..shader = RadialGradient(
          colors: [fwBlueBright.withValues(alpha: .35), fwPurple.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: outer)),
    );

    // Face.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final faceRect = Rect.fromCircle(center: Offset.zero, radius: face);
    for (var i = 0; i < fruitSegments.length; i++) {
      final start = -pi / 2 + i * seg;
      final base = fruitSegmentColor(i);
      canvas.drawArc(
        faceRect,
        start,
        seg,
        true,
        Paint()
          ..shader = RadialGradient(
            colors: [Color.lerp(base, Colors.white, .25)!, base, Color.lerp(base, Colors.black, .35)!],
            stops: const [0, .6, 1],
          ).createShader(faceRect),
      );
      if (i == highlight && glow > 0) {
        canvas.drawArc(
          faceRect,
          start,
          seg,
          true,
          Paint()..color = fwCream.withValues(alpha: .45 * glow),
        );
      }
    }
    final divider = Paint()
      ..color = fwGold
      ..strokeWidth = s * .008;
    for (var i = 0; i < fruitSegments.length; i++) {
      final a = -pi / 2 + i * seg;
      canvas.drawLine(Offset(cos(a), sin(a)) * face * .3, Offset(cos(a), sin(a)) * face, divider);
    }
    canvas.restore();

    // Inner purple ring around the hub.
    canvas.drawCircle(
      c,
      face * .3,
      Paint()
        ..color = fwPurpleDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .03,
    );

    // Gold rim: a thick ring with a bevel, then an inner hairline.
    final rimRect = Rect.fromCircle(center: c, radius: (outer + face) / 2);
    canvas.drawCircle(
      c,
      (outer + face) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outer - face
        ..shader = const SweepGradient(
          colors: [fwGold, fwCream, fwGoldDark, fwGold, fwCream, fwGoldDark, fwGold],
        ).createShader(rimRect),
    );
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .01
        ..color = fwGoldDark,
    );
    canvas.drawCircle(
      c,
      outer - s * .005,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .01
        ..color = fwGoldDark,
    );

    // Bulbs chase around the rim.
    const bulbs = 20;
    for (var i = 0; i < bulbs; i++) {
      final a = -pi / 2 + i * 2 * pi / bulbs + seg / 4;
      final p = c + Offset(cos(a), sin(a)) * ((outer + face) / 2);
      final lit = ((i + (bulbPhase * bulbs).floor()) % 2) == 0;
      canvas.drawCircle(
        p,
        s * .016,
        Paint()..color = lit ? fwCream : fwGoldDark.withValues(alpha: .8),
      );
      if (lit) {
        canvas.drawCircle(
          p,
          s * .03,
          Paint()
            ..color = fwGold.withValues(alpha: .35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(FruitWheelPainter old) =>
      old.angle != angle ||
      old.highlight != highlight ||
      old.glow != glow ||
      old.bulbPhase != bulbPhase;
}

/// Fixed gold pointer at the top of the wheel.
class FruitPointerPainter extends CustomPainter {
  final double glow;
  const FruitPointerPainter({this.glow = 0});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * .1, 0)
      ..lineTo(w * .9, 0)
      ..lineTo(w / 2, h)
      ..close();
    canvas.drawShadow(path, Colors.black, 4, false);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fwGold.withValues(alpha: .7 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fwCream, fwGold, fwGoldDark],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(Offset(w / 2, h * .3), w * .14, Paint()..color = fwPink);
    canvas.drawCircle(Offset(w * .46, h * .26), w * .05, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(FruitPointerPainter old) => old.glow != glow;
}

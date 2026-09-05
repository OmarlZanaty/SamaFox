import 'dart:math';

import 'package:flutter/material.dart';

/// Original artwork for القط الجشع (Greedy Cat), drawn in code.
///
/// Every mark here is vector-painted rather than shipped as a bitmap, for two
/// reasons: it stays crisp at any density, and it means the screen never shows
/// a grey placeholder while artwork is outstanding. When commissioned PNGs
/// arrive (see GREEDY_CAT_ARTWORK_BRIEF.md) drop them into
/// `assets/images/greedy/` under the filenames in [GreedyArt.assetFor] and
/// [FoodIcon] switches over automatically — the painted version stays as the
/// fallback for a missing or unreadable file.
///
/// All shapes are authored in a 100×100 box and scaled to fit, so a food icon
/// reads the same at 28px on a history token and at 90px on a wheel card.
///
/// ── On shading ──────────────────────────────────────────────
/// The first version of this file filled every shape with a flat `Color` and
/// relied on a thick outline to carry it. Flat fills plus outlines read as
/// clip-art, not as a game. Everything here is now built from four moves,
/// applied in this order, which is what gives objects their weight:
///
///   1. a gradient fill — [_sphere] for round forms, [_linear] for flat ones
///   2. [_occlude]      — contact shadow inside the lower edge
///   3. [_gloss]        — a broad specular sweep across the upper third
///   4. [_rim]          — a bright edge where the key light grazes the silhouette
///
/// The key light is consistently upper-LEFT, so shadows fall to the lower right
/// on every object in the game. Breaking that is what makes a set of icons look
/// like it came from three different artists.

// ── Palette ─────────────────────────────────────────────────
/// The style guide, as tokens. Nothing in this game should invent a colour.
class GreedyPalette {
  const GreedyPalette._();

  static const cyanTop = Color(0xFF3DD7F4);
  static const cyanBottom = Color(0xFF20BCEB);
  static const cyanDeep = Color(0xFF0E8FBE);
  static const patternBlue = Color(0xFF1599D0);

  static const purpleStrip = Color(0xFF24104B);
  static const purpleStripLight = Color(0xFF30135E);

  static const woodOutline = Color(0xFF5A2417);
  static const woodShadow = Color(0xFF7E3A1E);
  static const woodMid = Color(0xFFA94F28);
  static const woodHighlight = Color(0xFFD98A3C);
  static const woodLight = Color(0xFFEDB064);

  static const cream = Color(0xFFFFF3D2);
  static const creamDeep = Color(0xFFF3DCA8);
  static const warmPale = Color(0xFFFFE6A4);
  static const gold = Color(0xFFFFD83D);
  static const goldDeep = Color(0xFFD69A12);
  static const goldLight = Color(0xFFFFF3A8);
  static const orange = Color(0xFFF58B24);

  static const jackpotRed = Color(0xFFE93D4F);
  static const deepRed = Color(0xFFB51F3D);
  static const successGreen = Color(0xFF70E5A5);

  static const darkText = Color(0xFF402019);
  static const mutedText = Color(0xFF845E47);
  static const white = Color(0xFFFFFFFF);

  /// Mascot accents.
  static const lavender = Color(0xFFC9B6F5);
  static const lavenderDeep = Color(0xFF8E74D4);
  static const furShade = Color(0xFFE4DCF6);
  static const nosePink = Color(0xFFFF9BB3);
  static const blush = Color(0xFFFFB4C6);
}

/// Where a commissioned PNG would live for each drawable, if one exists.
class GreedyArt {
  const GreedyArt._();

  static const dir = 'assets/images/greedy';

  static String assetFor(String key) => '$dir/$key.png';
}

// ── Shading kit ─────────────────────────────────────────────
/// Radial gradient keyed to the upper-left light, for anything round.
Paint _sphere(Rect r, Color light, Color mid, Color dark) => Paint()
  ..shader = RadialGradient(
    center: const Alignment(-0.45, -0.55),
    radius: 1.05,
    colors: [light, mid, dark],
    stops: const [0.0, 0.52, 1.0],
  ).createShader(r);

/// Straight gradient for flat-ish forms — spokes, panels, leaves.
Paint _linear(
  Rect r,
  List<Color> colors, {
  Alignment begin = Alignment.topLeft,
  Alignment end = Alignment.bottomRight,
  List<double>? stops,
}) =>
    Paint()
      ..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops)
          .createShader(r);

/// Fill with a [Paint], then the warm outline that ties the whole set together.
void _paint(Canvas canvas, Path path, Paint fill, {double width = 4.5, Color? outline}) {
  canvas.drawPath(path, fill);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = outline ?? GreedyPalette.woodOutline,
  );
}

/// Flat-colour convenience, kept for the few places a gradient adds nothing.
void _shape(Canvas canvas, Path path, Color fill, {double width = 4.5, Color? outline}) =>
    _paint(canvas, path, Paint()..color = fill, width: width, outline: outline);

/// Darkens the inside of the lower edge, so a shape sits in its own shadow
/// instead of floating. This is the single biggest difference between "flat
/// vector" and "has volume".
void _occlude(Canvas canvas, Path path, Rect r, {double opacity = 0.26}) {
  canvas.save();
  canvas.clipPath(path);
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(r.center.dx + r.width * 0.08, r.bottom + r.height * 0.30),
      width: r.width * 1.5,
      height: r.height * 0.9,
    ),
    Paint()
      ..color = Colors.black.withOpacity(opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );
  canvas.restore();
}

/// The broad specular sweep across the upper third.
void _gloss(Canvas canvas, Path path, Rect r, {double opacity = 0.6}) {
  canvas.save();
  canvas.clipPath(path);
  final glossRect = Rect.fromLTWH(
    r.left + r.width * 0.06,
    r.top + r.height * 0.02,
    r.width * 0.62,
    r.height * 0.5,
  );
  canvas.drawOval(
    glossRect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withOpacity(opacity), Colors.white.withOpacity(0)],
      ).createShader(glossRect),
  );
  canvas.restore();
}

/// A bright grazing edge along the lit side of the silhouette.
void _rim(Canvas canvas, Path path, {Color color = Colors.white, double opacity = 0.5,
    double width = 3, Offset shift = const Offset(-2.5, -2.5)}) {
  canvas.save();
  canvas.clipPath(path);
  canvas.drawPath(
    path.shift(shift),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color.withOpacity(opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
  );
  canvas.restore();
}

/// The small hard catchlight that sells a glossy surface.
void _glint(Canvas canvas, Offset centre, double rx, double ry, {double opacity = 0.85}) {
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(-0.5);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
    Paint()..color = Colors.white.withOpacity(opacity),
  );
  canvas.restore();
}

/// A soft drop shadow cast onto whatever is behind the object.
void _cast(Canvas canvas, Path path, {double opacity = 0.22, Offset offset = const Offset(3, 5)}) {
  canvas.drawPath(
    path.shift(offset),
    Paint()
      ..color = Colors.black.withOpacity(opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
}

Path _leaf(Offset from, Offset tip, double bulge) {
  final path = Path()..moveTo(from.dx, from.dy);
  final mid = Offset((from.dx + tip.dx) / 2, (from.dy + tip.dy) / 2);
  final normal = Offset(-(tip.dy - from.dy), tip.dx - from.dx);
  final len = normal.distance == 0 ? 1 : normal.distance;
  final push = Offset(normal.dx / len * bulge, normal.dy / len * bulge);
  path
    ..quadraticBezierTo(mid.dx + push.dx, mid.dy + push.dy, tip.dx, tip.dy)
    ..quadraticBezierTo(mid.dx - push.dx, mid.dy - push.dy, from.dx, from.dy)
    ..close();
  return path;
}

/// A shaded leaf with a centre vein — used by corn, carrot and the tomato crown.
void _shadedLeaf(Canvas canvas, Offset from, Offset tip, double bulge, Color light, Color dark,
    {double width = 3.2}) {
  final path = _leaf(from, tip, bulge);
  final r = path.getBounds();
  _paint(canvas, path, _linear(r, [light, dark]), width: width);
  canvas.save();
  canvas.clipPath(path);
  canvas.drawLine(
    from,
    tip,
    Paint()
      ..strokeWidth = 1.6
      ..color = dark.withOpacity(0.55)
      ..strokeCap = StrokeCap.round,
  );
  canvas.restore();
}

// ── Food icons ──────────────────────────────────────────────
/// Draws one of the eight foods, preferring a commissioned PNG when present.
class FoodIcon extends StatelessWidget {
  const FoodIcon(this.symbolKey, {super.key, this.size = 64});

  final String symbolKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        GreedyArt.assetFor(symbolKey),
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        // No artwork on disk is the normal case today, not an error state —
        // fall through to the painted original rather than a broken-image box.
        errorBuilder: (_, __, ___) => CustomPaint(
          size: Size.square(size),
          painter: FoodIconPainter(symbolKey),
        ),
      ),
    );
  }
}

class FoodIconPainter extends CustomPainter {
  const FoodIconPainter(this.symbolKey);

  final String symbolKey;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    switch (symbolKey) {
      case 'corn':
        _corn(canvas);
        break;
      case 'chicken':
        _chicken(canvas);
        break;
      case 'tomato':
        _tomato(canvas);
        break;
      case 'goat':
        _goat(canvas);
        break;
      case 'pepper':
        _pepper(canvas);
        break;
      case 'fish':
        _fish(canvas);
        break;
      case 'carrot':
        _carrot(canvas);
        break;
      case 'shrimp':
        _shrimp(canvas);
        break;
      default:
        _tomato(canvas);
    }
    canvas.restore();
  }

  // ذرة — corn cob in a split green husk.
  void _corn(Canvas canvas) {
    _shadedLeaf(canvas, const Offset(50, 93), const Offset(15, 42), 13,
        const Color(0xFF7ED267), const Color(0xFF3E8C31));
    _shadedLeaf(canvas, const Offset(50, 93), const Offset(85, 42), -13,
        const Color(0xFF8FE076), const Color(0xFF4C9E3C));

    final r = const Rect.fromLTWH(33, 11, 34, 76);
    final cob = Path()
      ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(17)));
    // Cylindrical, not spherical: light band down the left, falling away right.
    _paint(
      canvas,
      cob,
      _linear(r, const [Color(0xFFFFE885), Color(0xFFFFD335), Color(0xFFC98A0C)],
          begin: Alignment.centerLeft, end: Alignment.centerRight, stops: [0.0, 0.45, 1.0]),
    );

    canvas.save();
    canvas.clipPath(cob);
    // Each kernel gets its own tiny sphere so the surface reads as beaded.
    for (var row = 0; row < 10; row++) {
      final y = 16.0 + row * 7.8;
      final offset = row.isEven ? 0.0 : 4.6;
      for (var col = 0; col < 4; col++) {
        final x = 34.5 + offset + col * 9;
        final kr = Rect.fromCenter(center: Offset(x, y), width: 8.2, height: 7.6);
        canvas.drawOval(
          kr,
          _sphere(kr, const Color(0xFFFFF0A8), const Color(0xFFF5C63A), const Color(0xFFB87A08)),
        );
      }
    }
    canvas.restore();

    _occlude(canvas, cob, r, opacity: 0.18);
    _gloss(canvas, cob, r, opacity: 0.35);
    _rim(canvas, cob, opacity: 0.55);
  }

  // دجاجة — white hen with a red comb.
  void _chicken(Canvas canvas) {
    final bodyR = const Rect.fromLTWH(19, 37, 62, 52);
    final body = Path()..addOval(bodyR);
    _cast(canvas, body, opacity: 0.16);
    _paint(canvas, body,
        _sphere(bodyR, Colors.white, const Color(0xFFF6EFE4), const Color(0xFFCFC0AE)));
    _occlude(canvas, body, bodyR, opacity: 0.20);

    final tail = Path()
      ..moveTo(24, 60)
      ..quadraticBezierTo(4, 47, 11, 31)
      ..quadraticBezierTo(21, 43, 32, 50)
      ..close();
    _paint(canvas, tail,
        _linear(tail.getBounds(), const [Color(0xFFFFFFFF), Color(0xFFDCCDBA)]), width: 3.8);

    final headR = const Rect.fromLTWH(48, 12, 35, 35);
    final head = Path()..addOval(headR);
    _paint(canvas, head,
        _sphere(headR, Colors.white, const Color(0xFFF8F2E8), const Color(0xFFD5C7B5)));

    final comb = Path()
      ..moveTo(56, 17)
      ..quadraticBezierTo(58, 4, 66, 11)
      ..quadraticBezierTo(72, 0, 76, 13)
      ..quadraticBezierTo(80, 6, 80, 19)
      ..close();
    _paint(canvas, comb,
        _linear(comb.getBounds(), const [Color(0xFFFF6B76), Color(0xFFC3162C)]), width: 3.6);
    _rim(canvas, comb, opacity: 0.4, width: 2);

    final beak = Path()
      ..moveTo(80, 31)
      ..lineTo(95, 36)
      ..lineTo(80, 41)
      ..close();
    _paint(canvas, beak,
        _linear(beak.getBounds(), const [Color(0xFFFFC24D), Color(0xFFDE7A0E)]), width: 3.2);

    final wattle = Path()..addOval(const Rect.fromLTWH(72, 40, 10, 14));
    _paint(canvas, wattle,
        _linear(wattle.getBounds(), const [Color(0xFFFF5F6C), Color(0xFFB8142A)]), width: 3.2);

    final wing = Path()
      ..moveTo(32, 55)
      ..quadraticBezierTo(52, 48, 61, 66)
      ..quadraticBezierTo(45, 77, 32, 55)
      ..close();
    _paint(canvas, wing,
        _linear(wing.getBounds(), const [Color(0xFFFDF7EE), Color(0xFFD9CAB6)]), width: 3.4);

    _eye(canvas, const Offset(68, 27), 4.6);
    _gloss(canvas, head, headR, opacity: 0.5);
    _gloss(canvas, body, bodyR, opacity: 0.35);
    _rim(canvas, body, opacity: 0.6);
  }

  // طماطم — glossy tomato with a green crown.
  void _tomato(Canvas canvas) {
    final r = const Rect.fromLTWH(13, 25, 74, 67);
    final body = Path()..addOval(r);
    _cast(canvas, body);
    _paint(canvas, body,
        _sphere(r, const Color(0xFFFF8A7A), const Color(0xFFE93C3C), const Color(0xFF9E1420)));

    // Two soft lobe creases, clipped in — a tomato is not a perfect ball.
    canvas.save();
    canvas.clipPath(body);
    final crease = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..color = const Color(0xFF9E1420).withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawArc(const Rect.fromLTWH(20, 28, 44, 62), -pi / 2.4, pi * 0.9, false, crease);
    canvas.drawArc(const Rect.fromLTWH(46, 30, 42, 60), -pi / 2.9, pi * 0.8, false, crease);
    canvas.restore();

    _occlude(canvas, body, r);
    _gloss(canvas, body, r, opacity: 0.55);
    _rim(canvas, body, opacity: 0.45);

    for (var i = 0; i < 5; i++) {
      final a = -pi / 2 + (i - 2) * 0.62;
      final tip = Offset(50 + cos(a) * 31, 33 + sin(a) * 25);
      _shadedLeaf(canvas, const Offset(50, 31), tip, 7,
          const Color(0xFF6FCB53), const Color(0xFF2F7A28));
    }
    final stemR = const Rect.fromLTWH(46, 7, 9, 23);
    final stem = Path()
      ..addRRect(RRect.fromRectAndRadius(stemR, const Radius.circular(4.5)));
    _paint(canvas, stem,
        _linear(stemR, const [Color(0xFF5FBC4A), Color(0xFF2C7024)],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
        width: 3.2);

    _glint(canvas, const Offset(33, 45), 6.5, 12, opacity: 0.9);
    _glint(canvas, const Offset(27, 62), 2.6, 4.5, opacity: 0.5);
  }

  // ماعز — brown-and-white goat head.
  void _goat(Canvas canvas) {
    // Horns, with ridges, behind the head.
    for (final side in [-1, 1]) {
      final horn = _leaf(Offset(50 + side * 16, 31), Offset(50 + side * 35, 3), 7.0 * side);
      _paint(canvas, horn,
          _linear(horn.getBounds(), const [Color(0xFFE0C89A), Color(0xFF9A7638)]), width: 3.4);
      canvas.save();
      canvas.clipPath(horn);
      for (var i = 1; i < 5; i++) {
        final t = i / 5;
        canvas.drawLine(
          Offset(50 + side * (16 + 19 * t) - side * 5, 31 - 28 * t - 2),
          Offset(50 + side * (16 + 19 * t) + side * 4, 31 - 28 * t + 4),
          Paint()
            ..strokeWidth = 1.8
            ..color = const Color(0xFF8A6730).withOpacity(0.5)
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.restore();
    }

    for (final side in [-1, 1]) {
      final ear = _leaf(Offset(50 + side * 22, 45), Offset(50 + side * 46, 52), 9.0 * side);
      _paint(canvas, ear,
          _linear(ear.getBounds(), const [Color(0xFFA97A4E), Color(0xFF6B4526)]), width: 3.4);
    }

    final headR = const Rect.fromLTWH(23, 18, 54, 53);
    final head = Path()..addOval(headR);
    _cast(canvas, head, opacity: 0.18);
    _paint(canvas, head,
        _sphere(headR, const Color(0xFFC9915E), const Color(0xFFA06B41), const Color(0xFF6B4223)));
    _occlude(canvas, head, headR, opacity: 0.22);

    final muzzleR = const Rect.fromLTWH(32, 49, 36, 35);
    final muzzle = Path()..addOval(muzzleR);
    _paint(canvas, muzzle,
        _sphere(muzzleR, Colors.white, const Color(0xFFF3E3CC), const Color(0xFFCBB394)),
        width: 3.6);
    _gloss(canvas, muzzle, muzzleR, opacity: 0.4);

    _eye(canvas, const Offset(39, 41), 4.8);
    _eye(canvas, const Offset(61, 41), 4.8);

    final nostril = Paint()..color = const Color(0xFF7A4A2E).withOpacity(0.85);
    canvas.drawOval(Rect.fromCenter(center: const Offset(45, 60), width: 6, height: 4.4), nostril);
    canvas.drawOval(Rect.fromCenter(center: const Offset(55, 60), width: 6, height: 4.4), nostril);
    canvas.drawArc(const Rect.fromLTWH(43, 62, 14, 10), 0.2, pi - 0.4, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF8A5A38));

    _shadedLeaf(canvas, const Offset(50, 79), const Offset(50, 97), 7,
        Colors.white, const Color(0xFFCBB394));
    _gloss(canvas, head, headR, opacity: 0.3);
    _rim(canvas, head, opacity: 0.4);
  }

  // فلفل — a long curved chilli.
  //
  // Deliberately NOT a round bell pepper: tomato is already a red circle, and
  // at 40px on a wheel card the two were the same picture. A tapering curve is
  // unmistakable at any size, which matters because they are separate bets.
  void _pepper(Canvas canvas) {
    final body = Path()
      ..moveTo(62, 25)
      ..cubicTo(85, 40, 83, 73, 58, 89)
      ..cubicTo(43, 97, 26, 89, 28, 78)
      ..cubicTo(30, 69, 44, 76, 52, 70)
      ..cubicTo(67, 59, 69, 41, 54, 29)
      ..close();
    final r = body.getBounds();
    _cast(canvas, body);
    _paint(
      canvas,
      body,
      _linear(r, const [Color(0xFFFF7566), Color(0xFFE0342F), Color(0xFF8E101C)],
          begin: Alignment.topLeft, end: Alignment.bottomRight, stops: [0.0, 0.45, 1.0]),
    );

    // A chilli's signature: one long unbroken specular strip down the curve.
    canvas.save();
    canvas.clipPath(body);
    final strip = Path()
      ..moveTo(59, 34)
      ..cubicTo(72, 47, 70, 66, 56, 79)
      ..cubicTo(66, 64, 67, 49, 55, 38)
      ..close();
    canvas.drawPath(
      strip,
      Paint()
        ..color = Colors.white.withOpacity(0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
    );
    canvas.restore();
    _rim(canvas, body, opacity: 0.4);

    final cap = Path()
      ..moveTo(47, 25)
      ..quadraticBezierTo(60, 14, 73, 25)
      ..quadraticBezierTo(60, 34, 47, 25)
      ..close();
    _paint(canvas, cap,
        _linear(cap.getBounds(), const [Color(0xFF7ED267), Color(0xFF3E8C31)]), width: 3.2);
    canvas.drawPath(
      Path()
        ..moveTo(60, 21)
        ..quadraticBezierTo(56, 6, 41, 7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF3E8C31),
    );
  }

  // سمكة — blue body, orange fins.
  void _fish(Canvas canvas) {
    final tail = Path()
      ..moveTo(21, 50)
      ..lineTo(3, 28)
      ..lineTo(8, 50)
      ..lineTo(3, 72)
      ..close();
    _paint(canvas, tail,
        _linear(tail.getBounds(), const [Color(0xFFFFB067), Color(0xFFE06A10)]), width: 3.6);

    final fin = Path()
      ..moveTo(46, 33)
      ..quadraticBezierTo(50, 11, 67, 25)
      ..close();
    _paint(canvas, fin,
        _linear(fin.getBounds(), const [Color(0xFFFFB067), Color(0xFFE06A10)]), width: 3.6);
    final lower = Path()
      ..moveTo(44, 69)
      ..quadraticBezierTo(44, 86, 61, 75)
      ..close();
    _paint(canvas, lower,
        _linear(lower.getBounds(), const [Color(0xFFFFA050), Color(0xFFCF5D08)]), width: 3.6);

    final body = Path()
      ..moveTo(17, 50)
      ..cubicTo(30, 20, 75, 18, 92, 50)
      ..cubicTo(75, 82, 30, 80, 17, 50)
      ..close();
    final r = body.getBounds();
    _cast(canvas, body, opacity: 0.18);
    _paint(canvas, body,
        _linear(r, const [Color(0xFF7FD4FF), Color(0xFF2E9BE0), Color(0xFF11548F)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.0, 0.45, 1.0]));

    canvas.save();
    canvas.clipPath(body);
    // Lighter belly, then a few scale arcs.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(54, 64), width: 62, height: 26),
      Paint()
        ..color = const Color(0xFFBDEBFF).withOpacity(0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    final scale = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = const Color(0xFF11548F).withOpacity(0.35);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(40.0 + i * 13, 38.0 + j * 12), width: 14, height: 14),
          -pi * 0.85, pi * 0.7, false, scale,
        );
      }
    }
    canvas.restore();

    _occlude(canvas, body, r, opacity: 0.2);
    _gloss(canvas, body, r, opacity: 0.45);
    _rim(canvas, body, opacity: 0.5);

    // Gill line.
    canvas.drawArc(const Rect.fromLTWH(58, 32, 22, 36), -pi * 0.55, pi * 1.1, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF11548F).withOpacity(0.5));
    _eye(canvas, const Offset(77, 43), 5.4);
  }

  // جزرة — carrot with leaf tops.
  void _carrot(Canvas canvas) {
    for (var i = -1; i <= 1; i++) {
      _shadedLeaf(canvas, const Offset(50, 30), Offset(50 + i * 25, 4 + i.abs() * 5), 8,
          const Color(0xFF8FE076), const Color(0xFF3E8C31));
    }

    final root = Path()
      ..moveTo(32, 29)
      ..lineTo(68, 29)
      ..quadraticBezierTo(60, 76, 50, 95)
      ..quadraticBezierTo(40, 76, 32, 29)
      ..close();
    final r = root.getBounds();
    _cast(canvas, root, opacity: 0.18);
    _paint(
      canvas,
      root,
      _linear(r, const [Color(0xFFFFB566), Color(0xFFF58B24), Color(0xFFB9540A)],
          begin: Alignment.centerLeft, end: Alignment.centerRight, stops: [0.0, 0.42, 1.0]),
    );

    canvas.save();
    canvas.clipPath(root);
    for (var i = 0; i < 5; i++) {
      final y = 37.0 + i * 11;
      final w = 16 - i * 2.2;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(50, y), width: w * 2, height: 9),
        pi * 1.12, pi * 0.76, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF9E4708).withOpacity(0.45),
      );
    }
    canvas.restore();
    _gloss(canvas, root, r, opacity: 0.42);
    _rim(canvas, root, opacity: 0.5);
  }

  // روبيان — curled shrimp.
  void _shrimp(Canvas canvas) {
    final tail = Path()
      ..moveTo(34, 78)
      ..lineTo(11, 65)
      ..lineTo(20, 80)
      ..lineTo(9, 91)
      ..close();
    _paint(canvas, tail,
        _linear(tail.getBounds(), const [Color(0xFFFFA98A), Color(0xFFE05A2A)]), width: 3.2);

    // The body is one thick stroked arc, widened to a shell. An outline that
    // doubled back on itself read as a fish with antennae.
    final spine = Path()
      ..moveTo(36, 76)
      ..cubicTo(20, 52, 34, 23, 62, 23)
      ..cubicTo(85, 23, 91, 46, 74, 56);
    canvas.drawPath(
      spine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 31
        ..strokeCap = StrokeCap.round
        ..color = GreedyPalette.woodOutline,
    );
    canvas.drawPath(
      spine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 25
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFA07A), Color(0xFFFF7043), Color(0xFFC8410F)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(const Rect.fromLTWH(10, 15, 85, 70)),
    );
    // A highlight running along the outer edge of the curl.
    canvas.drawPath(
      spine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    const centre = Offset(54, 52);
    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB63B0C).withOpacity(0.75);
    for (var i = 1; i <= 4; i++) {
      final a = pi * 0.95 - i * 0.34;
      canvas.drawLine(centre + Offset(cos(a), sin(a)) * 12,
          centre + Offset(cos(a), sin(a)) * 25, rib);
    }

    final leg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = GreedyPalette.woodOutline;
    for (var i = 0; i < 4; i++) {
      final a = pi * 0.86 - i * 0.26;
      canvas.drawLine(centre + Offset(cos(a), sin(a)) * 11,
          centre + Offset(cos(a), sin(a)) * 3, leg);
    }

    canvas.drawLine(const Offset(78, 40), const Offset(97, 25), leg);
    canvas.drawLine(const Offset(76, 36), const Offset(93, 12), leg);
    _eye(canvas, const Offset(72, 36), 5.2);
  }

  /// A glossy eye: dark iris with a radial falloff, a big catchlight and a
  /// small bounce light opposite it.
  void _eye(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r + 1.2, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r,
      _sphere(Rect.fromCircle(center: c, radius: r), const Color(0xFF4A3A63),
          const Color(0xFF241733), const Color(0xFF0D0616)),
    );
    canvas.drawCircle(c.translate(-r * 0.32, -r * 0.36), r * 0.34,
        Paint()..color = Colors.white.withOpacity(0.95));
    canvas.drawCircle(c.translate(r * 0.34, r * 0.36), r * 0.16,
        Paint()..color = Colors.white.withOpacity(0.55));
  }

  @override
  bool shouldRepaint(FoodIconPainter old) => old.symbolKey != symbolKey;
}

// ── Cat mascot ──────────────────────────────────────────────
enum CatMood { idle, alert, win, lose }

/// The mascot at the centre of the wheel.
///
/// Everything is driven by two continuous inputs — [breath] for the idle sway
/// and [blink] for the eyelids — plus a discrete [mood], so the cat can react
/// to a phase change without a state machine of its own.
class CatMascotPainter extends CustomPainter {
  const CatMascotPainter({
    required this.mood,
    required this.breath,
    required this.blink,
  });

  /// 0..1 loop.
  final double breath;

  /// 0 = open, 1 = fully closed.
  final double blink;

  final CatMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    final bob = sin(breath * 2 * pi) * (mood == CatMood.alert ? 3.2 : 1.6);
    final squash = 1 + sin(breath * 2 * pi) * 0.018;
    canvas.translate(0, bob);

    // Contact shadow keeps the mascot sitting on the hub rather than floating.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(50, 95 - bob * 0.4), width: 58, height: 12),
      Paint()
        ..color = const Color(0xFF2A1A45).withOpacity(0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.save();
    canvas.translate(50, 62);
    canvas.scale(1 / squash, squash);
    canvas.translate(-50, -62);

    _paws(canvas);
    _silhouette(canvas);
    _face(canvas);

    canvas.restore();
    canvas.restore();
  }

  /// Head, body and ears as ONE outlined shape.
  ///
  /// They used to be three separate outlined paths, which left a hard dark seam
  /// running behind the head where the body's stroke showed through. Unioning
  /// the silhouette and stroking it once is what makes a character read as a
  /// single creature rather than assembled parts.
  Path _bodyPath() => Path()
    ..moveTo(29, 93)
    ..cubicTo(25, 76, 32, 60, 50, 60)
    ..cubicTo(68, 60, 75, 76, 71, 93)
    ..close();

  /// A deliberately large head over a small body — the chibi proportion that
  /// makes a mascot read as cute rather than as a scaled-down adult animal.
  Rect get _headRect => const Rect.fromLTWH(15, 7, 70, 63);

  Path _earPath(int side, {bool inner = false}) {
    final twitch = side == 1 ? sin(breath * 4 * pi) * 1.4 : 0.0;
    // Wide base, short reach: long narrow ears made the mascot read as a rabbit.
    final base = Offset(50 + side * 13, 22.0);
    final tipX = 50 + side * 36.0;
    if (!inner) return _leaf(base, Offset(tipX, 3 + twitch), 15 * side.toDouble());
    return _leaf(
      Offset(base.dx + side * 3, base.dy - 1),
      Offset(tipX - side * 7, 11 + twitch),
      8 * side.toDouble(),
    );
  }

  void _silhouette(Canvas canvas) {
    var shape = Path.combine(PathOperation.union, _bodyPath(), Path()..addOval(_headRect));
    for (final side in [-1, 1]) {
      shape = Path.combine(PathOperation.union, shape, _earPath(side));
    }

    final r = shape.getBounds();
    // A gentle diagonal wash, not a radial one. A sphere gradient centred on
    // the head puts the whole body at its dark stop, which turned the cat
    // lavender from the neck down.
    _paint(
      canvas,
      shape,
      _linear(r, const [Colors.white, Color(0xFFFCFBFF), Color(0xFFEDE8F8)],
          stops: [0.0, 0.55, 1.0]),
      width: 3.8,
    );

    canvas.save();
    canvas.clipPath(shape);
    // Lavender chest marking, soft-edged so it reads as fur not a decal.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 88), width: 30, height: 24),
      Paint()
        ..color = GreedyPalette.lavender.withOpacity(0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // The shadow the head casts on the chest — this replaces the old hard seam.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 70), width: 56, height: 20),
      Paint()
        ..color = GreedyPalette.lavenderDeep.withOpacity(0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.restore();

    // Ear interiors sit on top of the unified shape.
    for (final side in [-1, 1]) {
      final inner = _earPath(side, inner: true);
      _paint(canvas, inner,
          _linear(inner.getBounds(),
              const [Color(0xFFDCCDFA), GreedyPalette.lavenderDeep]),
          width: 2.2, outline: GreedyPalette.lavenderDeep);
    }

    _rim(canvas, shape, opacity: 0.8, shift: const Offset(-2.5, -3));
  }

  void _paws(Canvas canvas) {
    // Enough to read as a cheer, not so much that the paws end up beside the
    // ears — the head got bigger, so the old lift put them over the face.
    final lift = mood == CatMood.win ? 13.0 : 0.0;
    final droop = mood == CatMood.lose ? 4.0 : 0.0;
    for (final side in [-1, 1]) {
      final x = 50 + side * 23.0;
      final y = 88 - lift + droop;
      final pr = Rect.fromCenter(center: Offset(x, y), width: 23, height: 18);
      final paw = Path()..addOval(pr);
      _paint(canvas, paw,
          _sphere(pr, Colors.white, const Color(0xFFF6F2FD), GreedyPalette.furShade), width: 3.4);
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(Offset(x + i * 5.0, y - 4), 1.9,
            Paint()..color = GreedyPalette.lavenderDeep.withOpacity(0.45));
      }
    }
  }

  void _face(Canvas canvas) {
    // Blush.
    for (final side in [-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(50 + side * 26.0, 47), width: 16, height: 9),
        Paint()
          ..color = GreedyPalette.blush.withOpacity(mood == CatMood.win ? 0.65 : 0.42)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
    }

    _eyes(canvas);

    final nose = Path()
      ..moveTo(45.5, 45)
      ..lineTo(54.5, 45)
      ..lineTo(50, 50.5)
      ..close();
    _paint(canvas, nose,
        _linear(nose.getBounds(), const [Color(0xFFFFC0D0), Color(0xFFE8718F)]), width: 2.2);

    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = GreedyPalette.woodOutline;
    if (mood == CatMood.win) {
      final open = Path()..addOval(const Rect.fromLTWH(43, 50, 14, 13));
      _paint(canvas, open,
          _linear(const Rect.fromLTWH(43, 50, 14, 13),
              const [Color(0xFFF4899C), Color(0xFFB93F58)]),
          width: 2.4);
      canvas.drawOval(Rect.fromCenter(center: const Offset(50, 60), width: 8, height: 5),
          Paint()..color = const Color(0xFFFF9BB3));
    } else if (mood == CatMood.lose) {
      canvas.drawArc(const Rect.fromLTWH(42, 54, 16, 12), pi * 0.15, pi * 0.7, false, mouth);
    } else {
      canvas.drawArc(const Rect.fromLTWH(42, 46, 8, 10), 0, pi * 0.8, false, mouth);
      canvas.drawArc(const Rect.fromLTWH(50, 46, 8, 10), pi * 0.2, pi * 0.8, false, mouth);
    }

    final whisker = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = GreedyPalette.mutedText.withOpacity(0.55);
    for (final side in [-1, 1]) {
      for (var i = 0; i < 2; i++) {
        final y = 45.0 + i * 6;
        canvas.drawLine(Offset(50 + side * 13.0, y),
            Offset(50 + side * 37.0, y - 3 + i * 5.0), whisker);
      }
    }

    if (mood == CatMood.win) _sparkles(canvas);
  }

  void _eyes(Canvas canvas) {
    for (final side in [-1, 1]) {
      final centre = Offset(50 + side * 14.5, 37);
      final wide = mood == CatMood.alert || mood == CatMood.win;
      final h = (wide ? 24.0 : 21.0) * (1 - blink);

      if (h < 2.5) {
        canvas.drawArc(
          Rect.fromCenter(center: centre, width: 18, height: 12),
          pi, pi, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = GreedyPalette.darkText,
        );
        continue;
      }

      final eyeR = Rect.fromCenter(center: centre, width: 19, height: h);
      final eye = Path()..addOval(eyeR);
      // A violet iris that falls off to near-black at the rim.
      _paint(canvas, eye,
          _sphere(eyeR, const Color(0xFF7E63B8), const Color(0xFF3B2358),
              const Color(0xFF120A22)),
          width: 2.4);

      if (mood == CatMood.lose) {
        canvas.save();
        canvas.clipPath(eye);
        canvas.drawOval(
          Rect.fromCenter(center: centre.translate(0, -h * 0.45), width: 20, height: h * 0.5),
          Paint()..color = GreedyPalette.furShade,
        );
        canvas.restore();
      }
      canvas.drawCircle(centre.translate(3.2, -h * 0.20), h * 0.20,
          Paint()..color = Colors.white.withOpacity(0.95));
      canvas.drawCircle(centre.translate(-3.6, h * 0.22), h * 0.10,
          Paint()..color = Colors.white.withOpacity(0.6));
    }
  }

  void _sparkles(Canvas canvas) {
    for (var i = 0; i < 5; i++) {
      final a = breath * 2 * pi + i * pi / 2.5;
      final centre = Offset(50 + cos(a) * 41, 36 + sin(a) * 27);
      final r = 3.4 + sin(breath * 2 * pi + i) * 1.3;
      final star = Path()
        ..moveTo(centre.dx, centre.dy - r)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx + r, centre.dy)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx, centre.dy + r)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx - r, centre.dy)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx, centre.dy - r)
        ..close();
      canvas.drawPath(star,
          Paint()..color = GreedyPalette.goldLight.withOpacity(0.9)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8));
      canvas.drawPath(star, Paint()..color = GreedyPalette.gold);
    }
  }

  @override
  bool shouldRepaint(CatMascotPainter old) =>
      old.breath != breath || old.blink != blink || old.mood != mood;
}

// ── Wheel chrome ────────────────────────────────────────────
/// The wooden machine the food cards sit on: eight spokes, a studded hub and
/// the two support legs that plant it on the dashboard.
///
/// The cards themselves are laid out as widgets on top of this, so the painter
/// only draws what sits *behind* them.
class WheelFramePainter extends CustomPainter {
  const WheelFramePainter({
    required this.count,
    required this.cardRadius,
    required this.hubRadius,
    required this.glow,
    this.rotation = 0,
    this.winningIndex,
    this.winnerPulse = 0,
  });

  final int count;

  /// Wheel rotation in turns. The cards orbit with the spokes, but the card
  /// widgets themselves are never rotated — Arabic labels and food icons stay
  /// upright through the whole spin.
  final double rotation;

  /// Distance from centre to each card's centre, in pixels.
  final double cardRadius;
  final double hubRadius;

  /// 0..1 ambient light-chase phase around the hub studs.
  final double glow;

  final int? winningIndex;

  /// 0..1, drives the winning spoke's highlight after the wheel stops.
  final double winnerPulse;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);

    _legs(canvas, size, centre);

    for (var i = 0; i < count; i++) {
      final a = _angleFor(i);
      final dir = Offset(cos(a), sin(a));
      final outer = centre + dir * cardRadius;
      final isWinner = winningIndex == i && winnerPulse > 0;

      // Cast shadow under the spoke.
      canvas.drawLine(
        centre + const Offset(2, 5),
        outer + const Offset(2, 5),
        Paint()
          ..strokeWidth = hubRadius * 0.32
          ..strokeCap = StrokeCap.round
          ..color = Colors.black.withOpacity(0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawLine(
        centre, outer,
        Paint()
          ..strokeWidth = hubRadius * 0.34
          ..strokeCap = StrokeCap.round
          ..color = GreedyPalette.woodOutline,
      );
      // Rounded timber: light along the upper edge, dark along the lower.
      final band = Rect.fromPoints(
        centre - Offset(dir.dy, -dir.dx) * hubRadius * 0.14,
        outer + Offset(dir.dy, -dir.dx) * hubRadius * 0.14,
      );
      canvas.drawLine(
        centre, outer,
        Paint()
          ..strokeWidth = hubRadius * 0.25
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isWinner
                ? [GreedyPalette.goldLight, GreedyPalette.gold, GreedyPalette.goldDeep]
                : const [
                    GreedyPalette.woodLight,
                    GreedyPalette.woodMid,
                    GreedyPalette.woodShadow,
                  ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(band.inflate(hubRadius * 0.1)),
      );
      // Grain.
      canvas.save();
      canvas.drawLine(
        centre + dir * (hubRadius * 0.75),
        outer,
        Paint()
          ..strokeWidth = hubRadius * 0.045
          ..strokeCap = StrokeCap.round
          ..color = GreedyPalette.woodLight.withOpacity(0.5),
      );
      canvas.restore();

      for (final t in const [0.45, 0.75]) {
        final p = centre + dir * (cardRadius * t);
        canvas.drawCircle(p, hubRadius * 0.078, Paint()..color = GreedyPalette.woodOutline);
        canvas.drawCircle(
          p,
          hubRadius * 0.056,
          _sphere(Rect.fromCircle(center: p, radius: hubRadius * 0.056),
              GreedyPalette.goldLight, GreedyPalette.gold, GreedyPalette.goldDeep),
        );
      }
    }

    _hub(canvas, centre);
  }

  /// Card 0 sits at 12 o'clock when [rotation] is zero, and the ring runs
  /// clockwise — matching the server's symbol order exactly.
  double _angleFor(int i) => angleFor(i, count, rotation);

  /// Shared with the screen, so the cards it lays out sit exactly on the spokes
  /// this painter draws. One definition, two consumers.
  static double angleFor(int i, int count, double rotation) =>
      -pi / 2 + i * 2 * pi / count + rotation * 2 * pi;

  /// The rotation that brings card [index] to rest under the 12 o'clock
  /// pointer. Whole turns are added by the caller for the run-up.
  static double landingFor(int index, int count) => -index / count;

  void _legs(Canvas canvas, Size size, Offset centre) {
    for (final side in [-1, 1]) {
      final top = centre.translate(side * hubRadius * 0.55, hubRadius * 0.4);
      final bottom = Offset(centre.dx + side * hubRadius * 1.5, size.height);
      final leg = Path()
        ..moveTo(top.dx - hubRadius * 0.16, top.dy)
        ..lineTo(top.dx + hubRadius * 0.16, top.dy)
        ..lineTo(bottom.dx + hubRadius * 0.22, bottom.dy)
        ..lineTo(bottom.dx - hubRadius * 0.22, bottom.dy)
        ..close();
      _cast(canvas, leg, opacity: 0.18, offset: const Offset(3, 4));
      _paint(
        canvas,
        leg,
        _linear(leg.getBounds(),
            side < 0
                ? const [GreedyPalette.woodLight, GreedyPalette.woodShadow]
                : const [GreedyPalette.woodMid, GreedyPalette.woodShadow],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
        width: hubRadius * 0.06,
      );
    }
  }

  void _hub(Canvas canvas, Offset centre) {
    final outerR = Rect.fromCircle(center: centre, radius: hubRadius);
    canvas.drawCircle(centre.translate(2, 5), hubRadius,
        Paint()
          ..color = Colors.black.withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(centre, hubRadius, Paint()..color = GreedyPalette.woodOutline);

    // Metallic gold ring: dark, bright, dark across its width.
    canvas.drawCircle(
      centre,
      hubRadius * 0.95,
      Paint()
        ..shader = SweepGradient(
          colors: const [
            GreedyPalette.goldDeep, GreedyPalette.goldLight, GreedyPalette.gold,
            GreedyPalette.goldDeep, GreedyPalette.goldLight, GreedyPalette.goldDeep,
          ],
          stops: const [0.0, 0.18, 0.42, 0.63, 0.84, 1.0],
          transform: GradientRotation(-pi / 2),
        ).createShader(outerR),
    );

    canvas.drawCircle(
      centre,
      hubRadius * 0.85,
      _sphere(Rect.fromCircle(center: centre, radius: hubRadius * 0.85),
          GreedyPalette.woodLight, GreedyPalette.woodMid, GreedyPalette.woodShadow),
    );

    const bulbs = 16;
    for (var i = 0; i < bulbs; i++) {
      final a = -pi / 2 + i * 2 * pi / bulbs;
      final p = centre + Offset(cos(a), sin(a)) * (hubRadius * 0.90);
      // A travelling wave rather than a blink, so nothing flashes.
      final t = ((glow * bulbs) - i) % bulbs / bulbs;
      final lit = (cos(t * 2 * pi) + 1) / 2;
      if (lit > 0.55) {
        canvas.drawCircle(p, hubRadius * 0.085,
            Paint()
              ..color = GreedyPalette.goldLight.withOpacity((lit - 0.55) * 1.2)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }
      canvas.drawCircle(p, hubRadius * 0.052, Paint()..color = GreedyPalette.woodOutline);
      canvas.drawCircle(
        p,
        hubRadius * 0.038,
        Paint()..color = Color.lerp(GreedyPalette.warmPale, GreedyPalette.goldLight, lit)!,
      );
    }

    // Cream face with an inner bevel.
    final faceR = Rect.fromCircle(center: centre, radius: hubRadius * 0.74);
    canvas.drawCircle(centre, hubRadius * 0.74,
        _sphere(faceR, Colors.white, GreedyPalette.cream, GreedyPalette.creamDeep));
    canvas.drawCircle(
      centre,
      hubRadius * 0.74,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hubRadius * 0.05
        ..color = GreedyPalette.woodOutline,
    );
  }

  @override
  bool shouldRepaint(WheelFramePainter old) =>
      old.rotation != rotation ||
      old.glow != glow ||
      old.winningIndex != winningIndex ||
      old.winnerPulse != winnerPulse ||
      old.cardRadius != cardRadius ||
      old.hubRadius != hubRadius;
}

/// The fixed winner pointer at 12 o'clock.
class PointerPainter extends CustomPainter {
  const PointerPainter({this.pulse = 0});

  /// 0..1, swells the pointer as the wheel comes to rest.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w / 2, h)
      ..lineTo(w * 0.14, h * 0.18)
      ..quadraticBezierTo(w / 2, -h * 0.12, w * 0.86, h * 0.18)
      ..close();
    _cast(canvas, path, opacity: 0.28, offset: const Offset(2, 3));
    if (pulse > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = GreedyPalette.gold.withOpacity(pulse * 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    _paint(
      canvas,
      path,
      _linear(path.getBounds(), [
        Color.lerp(const Color(0xFFFF7A85), GreedyPalette.goldLight, pulse)!,
        Color.lerp(GreedyPalette.deepRed, GreedyPalette.goldDeep, pulse)!,
      ]),
      width: w * 0.09,
    );
    canvas.drawCircle(
      Offset(w / 2, h * 0.3),
      w * 0.12,
      _sphere(Rect.fromCircle(center: Offset(w / 2, h * 0.3), radius: w * 0.12),
          Colors.white, GreedyPalette.warmPale, GreedyPalette.goldDeep),
    );
  }

  @override
  bool shouldRepaint(PointerPainter old) => old.pulse != pulse;
}

// ── UI furniture ────────────────────────────────────────────
/// The gold coin with a rainbow crown, used everywhere a coin value appears.
class CoinEmblem extends StatelessWidget {
  const CoinEmblem({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    // Edge, then face, so the coin reads as a minted disc with thickness.
    canvas.drawCircle(const Offset(50, 54), 46, Paint()..color = const Color(0xFF9C6608));
    final faceR = Rect.fromCircle(center: const Offset(50, 49), radius: 45);
    canvas.drawCircle(const Offset(50, 49), 45,
        _sphere(faceR, GreedyPalette.goldLight, GreedyPalette.gold, GreedyPalette.goldDeep));
    canvas.drawCircle(const Offset(50, 49), 45,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF9C6608));
    canvas.drawCircle(const Offset(50, 49), 35,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFFB87A08).withOpacity(0.55));

    final crown = Path()
      ..moveTo(30, 61)
      ..lineTo(34, 34)
      ..lineTo(43, 48)
      ..lineTo(50, 29)
      ..lineTo(57, 48)
      ..lineTo(66, 34)
      ..lineTo(70, 61)
      ..close();
    _paint(canvas, crown,
        _linear(crown.getBounds(), const [Color(0xFFFFB65C), Color(0xFFD86A08)]), width: 3.2);

    _glint(canvas, const Offset(33, 27), 7, 11, opacity: 0.85);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoinPainter old) => false;
}

/// Open treasure chest for the LuckyDrop teaser and the milestone markers.
class TreasureChest extends StatelessWidget {
  const TreasureChest({super.key, this.size = 44, this.opened = true, this.locked = false});

  final double size;
  final bool opened;
  final bool locked;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _ChestPainter(opened: opened, locked: locked),
      );
}

class _ChestPainter extends CustomPainter {
  const _ChestPainter({required this.opened, required this.locked});

  final bool opened;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    final wood = locked
        ? const [Color(0xFF9E8B7C), Color(0xFF6A5A4D)]
        : const [GreedyPalette.woodLight, GreedyPalette.woodShadow];
    final band = locked
        ? const [Color(0xFFC0B2A2), Color(0xFF8C7C6C)]
        : const [GreedyPalette.goldLight, GreedyPalette.goldDeep];

    // Paint order matters: an open chest is lid FIRST (thrown back at the top),
    // then the treasure, then the body front.
    if (opened && !locked) {
      final lid = Path()
        ..moveTo(16, 34)
        ..quadraticBezierTo(50, 2, 84, 34)
        ..quadraticBezierTo(50, 20, 16, 34)
        ..close();
      _paint(canvas, lid, _linear(lid.getBounds(), wood), width: 4);

      // Warm bounce light from all that gold.
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(50, 48), width: 74, height: 26),
        Paint()
          ..color = GreedyPalette.gold.withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );

      for (var i = 0; i < 6; i++) {
        final x = 24.0 + i * 10.5;
        final y = 50.0 - (i.isEven ? 7 : 0);
        final cr = Rect.fromCircle(center: Offset(x, y), radius: 7);
        canvas.drawCircle(Offset(x, y + 1.5), 7, Paint()..color = const Color(0xFF9C6608));
        canvas.drawCircle(Offset(x, y), 6.4,
            _sphere(cr, GreedyPalette.goldLight, GreedyPalette.gold, GreedyPalette.goldDeep));
      }
      for (final gem in const [
        [22.0, 44.0, 0xFF9BE6FF, 0xFF2196C4],
        [76.0, 46.0, 0xFFFFA8C8, 0xFFD1417F],
        [50.0, 38.0, 0xFFC0F58F, 0xFF54A32B],
      ]) {
        final p = Offset(gem[0] as double, gem[1] as double);
        final path = Path()
          ..moveTo(p.dx, p.dy - 6.5)
          ..lineTo(p.dx + 5.5, p.dy)
          ..lineTo(p.dx, p.dy + 6.5)
          ..lineTo(p.dx - 5.5, p.dy)
          ..close();
        _paint(canvas, path,
            _linear(path.getBounds(), [Color(gem[2] as int), Color(gem[3] as int)]), width: 2.2);
      }
    } else {
      final lid = Path()
        ..moveTo(14, 54)
        ..quadraticBezierTo(50, 22, 86, 54)
        ..close();
      _paint(canvas, lid, _linear(lid.getBounds(), wood), width: 4);
    }

    final bodyR = const Rect.fromLTWH(14, 52, 72, 36);
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(bodyR, const Radius.circular(6)));
    _paint(canvas, body,
        _linear(bodyR, wood, begin: Alignment.topCenter, end: Alignment.bottomCenter), width: 4);

    final bandPaint = _linear(const Rect.fromLTWH(14, 56, 72, 8), band,
        begin: Alignment.topCenter, end: Alignment.bottomCenter);
    canvas.drawRect(const Rect.fromLTWH(14, 56, 72, 8), bandPaint);
    canvas.drawRect(const Rect.fromLTWH(44, 56, 12, 32),
        _linear(const Rect.fromLTWH(44, 56, 12, 32), band,
            begin: Alignment.centerLeft, end: Alignment.centerRight));

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(42, 62, 16, 16), const Radius.circular(3)),
      _linear(const Rect.fromLTWH(42, 62, 16, 16), band),
    );
    canvas.drawCircle(const Offset(50, 70), 3.4, Paint()..color = GreedyPalette.woodOutline);
    _rim(canvas, body, opacity: 0.35);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChestPainter old) => old.opened != opened || old.locked != locked;
}

/// The cyan field behind the whole screen: a lit gradient, soft bokeh, a doodle
/// layer and a vignette that pushes the corners back so the wheel sits forward.
class BackgroundPatternPainter extends CustomPainter {
  const BackgroundPatternPainter({required this.drift});

  /// 0..1, slides the field so the background is never quite static.
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.15, -0.55),
          radius: 1.25,
          colors: [Color(0xFF7FE9FF), GreedyPalette.cyanTop, GreedyPalette.cyanBottom],
          stops: [0.0, 0.42, 1.0],
        ).createShader(rect),
    );

    // Soft out-of-focus discs, drifting.
    final bokeh = Paint()..color = Colors.white.withOpacity(0.07);
    for (var i = 0; i < 9; i++) {
      final t = (drift + i / 9) % 1.0;
      final x = size.width * ((i * 0.37) % 1.0);
      final y = size.height * (1.05 - t * 1.15);
      canvas.drawCircle(Offset(x, y), 26.0 + (i % 4) * 13, bokeh);
    }

    final paint = Paint()..color = GreedyPalette.patternBlue.withOpacity(0.20);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = GreedyPalette.patternBlue.withOpacity(0.20);
    const cell = 84.0;
    final offset = drift * cell;
    for (var y = -cell; y < size.height + cell; y += cell) {
      for (var x = -cell; x < size.width + cell; x += cell) {
        final px = x + ((y / cell).floor().isEven ? cell / 2 : 0) + offset * 0.3;
        final py = y + offset;
        final kind = ((x / cell).floor() + (y / cell).floor()) % 3;
        if (kind == 0) {
          canvas.drawPath(_leaf(Offset(px, py), Offset(px + 16, py - 14), 6), paint);
        } else if (kind == 1) {
          const r = 7.0;
          final star = Path()
            ..moveTo(px, py - r)
            ..quadraticBezierTo(px, py, px + r, py)
            ..quadraticBezierTo(px, py, px, py + r)
            ..quadraticBezierTo(px, py, px - r, py)
            ..quadraticBezierTo(px, py, px, py - r)
            ..close();
          canvas.drawPath(star, paint);
        } else {
          canvas.drawArc(Rect.fromCircle(center: Offset(px, py), radius: 11),
              pi * 0.2, pi * 0.9, false, stroke);
        }
      }
    }

    // Vignette.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            Colors.transparent,
            GreedyPalette.cyanDeep.withOpacity(0.32),
          ],
          stops: const [0.62, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(BackgroundPatternPainter old) => old.drift != drift;
}

/// Confetti for a winning result. Deterministic per [seed] so a rebuild during
/// the burst does not reshuffle the pieces mid-flight.
class ConfettiPainter extends CustomPainter {
  const ConfettiPainter({required this.progress, required this.seed});

  final double progress;
  final int seed;

  static const _colors = [
    GreedyPalette.gold,
    GreedyPalette.jackpotRed,
    GreedyPalette.successGreen,
    GreedyPalette.lavender,
    GreedyPalette.orange,
    Color(0xFF6BD5FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    for (var i = 0; i < 54; i++) {
      final x = rng.nextDouble() * size.width;
      final delay = rng.nextDouble() * 0.35;
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final drift = (rng.nextDouble() - 0.5) * 90;
      final spin = rng.nextDouble() * 12;
      final flip = rng.nextDouble() * 14;
      final y = -30 + t * (size.height + 60);
      final w = 7 + rng.nextDouble() * 7;
      final colour = _colors[i % _colors.length];

      canvas.save();
      canvas.translate(x + drift * t, y);
      canvas.rotate(spin * t);
      // Foil flip: the strip narrows as it turns edge-on, and darkens on the
      // back face. Static rectangles read as falling paper, not foil.
      final face = cos(flip * t);
      canvas.scale(1, face.abs().clamp(0.15, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.6),
          const Radius.circular(1.4),
        ),
        Paint()
          ..color = (face >= 0 ? colour : Color.lerp(colour, Colors.black, 0.35)!)
              .withOpacity((1 - t * 0.65).clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.progress != progress || old.seed != seed;
}

/// The round wooden plaque a food icon sits on.
///
/// This used to be two nested `Container`s with flat fills, which is why the
/// wheel read as paper cut-outs: a real plaque has a turned wooden rim catching
/// the light on one side, a dished face that darkens where the rim overhangs
/// it, and a glaze across the top.
class PlaquePainter extends CustomPainter {
  const PlaquePainter({this.winner = false, this.pulse = 0});

  /// Draws the gold winning treatment instead of the wooden one.
  final bool winner;

  /// 0..1, brightens the winner's rim as it pulses.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final full = Rect.fromCircle(center: c, radius: r);

    // Contact shadow.
    canvas.drawCircle(
      c.translate(0, r * 0.09),
      r * 0.97,
      Paint()
        ..color = Colors.black.withOpacity(winner ? 0.30 : 0.24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.13),
    );

    if (winner) {
      canvas.drawCircle(
        c,
        r * 1.02,
        Paint()
          ..color = GreedyPalette.gold.withOpacity(0.35 + pulse * 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.28),
      );
    }

    // Outer rim: a turned ring, lit from the upper left.
    canvas.drawCircle(c, r, Paint()..color = GreedyPalette.woodOutline);
    canvas.drawCircle(
      c,
      r * 0.955,
      Paint()
        ..shader = SweepGradient(
          colors: winner
              ? const [
                  GreedyPalette.goldDeep, GreedyPalette.goldLight, GreedyPalette.gold,
                  GreedyPalette.goldDeep, GreedyPalette.goldLight, GreedyPalette.goldDeep,
                ]
              : const [
                  GreedyPalette.woodShadow, GreedyPalette.woodLight, GreedyPalette.woodHighlight,
                  GreedyPalette.woodShadow, GreedyPalette.woodLight, GreedyPalette.woodShadow,
                ],
          stops: const [0.0, 0.18, 0.42, 0.63, 0.84, 1.0],
          transform: const GradientRotation(-pi * 0.75),
        ).createShader(full),
    );

    // Inner rim.
    canvas.drawCircle(c, r * 0.80, Paint()..color = GreedyPalette.woodOutline);
    canvas.drawCircle(
      c,
      r * 0.775,
      _sphere(Rect.fromCircle(center: c, radius: r * 0.775),
          GreedyPalette.warmPale, GreedyPalette.creamDeep, const Color(0xFFD9BC7E)),
    );

    // Dished face.
    final faceR = Rect.fromCircle(center: c, radius: r * 0.70);
    final face = Path()..addOval(faceR);
    canvas.drawPath(
      face,
      _sphere(faceR, Colors.white, GreedyPalette.cream, GreedyPalette.creamDeep),
    );
    // The rim overhangs the face, so the top of the dish is in shadow.
    canvas.save();
    canvas.clipPath(face);
    canvas.drawCircle(
      c.translate(0, -r * 0.20),
      r * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = const Color(0xFF9E7B3E).withOpacity(0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.10),
    );
    canvas.restore();

    // Glaze.
    _gloss(canvas, face, faceR, opacity: 0.5);
  }

  @override
  bool shouldRepaint(PlaquePainter old) => old.winner != winner || old.pulse != pulse;
}

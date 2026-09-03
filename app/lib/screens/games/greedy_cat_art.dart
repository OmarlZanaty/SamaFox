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

// ── Palette ─────────────────────────────────────────────────
/// The style guide, as tokens. Nothing in this game should invent a colour.
class GreedyPalette {
  const GreedyPalette._();

  static const cyanTop = Color(0xFF3DD7F4);
  static const cyanBottom = Color(0xFF20BCEB);
  static const patternBlue = Color(0xFF1599D0);

  static const purpleStrip = Color(0xFF24104B);
  static const purpleStripLight = Color(0xFF30135E);

  static const woodOutline = Color(0xFF6D2D1E);
  static const woodMid = Color(0xFFA94F28);
  static const woodHighlight = Color(0xFFD98A3C);

  static const cream = Color(0xFFFFF3D2);
  static const warmPale = Color(0xFFFFE6A4);
  static const gold = Color(0xFFFFD83D);
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
  static const nosePink = Color(0xFFFF9BB3);
}

/// Where a commissioned PNG would live for each drawable, if one exists.
class GreedyArt {
  const GreedyArt._();

  static const dir = 'assets/images/greedy';

  static String assetFor(String key) => '$dir/$key.png';
}

// ── Shared painting helpers ─────────────────────────────────
/// Fill + thick warm outline, the single move that gives everything here its
/// storybook edge. [width] is in the 100-unit authoring space.
void _shape(Canvas canvas, Path path, Color fill, {double width = 4.5, Color? outline}) {
  canvas.drawPath(path, Paint()..color = fill);
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

/// The candy glint every solid object gets, so nothing reads as flat vector.
void _glint(Canvas canvas, Offset centre, double rx, double ry, {double opacity = 0.55}) {
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(-0.5);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
    Paint()..color = Colors.white.withOpacity(opacity),
  );
  canvas.restore();
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
    _shape(canvas, _leaf(const Offset(50, 92), const Offset(18, 44), 13), const Color(0xFF57B14A));
    _shape(canvas, _leaf(const Offset(50, 92), const Offset(82, 44), -13), const Color(0xFF6FC95B));

    final cob = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(33, 12, 34, 74),
        const Radius.circular(17),
      ));
    _shape(canvas, cob, GreedyPalette.gold);

    // Kernels: staggered rows, clipped to the cob so the grid never leaks past
    // the outline.
    canvas.save();
    canvas.clipPath(cob);
    final kernel = Paint()..color = const Color(0xFFE8A81C);
    for (var row = 0; row < 9; row++) {
      final y = 18.0 + row * 8;
      final offset = row.isEven ? 0.0 : 5.0;
      for (var col = 0; col < 4; col++) {
        final x = 35.0 + offset + col * 9;
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 6.4, height: 6.0), kernel);
      }
    }
    canvas.restore();
    _glint(canvas, const Offset(41, 28), 3.6, 10, opacity: 0.5);
  }

  // دجاجة — white hen with a red comb.
  void _chicken(Canvas canvas) {
    final body = Path()..addOval(const Rect.fromLTWH(20, 38, 60, 50));
    _shape(canvas, body, GreedyPalette.white);

    final tail = Path()
      ..moveTo(24, 60)
      ..quadraticBezierTo(6, 48, 12, 34)
      ..quadraticBezierTo(22, 44, 32, 50)
      ..close();
    _shape(canvas, tail, const Color(0xFFF2E6D8));

    final head = Path()..addOval(const Rect.fromLTWH(48, 14, 34, 34));
    _shape(canvas, head, GreedyPalette.white);

    // Comb — three soft lobes.
    final comb = Path()
      ..moveTo(56, 18)
      ..quadraticBezierTo(58, 6, 66, 12)
      ..quadraticBezierTo(72, 2, 76, 14)
      ..quadraticBezierTo(80, 8, 80, 20)
      ..close();
    _shape(canvas, comb, GreedyPalette.jackpotRed, width: 4);

    final beak = Path()
      ..moveTo(80, 32)
      ..lineTo(94, 36)
      ..lineTo(80, 41)
      ..close();
    _shape(canvas, beak, GreedyPalette.orange, width: 3.5);

    // Wattle.
    final wattle = Path()..addOval(const Rect.fromLTWH(72, 40, 10, 13));
    _shape(canvas, wattle, GreedyPalette.jackpotRed, width: 3.5);

    final wing = Path()
      ..moveTo(34, 56)
      ..quadraticBezierTo(52, 50, 60, 66)
      ..quadraticBezierTo(46, 76, 34, 56)
      ..close();
    _shape(canvas, wing, const Color(0xFFF0E2D0), width: 3.5);

    canvas.drawCircle(const Offset(68, 28), 4.2, Paint()..color = GreedyPalette.darkText);
    canvas.drawCircle(const Offset(69.4, 26.6), 1.5, Paint()..color = Colors.white);
    _glint(canvas, const Offset(36, 52), 4, 9, opacity: 0.6);
  }

  // طماطم — glossy tomato with a green crown.
  void _tomato(Canvas canvas) {
    final body = Path()..addOval(const Rect.fromLTWH(14, 26, 72, 66));
    _shape(canvas, body, const Color(0xFFEE4B4B));

    canvas.drawPath(
      Path()..addOval(const Rect.fromLTWH(22, 36, 40, 40)),
      Paint()..color = const Color(0xFFFF6B6B).withOpacity(0.75),
    );

    // Crown: five leaflets around the stem.
    for (var i = 0; i < 5; i++) {
      final a = -pi / 2 + (i - 2) * 0.62;
      final tip = Offset(50 + cos(a) * 30, 34 + sin(a) * 24);
      _shape(canvas, _leaf(const Offset(50, 32), tip, 7), const Color(0xFF4FA83E), width: 3.4);
    }
    final stem = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(46, 8, 9, 22),
        const Radius.circular(4.5),
      ));
    _shape(canvas, stem, const Color(0xFF3E8C31), width: 3.4);
    _glint(canvas, const Offset(33, 48), 6, 12);
  }

  // ماعز — brown-and-white goat head.
  void _goat(Canvas canvas) {
    // Horns first, so the head overlaps their roots. Darker than the cream
    // muzzle on purpose — at cream-on-cream they vanished against the card.
    _shape(canvas, _leaf(const Offset(34, 30), const Offset(16, 4), 7),
        const Color(0xFFB08A52), width: 3.6);
    _shape(canvas, _leaf(const Offset(66, 30), const Offset(84, 4), -7),
        const Color(0xFFB08A52), width: 3.6);

    _shape(canvas, _leaf(const Offset(28, 44), const Offset(6, 50), 9), const Color(0xFF8A5A38), width: 3.6);
    _shape(canvas, _leaf(const Offset(72, 44), const Offset(94, 50), -9), const Color(0xFF8A5A38), width: 3.6);

    final head = Path()..addOval(const Rect.fromLTWH(24, 20, 52, 50));
    _shape(canvas, head, const Color(0xFFA06B41));

    // Cream muzzle.
    final muzzle = Path()..addOval(const Rect.fromLTWH(33, 50, 34, 34));
    _shape(canvas, muzzle, const Color(0xFFF6E7D2), width: 4);

    canvas.drawCircle(const Offset(39, 42), 4.4, Paint()..color = GreedyPalette.darkText);
    canvas.drawCircle(const Offset(61, 42), 4.4, Paint()..color = GreedyPalette.darkText);
    canvas.drawCircle(const Offset(40.4, 40.5), 1.6, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(62.4, 40.5), 1.6, Paint()..color = Colors.white);

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 60), width: 11, height: 8),
      Paint()..color = const Color(0xFF7A4A2E),
    );
    // Beard.
    _shape(canvas, _leaf(const Offset(50, 80), const Offset(50, 96), 7),
        const Color(0xFFF6E7D2), width: 3.4);
  }

  // فلفل — a long curved chilli.
  //
  // Deliberately NOT a round bell pepper: tomato is already a red circle, and
  // at 40px on a wheel card the two were the same picture. A tapering curve is
  // unmistakable at any size, which matters because they are separate bets.
  void _pepper(Canvas canvas) {
    final body = Path()
      ..moveTo(62, 26)
      ..cubicTo(84, 40, 82, 72, 58, 88)
      ..cubicTo(44, 96, 28, 88, 30, 78)
      ..cubicTo(32, 70, 44, 76, 52, 70)
      ..cubicTo(66, 60, 68, 42, 54, 30)
      ..close();
    _shape(canvas, body, const Color(0xFFE0342F));

    // Highlight running the length of the curve.
    canvas.drawPath(
      Path()
        ..moveTo(60, 36)
        ..cubicTo(72, 48, 70, 66, 56, 78)
        ..cubicTo(66, 64, 66, 50, 55, 40)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.55),
    );

    // Green cap and a stem hooking back over the shoulder.
    final cap = Path()
      ..moveTo(48, 26)
      ..quadraticBezierTo(60, 16, 72, 26)
      ..quadraticBezierTo(60, 34, 48, 26)
      ..close();
    _shape(canvas, cap, const Color(0xFF5FBC4A), width: 3.4);
    canvas.drawPath(
      Path()
        ..moveTo(60, 22)
        ..quadraticBezierTo(56, 8, 42, 8),
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
      ..moveTo(20, 50)
      ..lineTo(4, 30)
      ..lineTo(8, 50)
      ..lineTo(4, 70)
      ..close();
    _shape(canvas, tail, GreedyPalette.orange, width: 3.8);

    final fin = Path()
      ..moveTo(46, 34)
      ..quadraticBezierTo(50, 14, 66, 26)
      ..close();
    _shape(canvas, fin, GreedyPalette.orange, width: 3.8);
    final lowerFin = Path()
      ..moveTo(44, 68)
      ..quadraticBezierTo(44, 84, 60, 74)
      ..close();
    _shape(canvas, lowerFin, GreedyPalette.orange, width: 3.8);

    final body = Path()
      ..moveTo(18, 50)
      ..cubicTo(30, 22, 74, 20, 90, 50)
      ..cubicTo(74, 80, 30, 78, 18, 50)
      ..close();
    _shape(canvas, body, const Color(0xFF2E9BE0));

    canvas.save();
    canvas.clipPath(body);
    final stripe = Paint()..color = const Color(0xFF1B7BC0).withOpacity(0.55);
    for (var i = 0; i < 3; i++) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(40.0 + i * 15, 50), width: 8, height: 46),
        stripe,
      );
    }
    canvas.restore();

    canvas.drawCircle(const Offset(76, 44), 6.4, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(77, 44), 3.4, Paint()..color = GreedyPalette.darkText);
    canvas.drawCircle(const Offset(78.4, 42.4), 1.4, Paint()..color = Colors.white);
    _glint(canvas, const Offset(44, 36), 5, 8, opacity: 0.45);
  }

  // جزرة — carrot with leaf tops.
  void _carrot(Canvas canvas) {
    for (var i = -1; i <= 1; i++) {
      _shape(
        canvas,
        _leaf(const Offset(50, 30), Offset(50 + i * 24, 6 + i.abs() * 5), 8),
        i == 0 ? const Color(0xFF57B14A) : const Color(0xFF6FC95B),
        width: 3.4,
      );
    }

    final root = Path()
      ..moveTo(32, 30)
      ..lineTo(68, 30)
      ..quadraticBezierTo(60, 76, 50, 94)
      ..quadraticBezierTo(40, 76, 32, 30)
      ..close();
    _shape(canvas, root, GreedyPalette.orange);

    // Growth notches.
    final notch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD86F14);
    canvas.save();
    canvas.clipPath(root);
    for (var i = 0; i < 4; i++) {
      final y = 40.0 + i * 12;
      canvas.drawLine(Offset(36 + i * 2.0, y), Offset(50 + i * 1.0, y + 4), notch);
    }
    canvas.restore();
    _glint(canvas, const Offset(41, 46), 3.2, 10, opacity: 0.5);
  }

  // روبيان — curled shrimp.
  //
  // Built as one thick C-curve rather than an outline that doubles back on
  // itself: the earlier self-intersecting path read as a fish with antennae.
  void _shrimp(Canvas canvas) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = GreedyPalette.woodOutline;

    // Fan tail, at the lower-left end of the curl.
    final tail = Path()
      ..moveTo(34, 78)
      ..lineTo(12, 66)
      ..lineTo(20, 80)
      ..lineTo(10, 90)
      ..close();
    _shape(canvas, tail, const Color(0xFFFF8A5C), width: 3.4);

    // The body: a stroked arc, widened to a tapering shell.
    final spine = Path()
      ..moveTo(36, 76)
      ..cubicTo(20, 52, 34, 24, 62, 24)
      ..cubicTo(84, 24, 90, 46, 74, 56);
    canvas.drawPath(
      spine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30
        ..strokeCap = StrokeCap.round
        ..color = GreedyPalette.woodOutline,
    );
    canvas.drawPath(
      spine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF7043),
    );

    // Segment ribs across the curl.
    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD84A22);
    for (var i = 1; i <= 4; i++) {
      final a = pi * 0.95 - i * 0.34;
      final centre = const Offset(54, 52);
      canvas.drawLine(
        centre + Offset(cos(a), sin(a)) * 12,
        centre + Offset(cos(a), sin(a)) * 25,
        rib,
      );
    }

    // Legs along the inner edge.
    for (var i = 0; i < 4; i++) {
      final a = pi * 0.86 - i * 0.26;
      final centre = const Offset(54, 52);
      canvas.drawLine(
        centre + Offset(cos(a), sin(a)) * 11,
        centre + Offset(cos(a), sin(a)) * 3,
        outline,
      );
    }

    // Head end: eye and antennae.
    canvas.drawLine(const Offset(78, 40), const Offset(96, 26), outline);
    canvas.drawLine(const Offset(76, 36), const Offset(92, 14), outline);
    canvas.drawCircle(const Offset(72, 36), 5.0, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(72, 36), 5.0, outline);
    canvas.drawCircle(const Offset(72.6, 36), 2.6, Paint()..color = GreedyPalette.darkText);
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
      Rect.fromCenter(center: Offset(50, 92 - bob * 0.4), width: 54, height: 11),
      Paint()..color = const Color(0xFF2A1A45).withOpacity(0.22),
    );

    canvas.save();
    canvas.translate(50, 62);
    canvas.scale(1 / squash, squash);
    canvas.translate(-50, -62);

    _paws(canvas);
    _body(canvas);
    _head(canvas);

    canvas.restore();
    canvas.restore();
  }

  void _body(Canvas canvas) {
    final body = Path()
      ..moveTo(28, 90)
      ..cubicTo(26, 62, 34, 50, 50, 50)
      ..cubicTo(66, 50, 74, 62, 72, 90)
      ..close();
    _shape(canvas, body, GreedyPalette.white, width: 3.6);

    // Lavender chest marking.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 84), width: 30, height: 30),
      Paint()..color = GreedyPalette.lavender.withOpacity(0.45),
    );
    canvas.restore();
  }

  void _paws(Canvas canvas) {
    // Raised in celebration, resting otherwise.
    final lift = mood == CatMood.win ? 26.0 : 0.0;
    final droop = mood == CatMood.lose ? 4.0 : 0.0;
    for (final side in [-1, 1]) {
      final x = 50 + side * 22.0;
      final y = 84 - lift + droop;
      final paw = Path()..addOval(Rect.fromCenter(center: Offset(x, y), width: 21, height: 17));
      _shape(canvas, paw, GreedyPalette.white, width: 3.4);
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(
          Offset(x + i * 5.0, y - 4),
          1.7,
          Paint()..color = GreedyPalette.lavenderDeep.withOpacity(0.5),
        );
      }
    }
  }

  void _head(Canvas canvas) {
    // Ears — outer white, lavender inner.
    for (final side in [-1, 1]) {
      final base = Offset(50 + side * 17, 30.0);
      final tipX = 50 + side * 30.0;
      // A small twitch on the idle loop, on one ear only, reads as alive
      // without looking mechanical.
      final twitch = side == 1 ? sin(breath * 4 * pi) * 1.6 : 0.0;
      _shape(
        canvas,
        _leaf(base, Offset(tipX, 6 + twitch), 9 * side.toDouble()),
        GreedyPalette.white,
        width: 3.4,
      );
      _shape(
        canvas,
        _leaf(
          Offset(base.dx + side * 2, base.dy - 2),
          Offset(tipX - side * 5, 12 + twitch),
          5 * side.toDouble(),
        ),
        GreedyPalette.lavender,
        width: 2.2,
        outline: GreedyPalette.lavenderDeep,
      );
    }

    final head = Path()..addOval(const Rect.fromLTWH(20, 14, 60, 54));
    _shape(canvas, head, GreedyPalette.white, width: 3.8);

    _eyes(canvas);

    // Nose and mouth.
    final nose = Path()
      ..moveTo(46, 47)
      ..lineTo(54, 47)
      ..lineTo(50, 52)
      ..close();
    _shape(canvas, nose, GreedyPalette.nosePink, width: 2.2);

    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = GreedyPalette.woodOutline;
    if (mood == CatMood.win) {
      // Open, delighted.
      final open = Path()..addOval(const Rect.fromLTWH(43, 52, 14, 12));
      _shape(canvas, open, const Color(0xFFE86A80), width: 2.4);
    } else if (mood == CatMood.lose) {
      canvas.drawArc(const Rect.fromLTWH(42, 56, 16, 12), pi * 0.15, pi * 0.7, false, mouth);
    } else {
      canvas.drawArc(const Rect.fromLTWH(42, 48, 8, 10), 0, pi * 0.8, false, mouth);
      canvas.drawArc(const Rect.fromLTWH(50, 48, 8, 10), pi * 0.2, pi * 0.8, false, mouth);
    }

    // Whiskers.
    final whisker = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = GreedyPalette.mutedText.withOpacity(0.7);
    for (final side in [-1, 1]) {
      for (var i = 0; i < 2; i++) {
        final y = 46.0 + i * 6;
        canvas.drawLine(
          Offset(50 + side * 12.0, y),
          Offset(50 + side * 34.0, y - 3 + i * 5.0),
          whisker,
        );
      }
    }

    if (mood == CatMood.win) _sparkles(canvas);
  }

  void _eyes(Canvas canvas) {
    for (final side in [-1, 1]) {
      final centre = Offset(50 + side * 13.0, 38);
      final wide = mood == CatMood.alert || mood == CatMood.win;
      final h = (wide ? 20.0 : 17.0) * (1 - blink);

      if (h < 2.5) {
        // Closed: a happy arc rather than a flat line.
        canvas.drawArc(
          Rect.fromCenter(center: centre, width: 18, height: 12),
          pi,
          pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = GreedyPalette.darkText,
        );
        continue;
      }

      final eye = Path()
        ..addOval(Rect.fromCenter(center: centre, width: 16, height: h));
      _shape(canvas, eye, const Color(0xFF3B2358), width: 2.4, outline: GreedyPalette.woodOutline);

      if (mood == CatMood.lose) {
        // Downcast: pupil low in the eye.
        canvas.drawCircle(centre.translate(0, h * 0.18), 4.4, Paint()..color = Colors.white24);
      }
      canvas.drawCircle(centre.translate(3, -h * 0.18), 3.4, Paint()..color = Colors.white);
      canvas.drawCircle(centre.translate(-3.5, h * 0.2), 1.7,
          Paint()..color = Colors.white.withOpacity(0.75));
    }
  }

  void _sparkles(Canvas canvas) {
    final paint = Paint()..color = GreedyPalette.gold;
    for (var i = 0; i < 4; i++) {
      final a = breath * 2 * pi + i * pi / 2;
      final centre = Offset(50 + cos(a) * 40, 36 + sin(a) * 26);
      final r = 3.0 + sin(breath * 2 * pi + i) * 1.2;
      final star = Path()
        ..moveTo(centre.dx, centre.dy - r)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx + r, centre.dy)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx, centre.dy + r)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx - r, centre.dy)
        ..quadraticBezierTo(centre.dx, centre.dy, centre.dx, centre.dy - r)
        ..close();
      canvas.drawPath(star, paint);
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

    // Spokes.
    for (var i = 0; i < count; i++) {
      final a = _angleFor(i);
      final outer = centre + Offset(cos(a), sin(a)) * cardRadius;
      final isWinner = winningIndex == i && winnerPulse > 0;

      canvas.drawLine(
        centre,
        outer,
        Paint()
          ..strokeWidth = hubRadius * 0.34
          ..strokeCap = StrokeCap.round
          ..color = GreedyPalette.woodOutline,
      );
      canvas.drawLine(
        centre,
        outer,
        Paint()
          ..strokeWidth = hubRadius * 0.24
          ..strokeCap = StrokeCap.round
          ..color = isWinner
              ? Color.lerp(GreedyPalette.woodMid, GreedyPalette.gold, winnerPulse)!
              : GreedyPalette.woodMid,
      );
      // Grain highlight along the upper edge of each spoke.
      canvas.drawLine(
        centre + Offset(cos(a), sin(a)) * (hubRadius * 0.7),
        outer,
        Paint()
          ..strokeWidth = hubRadius * 0.07
          ..strokeCap = StrokeCap.round
          ..color = GreedyPalette.woodHighlight.withOpacity(0.65),
      );

      // Rivets.
      for (final t in const [0.45, 0.75]) {
        final p = centre + Offset(cos(a), sin(a)) * (cardRadius * t);
        canvas.drawCircle(p, hubRadius * 0.075, Paint()..color = GreedyPalette.woodOutline);
        canvas.drawCircle(p, hubRadius * 0.055, Paint()..color = GreedyPalette.warmPale);
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
      _shapePx(canvas, leg, GreedyPalette.woodMid, hubRadius * 0.06);
    }
  }

  void _hub(Canvas canvas, Offset centre) {
    canvas.drawCircle(centre, hubRadius, Paint()..color = GreedyPalette.woodOutline);
    canvas.drawCircle(centre, hubRadius * 0.94, Paint()..color = GreedyPalette.woodHighlight);
    canvas.drawCircle(centre, hubRadius * 0.84, Paint()..color = GreedyPalette.woodMid);

    // Bulbs around the rim, chasing.
    const bulbs = 16;
    for (var i = 0; i < bulbs; i++) {
      final a = -pi / 2 + i * 2 * pi / bulbs;
      final p = centre + Offset(cos(a), sin(a)) * (hubRadius * 0.89);
      // A travelling wave rather than a blink, so nothing flashes.
      final t = ((glow * bulbs) - i) % bulbs / bulbs;
      final lit = (cos(t * 2 * pi) + 1) / 2;
      canvas.drawCircle(p, hubRadius * 0.055, Paint()..color = GreedyPalette.woodOutline);
      canvas.drawCircle(
        p,
        hubRadius * 0.04,
        Paint()..color = Color.lerp(GreedyPalette.warmPale, GreedyPalette.gold, lit)!,
      );
    }

    canvas.drawCircle(centre, hubRadius * 0.74, Paint()..color = GreedyPalette.cream);
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

/// Pixel-space fill + outline, for painters that are not in the 100-unit space.
void _shapePx(Canvas canvas, Path path, Color fill, double width) {
  canvas.drawPath(path, Paint()..color = fill);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..color = GreedyPalette.woodOutline,
  );
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
    _shapePx(canvas, path, Color.lerp(GreedyPalette.jackpotRed, GreedyPalette.gold, pulse)!,
        w * 0.09);
    canvas.drawCircle(Offset(w / 2, h * 0.3), w * 0.11, Paint()..color = GreedyPalette.warmPale);
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

    canvas.drawCircle(const Offset(50, 52), 46, Paint()..color = const Color(0xFFCE8A12));
    canvas.drawCircle(const Offset(50, 48), 44, Paint()..color = GreedyPalette.gold);
    canvas.drawCircle(const Offset(50, 48), 34, Paint()..color = const Color(0xFFFFE98A));

    final crown = Path()
      ..moveTo(30, 60)
      ..lineTo(34, 34)
      ..lineTo(43, 48)
      ..lineTo(50, 30)
      ..lineTo(57, 48)
      ..lineTo(66, 34)
      ..lineTo(70, 60)
      ..close();
    _shape(canvas, crown, GreedyPalette.orange, width: 3.4);
    _glint(canvas, const Offset(34, 28), 6, 10, opacity: 0.7);

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

    final wood = locked ? const Color(0xFF7C6A5E) : GreedyPalette.woodMid;
    final band = locked ? const Color(0xFFA79683) : GreedyPalette.gold;

    // Paint order matters: an open chest is lid FIRST (thrown back at the top),
    // then the treasure, then the body front. The lid used to be painted last
    // and covered every coin it was supposed to be revealing.
    if (opened && !locked) {
      final lid = Path()
        ..moveTo(16, 34)
        ..quadraticBezierTo(50, 2, 84, 34)
        ..quadraticBezierTo(50, 20, 16, 34)
        ..close();
      _shape(canvas, lid, wood, width: 4);

      for (var i = 0; i < 6; i++) {
        final x = 24.0 + i * 10.5;
        final y = 50.0 - (i.isEven ? 7 : 0);
        canvas.drawCircle(Offset(x, y), 7, Paint()..color = const Color(0xFFCE8A12));
        canvas.drawCircle(Offset(x, y - 1.5), 6, Paint()..color = GreedyPalette.gold);
      }
      for (final gem in const [
        [22.0, 44.0, 0xFF6BD5FF],
        [76.0, 46.0, 0xFFFF7BA8],
        [50.0, 38.0, 0xFF9BE86B],
      ]) {
        final p = Offset(gem[0] as double, gem[1] as double);
        final path = Path()
          ..moveTo(p.dx, p.dy - 6)
          ..lineTo(p.dx + 5, p.dy)
          ..lineTo(p.dx, p.dy + 6)
          ..lineTo(p.dx - 5, p.dy)
          ..close();
        _shape(canvas, path, Color(gem[2] as int), width: 2.2);
      }
    } else {
      final lid = Path()
        ..moveTo(14, 54)
        ..quadraticBezierTo(50, 22, 86, 54)
        ..close();
      _shape(canvas, lid, wood, width: 4);
    }

    // Body.
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(14, 52, 72, 36),
        const Radius.circular(6),
      ));
    _shape(canvas, body, wood, width: 4);

    canvas.drawRect(const Rect.fromLTWH(14, 56, 72, 8), Paint()..color = band);
    canvas.drawRect(const Rect.fromLTWH(44, 56, 12, 32), Paint()..color = band);

    // Lock plate.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(42, 62, 16, 16), const Radius.circular(3)),
      Paint()..color = band,
    );
    canvas.drawCircle(const Offset(50, 70), 3.4, Paint()..color = GreedyPalette.woodOutline);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChestPainter old) => old.opened != opened || old.locked != locked;
}

/// The seamless cyan doodle field behind the whole screen.
class BackgroundPatternPainter extends CustomPainter {
  const BackgroundPatternPainter({required this.drift});

  /// 0..1, slides the field so the background is never quite static.
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GreedyPalette.cyanTop, GreedyPalette.cyanBottom],
        ).createShader(Offset.zero & size),
    );

    final paint = Paint()..color = GreedyPalette.patternBlue.withOpacity(0.22);
    const cell = 84.0;
    final offset = drift * cell;
    for (var y = -cell; y < size.height + cell; y += cell) {
      for (var x = -cell; x < size.width + cell; x += cell) {
        final px = x + ((y / cell).floor().isEven ? cell / 2 : 0) + offset * 0.3;
        final py = y + offset;
        final kind = ((x / cell).floor() + (y / cell).floor()) % 3;
        if (kind == 0) {
          // Leaf.
          canvas.drawPath(
            _leaf(Offset(px, py), Offset(px + 16, py - 14), 6),
            paint,
          );
        } else if (kind == 1) {
          // Four-point sparkle.
          final r = 7.0;
          final star = Path()
            ..moveTo(px, py - r)
            ..quadraticBezierTo(px, py, px + r, py)
            ..quadraticBezierTo(px, py, px, py + r)
            ..quadraticBezierTo(px, py, px - r, py)
            ..quadraticBezierTo(px, py, px, py - r)
            ..close();
          canvas.drawPath(star, paint);
        } else {
          // Curved stroke.
          canvas.drawArc(
            Rect.fromCircle(center: Offset(px, py), radius: 11),
            pi * 0.2,
            pi * 0.9,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round
              ..color = GreedyPalette.patternBlue.withOpacity(0.22),
          );
        }
      }
    }
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
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    for (var i = 0; i < 46; i++) {
      final x = rng.nextDouble() * size.width;
      final delay = rng.nextDouble() * 0.35;
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final drift = (rng.nextDouble() - 0.5) * 90;
      final spin = rng.nextDouble() * 12;
      final y = -30 + t * (size.height + 60);
      final w = 7 + rng.nextDouble() * 6;

      canvas.save();
      canvas.translate(x + drift * t, y);
      canvas.rotate(spin * t);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.55),
        Paint()..color = _colors[i % _colors.length].withOpacity((1 - t * 0.7).clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.progress != progress || old.seed != seed;
}

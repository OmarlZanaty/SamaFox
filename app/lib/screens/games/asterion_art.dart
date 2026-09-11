import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Original artwork for أستيريون (Citadel of Asterion), drawn in code.
///
/// Every mark here is vector-painted rather than shipped as a bitmap, for the
/// same two reasons as القط الجشع: it stays crisp at any density, and the screen
/// never shows a grey placeholder while commissioned art is outstanding. When
/// PNGs arrive (see ASTERION_ARTWORK_BRIEF.md at the repo root) they go into
/// `assets/images/asterion/` under the stems in [AsterionArt]; the painted
/// version stays as the fallback for a missing or unreadable file.
///
/// All symbols are authored in a 100×100 box and scaled to fit, so a symbol
/// reads the same at 26px in the paytable and at 70px on the board.
///
/// ── On shading ──────────────────────────────────────────────
/// Same discipline as القط الجشع, because a set of icons that light themselves
/// differently looks like it came from three different artists. Every object is
/// built from four moves, in this order:
///
///   1. a gradient fill — [_sphere] for round forms, [_linear] for flat ones
///   2. [_occlude]      — contact shadow inside the lower edge
///   3. [_gloss]        — a broad specular sweep across the upper third
///   4. [_rim]          — a bright edge where the key light grazes the silhouette
///
/// The key light is upper-LEFT throughout, so shadows fall to the lower right on
/// every object in the game.
///
/// The material language differs from القط الجشع on purpose: this citadel is
/// crystal, storm-blue metal and moon-silver, so outlines are cool and thin
/// rather than warm and heavy, and the highlights are sharper.

// ── Palette ─────────────────────────────────────────────────
/// The style guide, as tokens. Nothing in this game should invent a colour.
class AsterionPalette {
  const AsterionPalette._();

  // Ground
  static const nightTop = Color(0xFF141A47);
  static const nightMid = Color(0xFF0C1030);
  static const nightDeep = Color(0xFF06071A);
  static const dawn = Color(0xFF3B2A63);
  static const dawnWarm = Color(0xFF6E4370);

  // Energy
  static const cyan = Color(0xFF5EE0F5);
  static const cyanDeep = Color(0xFF1E8FB8);
  static const cyanPale = Color(0xFFBFF4FF);
  static const magenta = Color(0xFFC061E8);

  // Metal
  static const silver = Color(0xFFE7EEF8);
  static const silverMid = Color(0xFFA9B8CE);
  static const silverDeep = Color(0xFF5B6A84);
  static const ink = Color(0xFF232C4B);
  static const inkDeep = Color(0xFF141A33);

  // Warmth
  static const amber = Color(0xFFFFC46B);
  static const amberDeep = Color(0xFFD98A22);
  static const amberPale = Color(0xFFFFE7B8);

  // Symbol families
  static const prism = Color(0xFF52D8EE);
  static const prismDeep = Color(0xFF1B7FA0);
  static const sun = Color(0xFFFFC15C);
  static const sunDeep = Color(0xFFC97A16);
  static const comet = Color(0xFFB07BF0);
  static const cometDeep = Color(0xFF6438A8);
  static const tide = Color(0xFF5FE0AE);
  static const tideDeep = Color(0xFF1C8A66);

  static const white = Color(0xFFFFFFFF);
  static const muted = Color(0xFF8E9BB8);
}

/// Where a commissioned PNG would live for each drawable, if one exists.
class AsterionArt {
  const AsterionArt._();

  static const dir = 'assets/images/asterion';

  static String assetFor(String symbolId) => '$dir/symbol_${symbolId.toLowerCase()}.png';
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

/// Straight gradient for flat-ish forms — facets, panels, plates.
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

/// Fill with a [Paint], then the cool outline that ties the set together.
void _paint(Canvas canvas, Path path, Paint fill, {double width = 3.0, Color? outline}) {
  canvas.drawPath(path, fill);
  if (width > 0) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = outline ?? AsterionPalette.inkDeep,
    );
  }
}

/// Darkens the inside of the lower edge, so a shape sits in its own shadow
/// instead of floating.
void _occlude(Canvas canvas, Path path, Rect r, {double opacity = 0.30}) {
  canvas.save();
  canvas.clipPath(path);
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(r.center.dx + r.width * 0.08, r.bottom + r.height * 0.28),
      width: r.width * 1.5,
      height: r.height * 0.9,
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );
  canvas.restore();
}

/// The broad specular sweep across the upper third.
void _gloss(Canvas canvas, Path path, Rect r, {double opacity = 0.55}) {
  canvas.save();
  canvas.clipPath(path);
  final glossRect = Rect.fromLTWH(
    r.left + r.width * 0.06,
    r.top + r.height * 0.02,
    r.width * 0.60,
    r.height * 0.48,
  );
  canvas.drawOval(
    glossRect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: opacity), Colors.white.withValues(alpha: 0)],
      ).createShader(glossRect),
  );
  canvas.restore();
}

/// A bright grazing edge along the lit side of the silhouette.
void _rim(
  Canvas canvas,
  Path path, {
  Color color = Colors.white,
  double opacity = 0.55,
  double width = 2.2,
  Offset shift = const Offset(-2.0, -2.0),
}) {
  canvas.save();
  canvas.clipPath(path);
  canvas.drawPath(
    path.shift(shift),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color.withValues(alpha: opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
  );
  canvas.restore();
}

/// The small hard catchlight that sells a polished surface.
void _glint(Canvas canvas, Offset centre, double rx, double ry, {double opacity = 0.9}) {
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(-0.5);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
    Paint()..color = Colors.white.withValues(alpha: opacity),
  );
  canvas.restore();
}

/// A soft drop shadow cast onto whatever is behind the object.
void _cast(Canvas canvas, Path path, {double opacity = 0.26, Offset offset = const Offset(3, 5)}) {
  canvas.drawPath(
    path.shift(offset),
    Paint()
      ..color = Colors.black.withValues(alpha: opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
}

/// An outward bloom, for the pieces that are supposed to be light sources.
void _bloom(Canvas canvas, Offset centre, double radius, Color colour, {double opacity = 0.5}) {
  canvas.drawCircle(
    centre,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [
          colour.withValues(alpha: opacity),
          colour.withValues(alpha: opacity * 0.35),
          colour.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: centre, radius: radius)),
  );
}

Path _polygon(Offset centre, double radius, int sides, {double rotation = 0}) {
  final path = Path();
  for (var i = 0; i < sides; i++) {
    final a = rotation + i * 2 * math.pi / sides;
    final p = Offset(centre.dx + radius * math.cos(a), centre.dy + radius * math.sin(a));
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// A four-pointed star — the game's recurring celestial mark.
Path _star4(Offset c, double outer, double inner) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / 4;
    final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

// ── Symbol metadata ─────────────────────────────────────────

/// Display name and accent colour for every symbol. Original wording — none of
/// it is borrowed from a published game.
class SymbolInfo {
  const SymbolInfo(this.id, this.name, this.colour, this.glow);
  final String id;
  final String name;
  final Color colour;
  final Color glow;
}

const Map<String, SymbolInfo> kAsterionSymbols = {
  'L1': SymbolInfo('L1', 'شظية المنشور', AsterionPalette.prism, AsterionPalette.cyanPale),
  'L2': SymbolInfo('L2', 'قرص الشمس', AsterionPalette.sun, AsterionPalette.amberPale),
  'L3': SymbolInfo('L3', 'ختم المذنّب', AsterionPalette.comet, Color(0xFFE0C8FF)),
  'L4': SymbolInfo('L4', 'حجر المدّ', AsterionPalette.tide, Color(0xFFB9FFE4)),
  'H1': SymbolInfo('H1', 'تاج الهلال', AsterionPalette.silver, AsterionPalette.white),
  'H2': SymbolInfo('H2', 'جرّة النجوم', Color(0xFF6E8FE8), Color(0xFFBFD4FF)),
  'H3': SymbolInfo('H3', 'قيثارة العاصفة', Color(0xFF54C8E0), AsterionPalette.cyanPale),
  'H4': SymbolInfo('H4', 'بوصلة الشمس', AsterionPalette.amber, AsterionPalette.amberPale),
  'CREST': SymbolInfo('CREST', 'شعار أستيريون', AsterionPalette.cyan, AsterionPalette.white),
  'ORB': SymbolInfo('ORB', 'كرة العاصفة', AsterionPalette.magenta, AsterionPalette.cyanPale),
};

/// Which symbols pay, richest first. Kept next to the metadata so a caller
/// never has to guess whether 'CREST' belongs in a paytable — it does not.
const List<String> kPayingSymbols = ['H4', 'H3', 'H2', 'H1', 'L4', 'L3', 'L2', 'L1'];

// ── Symbol drawing ──────────────────────────────────────────

/// Draws one symbol into a 100×100 box at the canvas origin.
///
/// Split out from the painter so the board, the paytable and the help sheet all
/// render the identical artwork rather than three near-copies.
void paintSymbol(Canvas canvas, String id) {
  switch (id) {
    case 'L1':
      _prismShard(canvas);
      break;
    case 'L2':
      _sunDisc(canvas);
      break;
    case 'L3':
      _cometSeal(canvas);
      break;
    case 'L4':
      _tideStone(canvas);
      break;
    case 'H1':
      _diadem(canvas);
      break;
    case 'H2':
      _amphora(canvas);
      break;
    case 'H3':
      _lyre(canvas);
      break;
    case 'H4':
      _compass(canvas);
      break;
    case 'CREST':
      paintCrest(canvas);
      break;
    case 'ORB':
      paintOrbShell(canvas);
      break;
  }
}

// L1 — a faceted cyan shard, the cheapest thing in the citadel.
void _prismShard(Canvas canvas) {
  final body = Path()
    ..moveTo(50, 12)
    ..lineTo(76, 40)
    ..lineTo(66, 84)
    ..lineTo(34, 84)
    ..lineTo(24, 40)
    ..close();
  final r = body.getBounds();
  _cast(canvas, body);
  _paint(canvas, body, _linear(r, [AsterionPalette.cyanPale, AsterionPalette.prism, AsterionPalette.prismDeep]));

  // Facets: two internal planes, one lit, one in shade.
  canvas.save();
  canvas.clipPath(body);
  final left = Path()
    ..moveTo(50, 12)
    ..lineTo(24, 40)
    ..lineTo(34, 84)
    ..lineTo(50, 60)
    ..close();
  canvas.drawPath(left, Paint()..color = Colors.white.withValues(alpha: 0.22));
  final right = Path()
    ..moveTo(50, 12)
    ..lineTo(76, 40)
    ..lineTo(66, 84)
    ..lineTo(50, 60)
    ..close();
  canvas.drawPath(right, Paint()..color = AsterionPalette.inkDeep.withValues(alpha: 0.28));
  canvas.restore();

  _occlude(canvas, body, r);
  _gloss(canvas, body, r, opacity: 0.4);
  _rim(canvas, body, color: AsterionPalette.cyanPale);
  canvas.drawPath(
    _star4(const Offset(50, 46), 11, 3.4),
    Paint()..color = Colors.white.withValues(alpha: 0.75),
  );
  _glint(canvas, const Offset(40, 30), 4, 2);
}

// L2 — an amber sun-disc with engraved rays.
void _sunDisc(Canvas canvas) {
  const c = Offset(50, 50);
  final body = _polygon(c, 36, 6, rotation: -math.pi / 2);
  final r = body.getBounds();
  _cast(canvas, body);
  _paint(canvas, body, _sphere(r, AsterionPalette.amberPale, AsterionPalette.sun, AsterionPalette.sunDeep));

  canvas.save();
  canvas.clipPath(body);
  for (var i = 0; i < 12; i++) {
    final a = i * math.pi / 6;
    canvas.drawLine(
      Offset(c.dx + 10 * math.cos(a), c.dy + 10 * math.sin(a)),
      Offset(c.dx + 34 * math.cos(a), c.dy + 34 * math.sin(a)),
      Paint()
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.sunDeep.withValues(alpha: 0.55),
    );
  }
  canvas.restore();

  final inner = _polygon(c, 15, 6, rotation: -math.pi / 2);
  _paint(canvas, inner, _sphere(inner.getBounds(), Colors.white, AsterionPalette.amberPale, AsterionPalette.amber),
      width: 2.0, outline: AsterionPalette.amberDeep,);

  _occlude(canvas, body, r);
  _gloss(canvas, body, r, opacity: 0.45);
  _rim(canvas, body, color: AsterionPalette.amberPale);
  _glint(canvas, const Offset(36, 32), 5, 2.4);
}

// L3 — a violet comet seal on a rounded diamond medallion.
void _cometSeal(Canvas canvas) {
  final body = Path()
    ..moveTo(50, 10)
    ..quadraticBezierTo(84, 34, 50, 90)
    ..quadraticBezierTo(16, 34, 50, 10)
    ..close();
  final r = body.getBounds();
  _cast(canvas, body);
  _paint(canvas, body, _linear(r, [const Color(0xFFD8B8FF), AsterionPalette.comet, AsterionPalette.cometDeep]));
  _occlude(canvas, body, r);

  canvas.save();
  canvas.clipPath(body);
  // Comet: a bright head with a tail sweeping to the lower left.
  final tail = Path()
    ..moveTo(62, 32)
    ..quadraticBezierTo(44, 52, 30, 72)
    ..quadraticBezierTo(46, 58, 68, 40)
    ..close();
  canvas.drawPath(tail, Paint()..color = Colors.white.withValues(alpha: 0.55));
  canvas.drawCircle(const Offset(64, 32), 8, Paint()..color = Colors.white.withValues(alpha: 0.92));
  _bloom(canvas, const Offset(64, 32), 16, AsterionPalette.cyanPale, opacity: 0.5);
  canvas.restore();

  _gloss(canvas, body, r, opacity: 0.35);
  _rim(canvas, body, color: const Color(0xFFE8D6FF));
}

// L4 — an emerald tide stone with a wave glyph.
void _tideStone(Canvas canvas) {
  final body = Path()
    ..moveTo(50, 8)
    ..cubicTo(70, 30, 86, 48, 86, 62)
    ..cubicTo(86, 82, 70, 92, 50, 92)
    ..cubicTo(30, 92, 14, 82, 14, 62)
    ..cubicTo(14, 48, 30, 30, 50, 8)
    ..close();
  final r = body.getBounds();
  _cast(canvas, body);
  _paint(canvas, body, _sphere(r, const Color(0xFFCFFFEC), AsterionPalette.tide, AsterionPalette.tideDeep));
  _occlude(canvas, body, r);

  canvas.save();
  canvas.clipPath(body);
  for (var i = 0; i < 2; i++) {
    final y = 58.0 + i * 13;
    canvas.drawPath(
      Path()
        ..moveTo(26, y)
        ..quadraticBezierTo(38, y - 8, 50, y)
        ..quadraticBezierTo(62, y + 8, 74, y),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.65 - i * 0.25),
    );
  }
  canvas.restore();

  _gloss(canvas, body, r, opacity: 0.5);
  _rim(canvas, body, color: const Color(0xFFCFFFEC));
  _glint(canvas, const Offset(42, 26), 4.5, 2.2);
}

// H1 — the moon-silver diadem.
void _diadem(Canvas canvas) {
  final band = Path()
    ..moveTo(16, 64)
    ..quadraticBezierTo(50, 78, 84, 64)
    ..lineTo(84, 76)
    ..quadraticBezierTo(50, 90, 16, 76)
    ..close();
  final crown = Path()
    ..moveTo(16, 66)
    ..lineTo(26, 30)
    ..lineTo(38, 52)
    ..lineTo(50, 20)
    ..lineTo(62, 52)
    ..lineTo(74, 30)
    ..lineTo(84, 66)
    ..quadraticBezierTo(50, 78, 16, 66)
    ..close();

  _cast(canvas, crown);
  final cr = crown.getBounds();
  _paint(canvas, crown, _linear(cr, [AsterionPalette.white, AsterionPalette.silverMid, AsterionPalette.silverDeep]),
      width: 2.6, outline: AsterionPalette.ink,);
  _occlude(canvas, crown, cr);
  _gloss(canvas, crown, cr, opacity: 0.5);

  final br = band.getBounds();
  _paint(canvas, band, _linear(br, [AsterionPalette.silver, AsterionPalette.silverDeep]),
      width: 2.6, outline: AsterionPalette.ink,);

  // Crescent set into the band, the piece that makes it Asterion's and not a
  // generic crown. It sits on the band rather than up among the spikes, where
  // the first version of this drawing hid it completely.
  final crescent = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: const Offset(50, 62), radius: 13)),
    Path()..addOval(Rect.fromCircle(center: const Offset(57, 59), radius: 12)),
  );
  _bloom(canvas, const Offset(50, 62), 22, AsterionPalette.cyan, opacity: 0.55);
  _paint(canvas, crescent, Paint()..color = AsterionPalette.cyanPale, width: 0);

  _rim(canvas, crown, color: Colors.white, opacity: 0.65);
  _glint(canvas, const Offset(30, 44), 3.5, 1.8);
}

// H2 — the astral amphora.
void _amphora(Canvas canvas) {
  final body = Path()
    ..moveTo(38, 26)
    ..lineTo(62, 26)
    ..quadraticBezierTo(80, 46, 70, 70)
    ..quadraticBezierTo(62, 86, 50, 86)
    ..quadraticBezierTo(38, 86, 30, 70)
    ..quadraticBezierTo(20, 46, 38, 26)
    ..close();
  final r = body.getBounds();
  _cast(canvas, body);
  _paint(canvas, body, _sphere(r, const Color(0xFFAFC8FF), const Color(0xFF4E6CC4), const Color(0xFF223468)),
      width: 2.8, outline: AsterionPalette.inkDeep,);
  _occlude(canvas, body, r);

  // Handles.
  for (final side in [-1.0, 1.0]) {
    final h = Path()
      ..moveTo(50 + side * 22, 32)
      ..quadraticBezierTo(50 + side * 40, 42, 50 + side * 26, 56);
    canvas.drawPath(
      h,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.silverDeep,
    );
    canvas.drawPath(
      h.shift(const Offset(-1.4, -1.4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.silver.withValues(alpha: 0.8),
    );
  }

  // Constellation engraving.
  canvas.save();
  canvas.clipPath(body);
  const stars = [Offset(42, 48), Offset(54, 42), Offset(60, 56), Offset(46, 64), Offset(56, 70)];
  for (var i = 0; i < stars.length - 1; i++) {
    canvas.drawLine(
      stars[i],
      stars[i + 1],
      Paint()
        ..strokeWidth = 1.2
        ..color = AsterionPalette.cyanPale.withValues(alpha: 0.55),
    );
  }
  for (final s in stars) {
    canvas.drawCircle(s, 2.4, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }
  canvas.restore();

  // Mouth, glowing.
  final mouth = Rect.fromCenter(center: const Offset(50, 26), width: 30, height: 11);
  _bloom(canvas, mouth.center, 20, AsterionPalette.cyan, opacity: 0.5);
  canvas.drawOval(mouth, Paint()..color = AsterionPalette.cyanPale);
  canvas.drawOval(
    mouth,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = AsterionPalette.silver,
  );

  _gloss(canvas, body, r, opacity: 0.35);
  _rim(canvas, body, color: const Color(0xFFAFC8FF));
}

// H3 — the storm lyre.
void _lyre(Canvas canvas) {
  final frame = Path()
    ..moveTo(28, 84)
    ..quadraticBezierTo(6, 56, 26, 22)
    ..quadraticBezierTo(34, 12, 40, 22)
    ..quadraticBezierTo(26, 50, 40, 78)
    ..close()
    ..moveTo(72, 84)
    ..quadraticBezierTo(94, 56, 74, 22)
    ..quadraticBezierTo(66, 12, 60, 22)
    ..quadraticBezierTo(74, 50, 60, 78)
    ..close();

  _cast(canvas, frame);
  final fr = frame.getBounds();
  _paint(canvas, frame, _linear(fr, [AsterionPalette.silverMid, AsterionPalette.ink]),
      width: 2.4, outline: AsterionPalette.inkDeep,);

  // Strings, lit like filaments.
  for (var i = 0; i < 5; i++) {
    final x = 38.0 + i * 6;
    canvas.drawLine(
      Offset(x, 26 + (i - 2).abs() * 2.0),
      Offset(x, 80),
      Paint()
        ..strokeWidth = 1.6
        ..color = AsterionPalette.cyanPale.withValues(alpha: 0.95),
    );
    canvas.drawLine(
      Offset(x, 26 + (i - 2).abs() * 2.0),
      Offset(x, 80),
      Paint()
        ..strokeWidth = 4.5
        ..color = AsterionPalette.cyan.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  // Crossbar and base.
  final bar = RRect.fromRectAndRadius(
    Rect.fromCenter(center: const Offset(50, 82), width: 52, height: 10),
    const Radius.circular(5),
  );
  canvas.drawRRect(bar, _linear(bar.outerRect, [AsterionPalette.silver, AsterionPalette.silverDeep]));
  canvas.drawRRect(
    bar,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = AsterionPalette.inkDeep,
  );

  _rim(canvas, frame, color: AsterionPalette.silver, opacity: 0.5);
  _glint(canvas, const Offset(24, 34), 3, 1.6);
}

// H4 — the sun-forged compass, the top payer.
void _compass(Canvas canvas) {
  const c = Offset(50, 50);
  final ring = Path()..addOval(Rect.fromCircle(center: c, radius: 38));
  _cast(canvas, ring);
  final rr = ring.getBounds();
  _paint(canvas, ring, _sphere(rr, AsterionPalette.amberPale, AsterionPalette.amber, AsterionPalette.amberDeep),
      width: 3.0, outline: const Color(0xFF6B3E08),);

  final inner = Path()..addOval(Rect.fromCircle(center: c, radius: 28));
  _paint(canvas, inner, _sphere(inner.getBounds(), const Color(0xFF2A3560), AsterionPalette.inkDeep, Colors.black),
      width: 2.0, outline: AsterionPalette.amberDeep,);

  // Four radiant points.
  final rose = _star4(c, 26, 7);
  _paint(canvas, rose, _linear(rose.getBounds(), [Colors.white, AsterionPalette.silverMid]),
      width: 1.6, outline: AsterionPalette.silverDeep,);
  final rose2 = _star4(c, 16, 4.5);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(math.pi / 4);
  canvas.translate(-c.dx, -c.dy);
  canvas.drawPath(rose2, Paint()..color = AsterionPalette.amberPale.withValues(alpha: 0.85));
  canvas.restore();

  _bloom(canvas, c, 14, AsterionPalette.amberPale, opacity: 0.55);
  canvas.drawCircle(c, 5, Paint()..color = Colors.white);

  // Tick marks on the ring.
  for (var i = 0; i < 16; i++) {
    final a = i * math.pi / 8;
    final long = i % 4 == 0;
    canvas.drawLine(
      Offset(c.dx + (long ? 30 : 32) * math.cos(a), c.dy + (long ? 30 : 32) * math.sin(a)),
      Offset(c.dx + 36 * math.cos(a), c.dy + 36 * math.sin(a)),
      Paint()
        ..strokeWidth = long ? 2.4 : 1.2
        ..color = const Color(0xFF6B3E08).withValues(alpha: 0.75),
    );
  }

  _occlude(canvas, ring, rr, opacity: 0.24);
  _gloss(canvas, ring, rr, opacity: 0.4);
  _rim(canvas, ring, color: AsterionPalette.amberPale);
}

/// The scatter: a moon-silver medallion carrying Asterion's crescent halo and
/// his two-pronged staff. Deliberately symmetrical so it is spotted instantly
/// in a crowded board, and deliberately not a face.
void paintCrest(Canvas canvas) {
  const c = Offset(50, 50);
  _bloom(canvas, c, 46, AsterionPalette.cyan, opacity: 0.4);

  final ring = Path()..addOval(Rect.fromCircle(center: c, radius: 38));
  _cast(canvas, ring);
  final rr = ring.getBounds();
  _paint(canvas, ring, _sphere(rr, AsterionPalette.white, AsterionPalette.silverMid, AsterionPalette.silverDeep),
      width: 2.6, outline: AsterionPalette.ink,);

  final field = Path()..addOval(Rect.fromCircle(center: c, radius: 29));
  _paint(
    canvas,
    field,
    _sphere(field.getBounds(), const Color(0xFF243B6E), AsterionPalette.nightMid, Colors.black),
    width: 1.8,
    outline: AsterionPalette.silverDeep,
  );

  // Segmented halo: seven arcs with gaps, spanning the top symmetrically. The
  // first version swept only the upper-left quadrant, which read as a hook
  // rather than a halo — a scatter has to be recognised in a glance.
  for (var i = 0; i < 7; i++) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 21),
      math.pi * 1.13 + i * 0.33,
      0.23,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.6
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.cyanPale,
    );
  }

  // Two-pronged staff, held low inside the halo.
  final staff = Path()
    ..moveTo(50, 74)
    ..lineTo(50, 46)
    ..moveTo(50, 46)
    ..lineTo(41, 33)
    ..moveTo(50, 46)
    ..lineTo(59, 33);
  canvas.drawPath(
    staff,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.4
      ..strokeCap = StrokeCap.round
      ..color = AsterionPalette.silverDeep,
  );
  canvas.drawPath(
    staff,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white,
  );

  for (final p in [const Offset(41, 33), const Offset(59, 33)]) {
    _bloom(canvas, p, 9, AsterionPalette.cyan, opacity: 0.8);
    canvas.drawCircle(p, 2.8, Paint()..color = Colors.white);
  }

  // Amber star points at the cardinal edges.
  for (var i = 0; i < 4; i++) {
    final a = -math.pi / 2 + i * math.pi / 2;
    canvas.drawPath(
      _star4(Offset(c.dx + 33 * math.cos(a), c.dy + 33 * math.sin(a)), 4.5, 1.5),
      Paint()..color = AsterionPalette.amberPale,
    );
  }

  _rim(canvas, ring, color: Colors.white, opacity: 0.6);
}

/// The Storm Orb's shell. The numeral is drawn by the widget on top, so the
/// same shell serves 2x and 250x without re-authoring the art.
void paintOrbShell(Canvas canvas) {
  const c = Offset(50, 50);
  _bloom(canvas, c, 48, AsterionPalette.magenta, opacity: 0.42);

  // Wing-like fins, asymmetric so the orb never reads as a plain ball.
  final fins = Path()
    ..moveTo(20, 40)
    ..quadraticBezierTo(2, 28, 8, 12)
    ..quadraticBezierTo(24, 20, 30, 32)
    ..close()
    ..moveTo(80, 40)
    ..quadraticBezierTo(98, 28, 92, 12)
    ..quadraticBezierTo(76, 20, 70, 32)
    ..close()
    ..moveTo(26, 66)
    ..quadraticBezierTo(10, 78, 16, 90)
    ..quadraticBezierTo(28, 82, 34, 72)
    ..close()
    ..moveTo(74, 66)
    ..quadraticBezierTo(90, 78, 84, 90)
    ..quadraticBezierTo(72, 82, 66, 72)
    ..close();
  _paint(canvas, fins, _linear(fins.getBounds(), [AsterionPalette.cyanPale, AsterionPalette.magenta]),
      width: 1.8, outline: AsterionPalette.inkDeep,);

  final shell = Path()..addOval(Rect.fromCircle(center: c, radius: 30));
  _cast(canvas, shell);
  final sr = shell.getBounds();
  _paint(canvas, shell, _sphere(sr, Colors.white, AsterionPalette.magenta, const Color(0xFF3A1263)),
      width: 2.4, outline: AsterionPalette.inkDeep,);

  // Inner core.
  _bloom(canvas, c, 22, AsterionPalette.cyanPale, opacity: 0.85);
  canvas.drawCircle(c, 19, Paint()..color = const Color(0xFF17103A).withValues(alpha: 0.85));

  // A restrained arc of electricity around the shell.
  final arc = Path()
    ..moveTo(24, 36)
    ..lineTo(34, 44)
    ..lineTo(28, 50)
    ..lineTo(38, 60);
  canvas.drawPath(
    arc,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = AsterionPalette.cyanPale.withValues(alpha: 0.9),
  );

  _gloss(canvas, shell, sr, opacity: 0.4);
  _rim(canvas, shell, color: AsterionPalette.cyanPale);
}

/// A symbol at any size. [size] is the side of the square box it draws into.
class SymbolIcon extends StatelessWidget {
  const SymbolIcon(this.id, {super.key, this.size = 44});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SymbolPainter(id)),
      );
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    paintSymbol(canvas, id);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.id != id;
}

/// A Storm Orb with its face value written across the core.
class StormOrb extends StatelessWidget {
  const StormOrb({super.key, required this.value, this.size = 46, this.collected = false});

  final int value;
  final double size;

  /// After collection the orb dims and its number stops pulsing, so a player can
  /// see at a glance which orbs are already in the meter.
  final bool collected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: collected ? 0.45 : 1,
            child: CustomPaint(size: Size.square(size), painter: const _SymbolPainter('ORB')),
          ),
          Text(
            '${value}x',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              // 250x has to fit the same core as 2x, so the face shrinks with
              // the digit count rather than spilling over the shell.
              fontSize: size * (value >= 100 ? 0.21 : (value >= 10 ? 0.26 : 0.30)),
              height: 1,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: const [
                Shadow(color: AsterionPalette.magenta, blurRadius: 8),
                Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Asterion ────────────────────────────────────────────────

/// What the guardian is doing. The screen drives this; the painter only draws.
enum GuardianMood { calm, attentive, strike, exultant, trial }

/// Asterion himself: an invented sky guardian, deliberately not a classical
/// Zeus — no beard portrait, no throne, no laurel. What identifies him is the
/// segmented crescent halo, the silver braid over one shoulder and the
/// two-pronged staff, all of which read at thumbnail size.
class Guardian extends StatelessWidget {
  const Guardian({super.key, required this.mood, this.charge = 0});

  final GuardianMood mood;

  /// 0..1 — how far the staff has charged, drives the bolt's brightness.
  final double charge;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _GuardianPainter(mood: mood, charge: charge),
        size: Size.infinite,
      );
}

class _GuardianPainter extends CustomPainter {
  const _GuardianPainter({required this.mood, required this.charge});

  final GuardianMood mood;
  final double charge;

  @override
  void paint(Canvas canvas, Size size) {
    // Authored in a 200×300 box, letterboxed into whatever it is given.
    final scale = math.min(size.width / 200, size.height / 300);
    canvas.save();
    canvas.translate((size.width - 200 * scale) / 2, (size.height - 300 * scale) / 2);
    canvas.scale(scale);

    final lit = mood == GuardianMood.strike || mood == GuardianMood.trial;
    final glow = lit ? 1.0 : (mood == GuardianMood.exultant ? 0.7 : 0.35);

    // Aura.
    _bloom(canvas, const Offset(100, 140), 120, AsterionPalette.cyan, opacity: 0.18 + 0.22 * glow);

    // Mantle behind the body: narrow at the collar, flaring to the hem, so the
    // silhouette tapers up to the head instead of reading as one dark blob.
    final mantle = Path()
      ..moveTo(100, 84)
      ..quadraticBezierTo(150, 100, 156, 200)
      ..quadraticBezierTo(160, 250, 150, 268)
      ..quadraticBezierTo(100, 252, 50, 268)
      ..quadraticBezierTo(40, 250, 44, 200)
      ..quadraticBezierTo(50, 100, 100, 84)
      ..close();
    _paint(canvas, mantle, _linear(mantle.getBounds(), [const Color(0xFF2B3A72), const Color(0xFF101736)]),
        width: 3, outline: AsterionPalette.inkDeep,);
    _rim(canvas, mantle, color: AsterionPalette.cyanPale, opacity: 0.35, width: 3);

    // Two folds, which is what turns a flat shape into cloth.
    canvas.save();
    canvas.clipPath(mantle);
    for (final dx in [-26.0, 26.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(100 + dx * 0.5, 110)
          ..quadraticBezierTo(100 + dx, 190, 100 + dx * 1.25, 262),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = Colors.black.withValues(alpha: 0.35),
      );
    }
    canvas.restore();

    // Torso armour.
    final torso = Path()
      ..moveTo(100, 92)
      ..quadraticBezierTo(140, 104, 134, 180)
      ..quadraticBezierTo(100, 196, 66, 180)
      ..quadraticBezierTo(60, 104, 100, 92)
      ..close();
    final tr = torso.getBounds();
    _paint(canvas, torso, _linear(tr, [const Color(0xFF4A5E9E), const Color(0xFF1B2448)]),
        width: 3, outline: AsterionPalette.inkDeep,);
    _gloss(canvas, torso, tr, opacity: 0.3);

    // Chest sigil — the same crescent as the crest, so the set holds together.
    _bloom(canvas, const Offset(100, 132), 26, AsterionPalette.cyan, opacity: 0.5 * glow + 0.2);
    final sigil = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: const Offset(100, 132), radius: 15)),
      Path()..addOval(Rect.fromCircle(center: const Offset(107, 128), radius: 14)),
    );
    canvas.drawPath(sigil, Paint()..color = AsterionPalette.cyanPale);

    // Shoulder plates, overlapping the torso and angled down and out. Kept as
    // separate floating pills they read as handlebars, not armour.
    for (final side in [-1.0, 1.0]) {
      final plate = Path()
        ..moveTo(100 + side * 20, 100)
        ..quadraticBezierTo(100 + side * 56, 100, 100 + side * 54, 128)
        ..quadraticBezierTo(100 + side * 36, 118, 100 + side * 20, 118)
        ..close();
      _paint(canvas, plate, _linear(plate.getBounds(), [AsterionPalette.silver, AsterionPalette.silverDeep]),
          width: 3, outline: AsterionPalette.ink,);
      _rim(canvas, plate, opacity: 0.5);
    }

    // Sash across the waist, and the hem it tucks into.
    canvas.drawPath(
      Path()
        ..moveTo(70, 168)
        ..quadraticBezierTo(100, 180, 130, 168),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.amberDeep.withValues(alpha: 0.9),
    );

    // Hair mass behind the head, so the silhouette is not a bare ball.
    final hair = Path()
      ..addOval(Rect.fromCircle(center: const Offset(100, 58), radius: 30));
    _paint(canvas, hair, _linear(hair.getBounds(), [Colors.white, AsterionPalette.silverMid]),
        width: 2.4, outline: AsterionPalette.silverDeep,);

    // Head.
    final head = Path()..addOval(Rect.fromCircle(center: const Offset(100, 64), radius: 25));
    _paint(canvas, head, _sphere(head.getBounds(), const Color(0xFFF6E4D2), const Color(0xFFD9BBA1), const Color(0xFF8A6A52)),
        width: 2.6, outline: AsterionPalette.ink,);

    // The braid over his left shoulder — one of the three marks that identify
    // him at thumbnail size, with the halo and the two-pronged staff.
    final braid = Path()
      ..moveTo(74, 62)
      ..quadraticBezierTo(58, 104, 70, 150)
      ..quadraticBezierTo(82, 106, 86, 70)
      ..close();
    _paint(canvas, braid, _linear(braid.getBounds(), [Colors.white, AsterionPalette.silverMid]),
        width: 2.2, outline: AsterionPalette.silverDeep,);

    // Eyes — two cyan slivers, used sparingly, wider the more charged he is.
    for (final dx in [-9.0, 9.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(100 + dx, 62), width: 8, height: 2.6 + 3.0 * glow),
        Paint()..color = AsterionPalette.cyanPale,
      );
    }

    // Segmented crescent halo, spanning the top of the head. Seven crystal
    // arcs, gapped: the first version swept only the upper-left and read as a
    // hook rather than a halo.
    for (var i = 0; i < 7; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(100, 56), radius: 40),
        3.55 + i * 0.33,
        0.23,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = AsterionPalette.cyanPale.withValues(alpha: 0.5 + 0.5 * glow),
      );
    }

    // The staff: raised on a strike, mid on a win, held low otherwise. It stays
    // well right of the head — an earlier version rotated it across his face.
    final raised = mood == GuardianMood.strike || mood == GuardianMood.trial;
    final half = mood == GuardianMood.exultant;

    // The forearm that holds it, drawn before the staff so the hand overlaps.
    canvas.drawLine(
      const Offset(126, 152),
      const Offset(174, 158),
      Paint()
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF32406F),
    );
    canvas.drawCircle(
      const Offset(176, 158),
      9,
      Paint()..color = const Color(0xFFE0C6AE),
    );

    canvas.save();
    canvas.translate(172, raised ? 132 : 150);
    canvas.rotate(raised ? -0.18 : (half ? -0.13 : -0.07));
    final shaft = Path()
      ..moveTo(0, -60)
      ..lineTo(0, 95);
    canvas.drawPath(
      shaft,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.silverDeep,
    );
    canvas.drawPath(
      shaft,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    // Two prongs.
    final prongs = Path()
      ..moveTo(0, -60)
      ..lineTo(-16, -94)
      ..moveTo(0, -60)
      ..lineTo(16, -94);
    canvas.drawPath(
      prongs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.silverDeep,
    );
    canvas.drawPath(
      prongs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.cyanPale,
    );
    _bloom(canvas, const Offset(0, -82), 26 + 18 * charge, AsterionPalette.cyan, opacity: 0.35 + 0.5 * charge);

    // On a strike the prongs actually throw something: a short bolt leaving the
    // staff. Without it every mood painted the same pose with a brighter glow.
    if (raised) {
      final bolt = Path()
        ..moveTo(0, -94)
        ..lineTo(-14, -124)
        ..lineTo(2, -128)
        ..lineTo(-10, -158);
      canvas.drawPath(
        bolt,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = AsterionPalette.cyan.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        bolt,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.white,
      );
    }
    canvas.restore();

    // The trial keeps a portal ring open behind him for as long as it runs.
    if (mood == GuardianMood.trial) {
      canvas.drawCircle(
        const Offset(100, 150),
        96,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AsterionPalette.magenta.withValues(alpha: 0.5),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GuardianPainter old) => old.mood != mood || old.charge != charge;
}

// ── Environment ─────────────────────────────────────────────

/// The citadel behind the board: floating marble platforms, observatory arches,
/// cloud banks and a dawn horizon, with the centre kept quiet so symbols stay
/// readable on top of it.
class CitadelBackdrop extends StatelessWidget {
  const CitadelBackdrop({super.key, required this.drift, this.stormy = false});

  /// 0..1, loops — drives cloud drift and the star shimmer.
  final double drift;

  /// The trial darkens the sky and pushes the lightning forward.
  final bool stormy;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _CitadelPainter(drift: drift, stormy: stormy),
        size: Size.infinite,
      );
}

class _CitadelPainter extends CustomPainter {
  const _CitadelPainter({required this.drift, required this.stormy});

  final double drift;
  final bool stormy;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: stormy
              ? const [Color(0xFF0B0F2C), Color(0xFF16123A), Color(0xFF05060F)]
              : const [
                  AsterionPalette.nightTop,
                  AsterionPalette.dawn,
                  AsterionPalette.nightDeep,
                ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // Dawn glow low on the horizon.
    _bloom(
      canvas,
      Offset(size.width * 0.22, size.height * 0.72),
      size.width * 0.5,
      stormy ? AsterionPalette.magenta : AsterionPalette.dawnWarm,
      opacity: 0.30,
    );

    // Stars: fixed positions from a cheap hash, shimmering on the drift.
    for (var i = 0; i < 70; i++) {
      final x = ((i * 73) % 100) / 100 * size.width;
      final y = ((i * 149) % 60) / 100 * size.height;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(drift * 2 * math.pi + i));
      canvas.drawCircle(
        Offset(x, y),
        (i % 5 == 0 ? 1.6 : 1.0),
        Paint()..color = Colors.white.withValues(alpha: 0.22 * tw + 0.08),
      );
    }

    // Observatory arches, far layer.
    final arch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.012
      ..color = AsterionPalette.silverDeep.withValues(alpha: 0.28);
    for (var i = 0; i < 3; i++) {
      final cx = size.width * (0.16 + i * 0.34);
      final r = size.height * (0.30 - i * 0.04);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, size.height * 0.86), radius: r),
        math.pi,
        math.pi,
        false,
        arch,
      );
    }

    // Marble platform under the board.
    final plinth = Path()
      ..moveTo(size.width * 0.06, size.height * 0.97)
      ..lineTo(size.width * 0.14, size.height * 0.90)
      ..lineTo(size.width * 0.86, size.height * 0.90)
      ..lineTo(size.width * 0.94, size.height * 0.97)
      ..close();
    canvas.drawPath(
      plinth,
      _linear(plinth.getBounds(), [
        AsterionPalette.silverMid.withValues(alpha: 0.35),
        AsterionPalette.ink.withValues(alpha: 0.5),
      ]),
    );

    // Two cloud banks at different speeds — the parallax that sells the height.
    _clouds(canvas, size, offset: drift, y: 0.42, opacity: 0.10, scale: 1.0);
    _clouds(canvas, size, offset: (drift * 1.7) % 1.0, y: 0.62, opacity: 0.16, scale: 1.5);

    if (stormy) {
      // Distant lightning behind the architecture, never across the board.
      final bolt = Path()
        ..moveTo(size.width * 0.86, 0)
        ..lineTo(size.width * 0.80, size.height * 0.22)
        ..lineTo(size.width * 0.86, size.height * 0.24)
        ..lineTo(size.width * 0.78, size.height * 0.48);
      canvas.drawPath(
        bolt,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = AsterionPalette.cyanPale
              .withValues(alpha: 0.15 + 0.5 * (0.5 + 0.5 * math.sin(drift * 12))),
      );
    }
  }

  void _clouds(
    Canvas canvas,
    Size size, {
    required double offset,
    required double y,
    required double opacity,
    required double scale,
  }) {
    final paint = Paint()
      ..color = AsterionPalette.silver.withValues(alpha: opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * scale);
    for (var i = -1; i < 4; i++) {
      final x = ((i + offset) / 3.0) * size.width * 1.4 - size.width * 0.2;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, size.height * y),
          width: size.width * 0.5 * scale,
          height: size.height * 0.10 * scale,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CitadelPainter old) => old.drift != drift || old.stormy != stormy;
}

/// A jagged bolt between two points, used when the staff collects an orb.
class BoltPainter extends CustomPainter {
  const BoltPainter({required this.from, required this.to, required this.progress, this.seed = 0});

  final Offset from;
  final Offset to;

  /// 0..1 — how far the bolt has travelled.
  final double progress;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rnd = math.Random(seed);
    final head = Offset.lerp(from, to, progress.clamp(0.0, 1.0))!;
    final path = Path()..moveTo(from.dx, from.dy);
    const segments = 7;
    for (var i = 1; i <= segments; i++) {
      final t = i / segments;
      final p = Offset.lerp(from, head, t)!;
      final jitter = (1 - t) * 14;
      path.lineTo(
        p.dx + (rnd.nextDouble() - 0.5) * jitter,
        p.dy + (rnd.nextDouble() - 0.5) * jitter,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = AsterionPalette.cyan.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
    _bloom(canvas, head, 22, AsterionPalette.cyanPale, opacity: 0.8);
  }

  @override
  bool shouldRepaint(BoltPainter old) =>
      old.progress != progress || old.from != from || old.to != to;
}

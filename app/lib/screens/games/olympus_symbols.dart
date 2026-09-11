import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Visual identity for every بوابات أوليمبوس symbol.
///
/// No artwork exists yet, so each symbol renders as a *painted* glyph — a real
/// faceted gem silhouette for the five low symbols and a gold-rimmed artefact
/// plate for the four premiums — until the PNGs in OLYMPUS_ARTWORK_BRIEF.md
/// land. [OlympusArt] loads the real files when present and every call site
/// falls back automatically, exactly like بلينكو's peg art and أثيرفول's tiles.
///
/// The painted fallback is deliberately more than a Material icon: the brief's
/// acceptance test is that the board *reads* as this game, and a blue diamond,
/// a green triangle and a purple pentagon are most of what makes a 6×5 board
/// recognisable at a glance.

/// The silhouette a low symbol is cut to. Premiums use [GemShape.plate].
enum GemShape { diamond, triangle, hexagon, pentagon, square, plate }

class OlympusSymbolVisual {
  const OlympusSymbolVisual({
    required this.id,
    required this.shape,
    required this.color,
    required this.glow,
    required this.assetName,
    this.icon,
  });

  final String id;
  final GemShape shape;

  /// Face colour of the gem, or the accent of a premium plate.
  final Color color;

  /// The brighter rim/bloom colour, used for highlights and win glow.
  final Color glow;

  /// File stem under assets/images/olympus/, e.g. 'symbol_gem_blue'.
  final String assetName;

  /// Drawn on top of a premium plate. Null for the plain gems.
  final IconData? icon;
}

/// Cheapest first, matching the server's STANDARD_SYMBOLS order.
const Map<String, OlympusSymbolVisual> kOlympusSymbols = {
  'GEM_BLUE': OlympusSymbolVisual(
    id: 'GEM_BLUE',
    shape: GemShape.diamond,
    color: Color(0xFF2E7BE8),
    glow: Color(0xFF7FC4FF),
    assetName: 'symbol_gem_blue',
  ),
  'GEM_GREEN': OlympusSymbolVisual(
    id: 'GEM_GREEN',
    shape: GemShape.triangle,
    color: Color(0xFF23B26A),
    glow: Color(0xFF74F5B4),
    assetName: 'symbol_gem_green',
  ),
  'GEM_YELLOW': OlympusSymbolVisual(
    id: 'GEM_YELLOW',
    shape: GemShape.hexagon,
    color: Color(0xFFE8B21F),
    glow: Color(0xFFFFE382),
    assetName: 'symbol_gem_yellow',
  ),
  'GEM_PURPLE': OlympusSymbolVisual(
    id: 'GEM_PURPLE',
    shape: GemShape.pentagon,
    color: Color(0xFF8B3FE0),
    glow: Color(0xFFC79BFF),
    assetName: 'symbol_gem_purple',
  ),
  'GEM_RED': OlympusSymbolVisual(
    id: 'GEM_RED',
    shape: GemShape.square,
    color: Color(0xFFD62F42),
    glow: Color(0xFFFF8E9C),
    assetName: 'symbol_gem_red',
  ),
  'RING': OlympusSymbolVisual(
    id: 'RING',
    shape: GemShape.plate,
    color: Color(0xFFE3C173),
    glow: Color(0xFFFFE9B0),
    assetName: 'symbol_ring',
    icon: Icons.circle_outlined,
  ),
  'CHALICE': OlympusSymbolVisual(
    id: 'CHALICE',
    shape: GemShape.plate,
    color: Color(0xFFE9CE84),
    glow: Color(0xFFFFF1C2),
    assetName: 'symbol_chalice',
    icon: Icons.emoji_events_rounded,
  ),
  'HOURGLASS': OlympusSymbolVisual(
    id: 'HOURGLASS',
    shape: GemShape.plate,
    color: Color(0xFF6FA8FF),
    glow: Color(0xFFBFDCFF),
    assetName: 'symbol_hourglass',
    icon: Icons.hourglass_full_rounded,
  ),
  'CROWN': OlympusSymbolVisual(
    id: 'CROWN',
    shape: GemShape.plate,
    color: Color(0xFFFFD24A),
    glow: Color(0xFFFFF0A8),
    assetName: 'symbol_crown',
    icon: Icons.workspace_premium_rounded,
  ),
  'SCATTER': OlympusSymbolVisual(
    id: 'SCATTER',
    shape: GemShape.plate,
    color: Color(0xFFFFC93C),
    glow: Color(0xFFFFFFFF),
    assetName: 'symbol_scatter_zeus',
    icon: Icons.electric_bolt_rounded,
  ),
  'MULT': OlympusSymbolVisual(
    id: 'MULT',
    shape: GemShape.plate,
    color: Color(0xFFFFB300),
    glow: Color(0xFFB9E4FF),
    assetName: 'symbol_mult_orb',
    icon: Icons.bolt_rounded,
  ),
};

/// Backdrops and effect textures, keyed by the stem used in [OlympusArt].
const List<String> kOlympusFxAssets = [
  'fx_lightning_bolt',
  'fx_particle_spark',
  'fx_coin',
  'fx_burst_green',
  'fx_trumpet',
  // Drawn over a winning symbol while it is being counted, before it bursts.
  'fx_win_flame',
  'fx_explosion',
  // Plaque behind the tumble-win readout.
  'fx_tumble_banner',
];

const List<String> kOlympusSceneAssets = [
  'bg_olympus',
  'bg_olympus_bonus',
  'zeus',
  'zeus_strike',
  'zeus_celebrate',
  // The marble column Zeus stands on, drawn under him.
  'zeus_pedestal',
  'ornament_owl',
  'logo',
  // Ornate frame drawn over the board, replacing the painted meander.
  'frame_grid',
  // Parallax cloud layers, drifting at different speeds behind the board.
  'cloud_near',
  'cloud_far',
];

/// Loaded artwork for every symbol, the scene pieces and the effect textures.
/// Any missing file leaves its slot null and callers fall back to the painted
/// version, so a partial art delivery is always safe to drop in.
class OlympusArt {
  const OlympusArt(this.images, this.fx, this.scene);

  final Map<String, ui.Image?> images;
  final Map<String, ui.Image?> fx;
  final Map<String, ui.Image?> scene;

  static Future<ui.Image?> _load(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static Future<OlympusArt> load() async {
    const dir = 'assets/images/olympus';
    final entries = kOlympusSymbols.values.toList();

    final results = await Future.wait(entries.map((v) => _load('$dir/${v.assetName}.png')));
    final map = <String, ui.Image?>{};
    for (var i = 0; i < entries.length; i++) {
      map[entries[i].id] = results[i];
    }

    final fxResults = await Future.wait(kOlympusFxAssets.map((n) => _load('$dir/$n.png')));
    final fxMap = <String, ui.Image?>{};
    for (var i = 0; i < kOlympusFxAssets.length; i++) {
      fxMap[kOlympusFxAssets[i]] = fxResults[i];
    }

    final sceneResults =
        await Future.wait(kOlympusSceneAssets.map((n) => _load('$dir/$n.png')));
    final sceneMap = <String, ui.Image?>{};
    for (var i = 0; i < kOlympusSceneAssets.length; i++) {
      sceneMap[kOlympusSceneAssets[i]] = sceneResults[i];
    }

    return OlympusArt(map, fxMap, sceneMap);
  }

  ui.Image? forSymbol(String id) => images[id];
  ui.Image? forFx(String name) => fx[name];
  ui.Image? forScene(String name) => scene[name];
}

// ── Tile ─────────────────────────────────────────────────────────────────────

/// One board cell: real art if loaded, otherwise a painted gem or artefact.
///
/// [multValue] turns the tile into a lightning orb showing its face value, and
/// is the only case where the tile draws a number of its own.
class OlympusSymbolTile extends StatelessWidget {
  const OlympusSymbolTile({
    super.key,
    required this.symbol,
    required this.label,
    this.art,
    this.winFlame,
    this.badge,
    this.multValue,
    this.highlighted = false,
    this.dimmed = false,
    this.highContrast = false,
  });

  final String symbol;

  /// Localized name, for the accessibility label.
  final String label;
  final ui.Image? art;

  /// `fx_win_flame`, drawn over the symbol while it is winning. Null falls back
  /// to the plain glow, which is what ships until the texture is delivered.
  final ui.Image? winFlame;

  /// The word printed across the foot of the scatter tile, already localized.
  /// Drawn rather than baked into the artwork so it translates.
  final String? badge;
  final int? multValue;
  final bool highlighted;
  final bool dimmed;

  /// Stronger rims and a darker cell, for players who cannot separate the tile
  /// from the board at the default contrast.
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final visual = kOlympusSymbols[symbol];
    if (visual == null) return const SizedBox.shrink();

    final isMult = symbol == 'MULT';
    final isScatter = symbol == 'SCATTER';

    return Semantics(
      label: isMult && multValue != null ? '$label ×$multValue' : label,
      selected: highlighted,
      image: art != null,
      child: Opacity(
        opacity: dimmed ? 0.35 : 1.0,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.min(constraints.maxWidth, constraints.maxHeight);
            return Center(
              child: SizedBox(
                width: side,
                height: side,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Win glow sits behind the symbol so it never washes out the
                    // face colour the player is trying to count.
                    if (highlighted)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: visual.glow.withValues(alpha: 0.85),
                              blurRadius: side * 0.42,
                              spreadRadius: -side * 0.06,
                            ),
                          ],
                        ),
                      ),
                    if (art != null)
                      Padding(
                        padding: EdgeInsets.all(side * 0.06),
                        child: RawImage(image: art, fit: BoxFit.contain),
                      )
                    else
                      CustomPaint(
                        painter: _SymbolPainter(
                          visual: visual,
                          highlighted: highlighted,
                          highContrast: highContrast,
                        ),
                      ),
                    if (art == null && visual.icon != null && !isMult)
                      Center(
                        child: Icon(
                          visual.icon,
                          size: side * (isScatter ? 0.42 : 0.4),
                          color: isScatter ? Colors.white : const Color(0xFF3A1A05),
                          shadows: isScatter
                              ? const [Shadow(color: Color(0xFF64C8FF), blurRadius: 10)]
                              : null,
                        ),
                      ),
                    // Additive light on black, so it composites straight over
                    // whatever the symbol is without needing a matte.
                    if (highlighted && winFlame != null)
                      CustomPaint(painter: _FlamePainter(winFlame!)),
                    if (isScatter && (badge?.isNotEmpty ?? false)) _scatterBadge(side),
                    if (isMult && multValue != null) _multFace(side),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The SCATTER word, the one piece of text the reference art carries on a
  /// tile. Kept as drawn text rather than baked into the PNG so it translates.
  Widget _scatterBadge(double side) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: side * 0.05),
          child: FittedBox(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: side * 0.09, vertical: side * 0.02),
              decoration: BoxDecoration(
                color: const Color(0xCC1A0B36),
                borderRadius: BorderRadius.circular(side),
                border: Border.all(color: const Color(0xFFFFD24A), width: 0.8),
              ),
              child: Text(
                badge ?? '',
                style: const TextStyle(
                  color: Color(0xFFFFD24A),
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ),
      );

  /// The orb's face value, always LTR — "×25" reads the same in both languages
  /// and must never be reordered by the surrounding RTL chrome.
  /// The orb's face value, always LTR - "×25" reads the same in both languages
  /// and must never be reordered by the surrounding RTL chrome.
  ///
  /// Drawn as a dark stroke under a white fill rather than white-plus-glow. The
  /// delivered orb art has a near-white hot spot dead centre, which is exactly
  /// where this number sits, and a soft glow behind white text on white art is
  /// invisible. The stroke does not care what is underneath it.
  Widget _multFace(double side) {
    const size = 22.0;
    return Center(
      child: FittedBox(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: side * 0.14),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '×$multValue',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 4.5
                    ..strokeJoin = StrokeJoin.round
                    ..color = const Color(0xFF23104A),
                ),
              ),
              Text(
                '×$multValue',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: size,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the gem silhouette, its facets and its rim.
///
/// Every low symbol is a distinct convex polygon so the five of them can be
/// told apart by shape alone — which is also what makes the board legible to a
/// player who cannot separate the colours.
class _SymbolPainter extends CustomPainter {
  const _SymbolPainter({
    required this.visual,
    required this.highlighted,
    required this.highContrast,
  });

  final OlympusSymbolVisual visual;
  final bool highlighted;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final r = size.shortestSide * 0.40;

    final path = visual.shape == GemShape.plate
        ? _platePath(center, r)
        : _gemPath(visual.shape, center, r);

    // Body.
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            Color.lerp(visual.glow, Colors.white, 0.25)!,
            visual.color,
            Color.lerp(visual.color, Colors.black, 0.42)!,
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    // A single sweeping highlight across the upper-left face, which is what
    // makes a flat polygon read as cut glass.
    canvas.save();
    canvas.clipPath(path);
    final shine = Path()
      ..moveTo(center.dx - r, center.dy - r)
      ..lineTo(center.dx + r * 0.25, center.dy - r)
      ..lineTo(center.dx - r, center.dy + r * 0.35)
      ..close();
    canvas.drawPath(shine, Paint()..color = Colors.white.withValues(alpha: 0.26));
    canvas.restore();

    // Rim.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? r * 0.14 : (highContrast ? r * 0.11 : r * 0.07)
        ..color = highlighted
            ? Colors.white
            : (highContrast ? visual.glow : visual.glow.withValues(alpha: 0.7)),
    );
  }

  Path _gemPath(GemShape shape, Offset c, double r) {
    switch (shape) {
      case GemShape.diamond:
        return Path()
          ..moveTo(c.dx, c.dy - r * 1.15)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r * 1.15)
          ..lineTo(c.dx - r, c.dy)
          ..close();
      case GemShape.triangle:
        return _polygon(c, r * 1.12, 3, -math.pi / 2);
      case GemShape.hexagon:
        return _polygon(c, r * 1.05, 6, -math.pi / 2);
      case GemShape.pentagon:
        return _polygon(c, r * 1.08, 5, -math.pi / 2);
      case GemShape.square:
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: c, width: r * 1.75, height: r * 1.75),
              Radius.circular(r * 0.18),
            ),
          );
      case GemShape.plate:
        return _platePath(c, r);
    }
  }

  /// Premium symbols sit on a rounded gold-rimmed plate rather than a cut gem,
  /// which is what separates the four artefacts from the five gems at a glance.
  Path _platePath(Offset c, double r) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: r * 2.0, height: r * 2.0),
        Radius.circular(r * 0.42),
      ),
    );

  Path _polygon(Offset c, double r, int sides, double startAngle) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final a = startAngle + i * 2 * math.pi / sides;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _SymbolPainter old) =>
      old.visual.id != visual.id ||
      old.highlighted != highlighted ||
      old.highContrast != highContrast;
}

/// Draws the additive win-flame texture over a winning symbol.
class _FlamePainter extends CustomPainter {
  const _FlamePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) => old.image != image;
}

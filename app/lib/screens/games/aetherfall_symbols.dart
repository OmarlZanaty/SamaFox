import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Visual identity for every أثيرفول symbol.
///
/// No artwork exists yet, so each symbol renders as a simple painted glyph —
/// a coloured glass tile with a distinct icon and outline — until real art
/// lands (see AETHERFALL_ARTWORK_BRIEF.md at the repo root). [AetherfallArt]
/// loads the real PNGs when present and every call site falls back to the
/// painted glyph automatically, exactly like بلينكو's peg/ball art.
class SymbolVisual {
  const SymbolVisual({
    required this.id,
    required this.icon,
    required this.color,
    required this.glow,
    required this.assetName,
  });

  final String id;
  final IconData icon;
  final Color color;
  final Color glow;

  /// File stem under assets/images/aetherfall/, e.g. 'symbol_l1' →
  /// assets/images/aetherfall/symbol_l1.png.
  final String assetName;
}

const Map<String, SymbolVisual> kSymbolVisuals = {
  'L1': SymbolVisual(
    id: 'L1',
    icon: Icons.change_history_rounded,
    color: Color(0xFF4DD8E6),
    glow: Color(0xFF7FF0FF),
    assetName: 'symbol_l1',
  ),
  'L2': SymbolVisual(
    id: 'L2',
    icon: Icons.whatshot_rounded,
    color: Color(0xFFFF8A3D),
    glow: Color(0xFFFFC48A),
    assetName: 'symbol_l2',
  ),
  'L3': SymbolVisual(
    id: 'L3',
    icon: Icons.eco_rounded,
    color: Color(0xFF7CE8B0),
    glow: Color(0xFFB8FFDA),
    assetName: 'symbol_l3',
  ),
  'L4': SymbolVisual(
    id: 'L4',
    icon: Icons.brightness_2_rounded,
    color: Color(0xFF3E5AA8),
    glow: Color(0xFF7C93D9),
    assetName: 'symbol_l4',
  ),
  'H1': SymbolVisual(
    id: 'H1',
    icon: Icons.settings_rounded,
    color: Color(0xFFC98A4B),
    glow: Color(0xFFE8B77E),
    assetName: 'symbol_h1',
  ),
  'H2': SymbolVisual(
    id: 'H2',
    icon: Icons.favorite_rounded,
    color: Color(0xFFE85A3D),
    glow: Color(0xFFFF9A7A),
    assetName: 'symbol_h2',
  ),
  'H3': SymbolVisual(
    id: 'H3',
    icon: Icons.explore_rounded,
    color: Color(0xFF9C7BE8),
    glow: Color(0xFFCBB8FF),
    assetName: 'symbol_h3',
  ),
  'H4': SymbolVisual(
    id: 'H4',
    icon: Icons.diamond_rounded,
    color: Color(0xFFE6F3FF),
    glow: Color(0xFFB6D8FF),
    assetName: 'symbol_h4',
  ),
  'WILD': SymbolVisual(
    id: 'WILD',
    icon: Icons.hexagon_rounded,
    color: Color(0xFFFFFFFF),
    glow: Color(0xFFCFEFFF),
    assetName: 'symbol_wild',
  ),
  'KEY': SymbolVisual(
    id: 'KEY',
    icon: Icons.vpn_key_rounded,
    color: Color(0xFFCB9B5C),
    glow: Color(0xFF6FE3FF),
    assetName: 'symbol_key',
  ),
  'CHARGE': SymbolVisual(
    id: 'CHARGE',
    icon: Icons.bolt_rounded,
    color: Color(0xFFFF7A45),
    glow: Color(0xFFFFD08A),
    assetName: 'symbol_charge',
  ),
};

/// Display names for the paytable / help panel — original wording, not copied
/// from any published game.
const Map<String, String> kSymbolNames = {
  'L1': 'Cyan Rune Prism',
  'L2': 'Ember Shard',
  'L3': 'Mint Spiral Seed',
  'L4': 'Orbit Stone',
  'H1': 'Copper Astrolabe',
  'H2': 'Meteor-Heart Capsule',
  'H3': 'Aurora Compass',
  'H4': 'Skyfire Crown',
  'WILD': 'Prism Wild',
  'KEY': 'Vault Key',
  'CHARGE': 'Ember Charge',
};

/// Particle and ribbon textures, keyed by the stem used in [AetherfallArt.fx].
/// These are additive light on black, so they are drawn with [ui.BlendMode.plus]
/// and need no alpha of their own to look right over the board.
const List<String> kFxAssets = [
  'fx_particle_spark',
  'fx_particle_ember',
  'fx_ribbon_compass',
  'fx_constellation_thread',
  'fx_key_unlock',
];

/// Loaded artwork for every symbol plus the effect textures. Any missing file
/// leaves its slot null and callers fall back to the painted version.
class AetherfallArt {
  const AetherfallArt(this.images, this.fx);

  final Map<String, ui.Image?> images;

  /// Effect textures keyed by file stem, e.g. 'fx_particle_spark'.
  final Map<String, ui.Image?> fx;

  static Future<ui.Image?> _load(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static Future<AetherfallArt> load() async {
    const dir = 'assets/images/aetherfall';
    final entries = kSymbolVisuals.values.toList();
    final results = await Future.wait(
      entries.map((v) => _load('$dir/${v.assetName}.png')),
    );
    final map = <String, ui.Image?>{};
    for (var i = 0; i < entries.length; i++) {
      map[entries[i].id] = results[i];
    }

    final fxResults = await Future.wait(kFxAssets.map((n) => _load('$dir/$n.png')));
    final fxMap = <String, ui.Image?>{};
    for (var i = 0; i < kFxAssets.length; i++) {
      fxMap[kFxAssets[i]] = fxResults[i];
    }

    return AetherfallArt(map, fxMap);
  }

  ui.Image? forSymbol(String id) => images[id];
  ui.Image? forFx(String name) => fx[name];
}

/// One symbol tile: real art if loaded, otherwise a painted glass glyph.
class SymbolTile extends StatelessWidget {
  const SymbolTile({
    super.key,
    required this.symbol,
    this.art,
    this.chargeValue,
    this.highlighted = false,
    this.dimmed = false,
  });

  final String symbol;
  final ui.Image? art;
  final int? chargeValue;
  final bool highlighted;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final visual = kSymbolVisuals[symbol];
    if (visual == null) return const SizedBox.shrink();

    return Opacity(
      opacity: dimmed ? 0.35 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: RadialGradient(
            colors: [visual.color.withValues(alpha: 0.28), visual.color.withValues(alpha: 0.08)],
          ),
          border: Border.all(
            color: highlighted ? visual.glow : visual.color.withValues(alpha: 0.55),
            width: highlighted ? 2.4 : 1.2,
          ),
          boxShadow: highlighted
              ? [BoxShadow(color: visual.glow.withValues(alpha: 0.75), blurRadius: 16, spreadRadius: 1)]
              : [BoxShadow(color: visual.color.withValues(alpha: 0.25), blurRadius: 6)],
        ),
        child: Center(
          child: art != null
              ? RawImage(image: art, fit: BoxFit.contain, width: 34, height: 34)
              : symbol == 'CHARGE' && chargeValue != null
                  ? _chargeBadge(visual, chargeValue!)
                  : Icon(visual.icon, color: visual.color, size: 22),
        ),
      ),
    );
  }

  Widget _chargeBadge(SymbolVisual visual, int value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, color: visual.color, size: 15),
          Text(
            '+$value%',
            style: TextStyle(
              color: visual.glow,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Visual identity for every نيون فورتشن symbol.
///
/// No artwork exists yet, so each symbol renders as a painted glyph — a neon
/// plate with a distinct icon, letter or numeral — until real art lands (see
/// NEON_FORTUNE_ARTWORK_BRIEF.md at the repo root). [NeonArt] loads the real
/// PNGs when present and every call site falls back to the painted glyph
/// automatically, exactly like أثيرفول and بلينكو.
class NeonSymbolVisual {
  const NeonSymbolVisual({
    required this.id,
    required this.color,
    required this.glow,
    required this.assetName,
    this.icon,
    this.label,
  });

  final String id;
  final Color color;
  final Color glow;

  /// File stem under assets/images/neon/, e.g. 'symbol_tiger' →
  /// assets/images/neon/symbol_tiger.png.
  final String assetName;

  /// Painted fallback: an icon for the picture symbols…
  final IconData? icon;

  /// …or a letter/numeral for the card ranks.
  final String? label;
}

// Palette: midnight violet ground, cyan carrying the interactive states, gold
// held back for numbers and frames (design review §0.3 — the deliberate step
// away from the gold-dominant reference).
const Color kNeonInk = Color(0xFF17062E);
const Color kNeonPlum = Color(0xFF250A46);
const Color kNeonViolet = Color(0xFF8B22E8);
const Color kNeonMagenta = Color(0xFFEA35D7);
const Color kNeonCyan = Color(0xFF3CD7FF);
const Color kNeonGold = Color(0xFFFFC928);
const Color kNeonLime = Color(0xFF93E832);
const Color kNeonText = Color(0xFFFFF8FF);
const Color kNeonTextDim = Color(0xFFD7BDF2);

const Map<String, NeonSymbolVisual> kNeonSymbols = {
  'TIGER': NeonSymbolVisual(
    id: 'TIGER',
    icon: Icons.pets_rounded,
    color: Color(0xFFFF8A3D),
    glow: Color(0xFFFFC48A),
    assetName: 'symbol_tiger',
  ),
  'PANTHER': NeonSymbolVisual(
    id: 'PANTHER',
    icon: Icons.diamond_rounded,
    color: Color(0xFF9C7BE8),
    glow: Color(0xFFCBB8FF),
    assetName: 'symbol_panther',
  ),
  'CRANE': NeonSymbolVisual(
    id: 'CRANE',
    icon: Icons.flutter_dash_rounded,
    color: Color(0xFFF3E9FF),
    glow: Color(0xFFEA35D7),
    assetName: 'symbol_crane',
  ),
  'KOI': NeonSymbolVisual(
    id: 'KOI',
    icon: Icons.waves_rounded,
    color: Color(0xFF3CD7FF),
    glow: Color(0xFF9BEBFF),
    assetName: 'symbol_koi',
  ),
  'LANTERN': NeonSymbolVisual(
    id: 'LANTERN',
    icon: Icons.light_rounded,
    color: Color(0xFFFF6D54),
    glow: Color(0xFFFFA894),
    assetName: 'symbol_lantern',
  ),
  'COIN': NeonSymbolVisual(
    id: 'COIN',
    icon: Icons.stars_rounded,
    color: Color(0xFFFFC928),
    glow: Color(0xFFFFE79B),
    assetName: 'symbol_coin',
  ),
  'A': NeonSymbolVisual(
    id: 'A',
    label: 'A',
    color: Color(0xFFFFC928),
    glow: Color(0xFFEA35D7),
    assetName: 'symbol_a',
  ),
  'K': NeonSymbolVisual(
    id: 'K',
    label: 'K',
    color: Color(0xFFFFC928),
    glow: Color(0xFF3CD7FF),
    assetName: 'symbol_k',
  ),
  'Q': NeonSymbolVisual(
    id: 'Q',
    label: 'Q',
    color: Color(0xFFFFC928),
    glow: Color(0xFF8B22E8),
    assetName: 'symbol_q',
  ),
  'J': NeonSymbolVisual(
    id: 'J',
    label: 'J',
    color: Color(0xFFFFC928),
    glow: Color(0xFF5B8CFF),
    assetName: 'symbol_j',
  ),
  'TEN': NeonSymbolVisual(
    id: 'TEN',
    label: '10',
    color: Color(0xFFFFC928),
    glow: Color(0xFFEA35D7),
    assetName: 'symbol_10',
  ),
  'WILD': NeonSymbolVisual(
    id: 'WILD',
    icon: Icons.visibility_rounded,
    color: Color(0xFF93E832),
    glow: Color(0xFFD3FF95),
    assetName: 'symbol_wild',
  ),
  'SCATTER': NeonSymbolVisual(
    id: 'SCATTER',
    icon: Icons.confirmation_number_rounded,
    color: Color(0xFFEA35D7),
    glow: Color(0xFFFFA6F2),
    assetName: 'symbol_scatter',
  ),
  'TOKEN': NeonSymbolVisual(
    id: 'TOKEN',
    icon: Icons.token_rounded,
    color: Color(0xFF3CD7FF),
    glow: Color(0xFFFFC928),
    assetName: 'symbol_token',
  ),
};

/// Arabic names, used by the paytable and the help sheet.
const Map<String, String> kNeonSymbolNames = {
  'TIGER': 'حارس النمر',
  'PANTHER': 'الفهد البلوري',
  'CRANE': 'كركي الحظ',
  'KOI': 'سمكة النيون',
  'LANTERN': 'فانوس الحظ',
  'COIN': 'عملة النجمة',
  'A': 'A',
  'K': 'K',
  'Q': 'Q',
  'J': 'J',
  'TEN': '10',
  'WILD': 'الرمز البديل',
  'SCATTER': 'رمز الانتشار',
  'TOKEN': 'رمز الجائزة',
};

/// The four pools, in ladder order. Themed names rather than the genre's
/// MINI/MINOR/MAJOR/GRAND ladder — design review D5.
const List<String> kJackpotTiers = ['SPARK', 'GLOW', 'BEACON', 'CITY'];

const Map<String, String> kJackpotNames = {
  'SPARK': 'شرارة',
  'GLOW': 'وهج',
  'BEACON': 'منارة',
  'CITY': 'مدينة',
};

const Map<String, Color> kJackpotColors = {
  'SPARK': Color(0xFF93E832),
  'GLOW': Color(0xFF3CD7FF),
  'BEACON': Color(0xFFEA35D7),
  'CITY': Color(0xFFFFC928),
};

const Map<String, IconData> kJackpotIcons = {
  'SPARK': Icons.bolt_rounded,
  'GLOW': Icons.blur_on_rounded,
  'BEACON': Icons.lightbulb_rounded,
  'CITY': Icons.location_city_rounded,
};

/// Loaded artwork for every symbol, keyed by symbol id. Any missing file leaves
/// its slot null and callers fall back to the painted glyph.
class NeonArt {
  const NeonArt(this.images);

  final Map<String, ui.Image?> images;

  static Future<ui.Image?> _load(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static Future<NeonArt> load() async {
    const dir = 'assets/images/neon';
    final entries = kNeonSymbols.values.toList();
    final results = await Future.wait(entries.map((v) => _load('$dir/${v.assetName}.png')));
    final map = <String, ui.Image?>{};
    for (var i = 0; i < entries.length; i++) {
      map[entries[i].id] = results[i];
    }
    return NeonArt(map);
  }

  ui.Image? forSymbol(String id) => images[id];
}

/// One reel cell: real art if loaded, otherwise a painted neon plate.
class NeonSymbolTile extends StatelessWidget {
  const NeonSymbolTile({
    super.key,
    required this.symbol,
    this.art,
    this.highlighted = false,
    this.dimmed = false,
    this.multiplier,
    this.compact = false,
  });

  final String symbol;
  final ui.Image? art;
  final bool highlighted;
  final bool dimmed;

  /// Printed on a wild during Skyline Rush, e.g. ×3.
  final int? multiplier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = kNeonSymbols[symbol];
    if (visual == null) return const SizedBox.shrink();

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: dimmed ? 0.32 : 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.maxHeight.isFinite ? box.maxHeight : 48.0;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 7 : 10),
              gradient: RadialGradient(
                colors: [
                  visual.color.withValues(alpha: highlighted ? 0.38 : 0.22),
                  kNeonPlum.withValues(alpha: 0.85),
                ],
              ),
              border: Border.all(
                color: highlighted ? visual.glow : visual.color.withValues(alpha: 0.45),
                width: highlighted ? 2.2 : 1,
              ),
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: visual.glow.withValues(alpha: 0.7),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (art != null)
                  RawImage(image: art, fit: BoxFit.contain, width: size * 0.74, height: size * 0.74)
                else if (visual.label != null)
                  Text(
                    visual.label!,
                    style: TextStyle(
                      color: visual.color,
                      fontSize: size * (visual.label!.length > 1 ? 0.38 : 0.46),
                      fontWeight: FontWeight.w900,
                      height: 1,
                      shadows: [Shadow(color: visual.glow, blurRadius: 12)],
                    ),
                  )
                else
                  Icon(visual.icon, color: visual.color, size: size * 0.46),
                if (multiplier != null && multiplier! > 1)
                  Positioned(
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: kNeonInk.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kNeonLime.withValues(alpha: 0.8)),
                      ),
                      child: Text(
                        '×${multiplier!}',
                        style: const TextStyle(
                          color: kNeonLime,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
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

/// Formats coins the way the rest of the app does: 12,500 → 12.5K.
String neonCoins(int value) {
  if (value >= 1000000) {
    final m = value / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
  }
  if (value >= 10000) return '${(value / 1000).toStringAsFixed(value >= 100000 ? 0 : 1)}K';
  return value.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
}

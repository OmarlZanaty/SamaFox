import 'package:flutter/material.dart';

import 'asterion_art.dart';

/// The 6×5 pay-anywhere board, framed by the citadel's stone and storm-metal.
///
/// Purely presentational: [AsterionScreen] owns the timing of the deal, the
/// highlight, the burst and the refill, and this renders whatever state it is
/// handed, animating implicitly between calls.
class AsterionBoard extends StatelessWidget {
  const AsterionBoard({
    super.key,
    required this.cols,
    required this.rows,
    required this.grid,
    this.orbs = const {},
    this.highlighted = const {},
    this.clearing = const {},
    this.collectedOrbs = false,
    this.highContrast = false,
    this.reducedMotion = false,
  });

  final int cols, rows;

  /// Symbol id per cell, row-major; null = an empty cell mid-cascade.
  final List<String?> grid;

  /// Cell index → Storm Orb face value, for the orbs pinned to the board.
  final Map<int, int> orbs;

  final Set<int> highlighted;
  final Set<int> clearing;

  /// True once the orbs on the board have been swept into the meter.
  final bool collectedOrbs;

  final bool highContrast;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: cols / rows,
      child: LayoutBuilder(
        builder: (context, box) {
          final cell = box.maxWidth / cols;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: RadialGradient(
                colors: highContrast
                    ? const [Color(0xFF04060F), Color(0xFF04060F)]
                    : [
                        AsterionPalette.cyan.withValues(alpha: 0.16),
                        AsterionPalette.nightDeep.withValues(alpha: 0.86),
                      ],
              ),
              border: Border.all(
                color: highContrast
                    ? Colors.white70
                    : AsterionPalette.silverDeep.withValues(alpha: 0.75),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: AsterionPalette.cyan.withValues(alpha: 0.18),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cols * rows,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemBuilder: (context, i) {
                  final symbol = grid.length > i ? grid[i] : null;
                  final isClearing = clearing.contains(i);
                  final orb = orbs[i];

                  return AnimatedScale(
                    duration: Duration(milliseconds: reducedMotion ? 90 : 240),
                    curve: isClearing ? Curves.easeIn : Curves.easeOutBack,
                    scale: isClearing ? 0.2 : 1.0,
                    child: AnimatedOpacity(
                      duration: Duration(milliseconds: reducedMotion ? 80 : 200),
                      opacity: isClearing ? 0.0 : (symbol == null ? 0.0 : 1.0),
                      child: symbol == null
                          ? const SizedBox.shrink()
                          : orb != null
                              ? _OrbCell(value: orb, size: cell, collected: collectedOrbs)
                              : SymbolTile(
                                  symbol: symbol,
                                  size: cell,
                                  highlighted: highlighted.contains(i),
                                  highContrast: highContrast,
                                ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One symbol in its chamber. The chamber is what makes a 6×5 grid readable:
/// the tile edge tells the eye where one symbol ends, at any density.
class SymbolTile extends StatelessWidget {
  const SymbolTile({
    super.key,
    required this.symbol,
    required this.size,
    this.highlighted = false,
    this.highContrast = false,
  });

  final String symbol;
  final double size;
  final bool highlighted;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final info = kAsterionSymbols[symbol];
    if (info == null) return const SizedBox.shrink();

    return Semantics(
      label: info.name,
      selected: highlighted,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: highContrast
                ? const [Color(0xFF05060F), Color(0xFF05060F)]
                : [
                    info.colour.withValues(alpha: highlighted ? 0.38 : 0.20),
                    AsterionPalette.nightDeep.withValues(alpha: 0.55),
                  ],
          ),
          border: Border.all(
            color: highlighted
                ? (highContrast ? Colors.white : info.glow)
                : info.colour.withValues(alpha: highContrast ? 0.95 : 0.35),
            width: highlighted ? (highContrast ? 3.0 : 2.2) : (highContrast ? 2.0 : 1.0),
          ),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: info.glow.withValues(alpha: 0.7),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Center(child: SymbolIcon(symbol, size: size * 0.74)),
      ),
    );
  }
}

/// A pinned Storm Orb. It sits in its own chamber so it is obvious that the
/// cell is occupied but not matchable.
class _OrbCell extends StatelessWidget {
  const _OrbCell({required this.value, required this.size, required this.collected});

  final int value;
  final double size;
  final bool collected;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'كرة عاصفة، $value ضعف',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: RadialGradient(
              colors: [
                AsterionPalette.magenta.withValues(alpha: collected ? 0.18 : 0.42),
                AsterionPalette.nightDeep.withValues(alpha: 0.7),
              ],
            ),
            border: Border.all(
              color: collected
                  ? AsterionPalette.silverDeep
                  : AsterionPalette.cyanPale.withValues(alpha: 0.9),
              width: 1.8,
            ),
            boxShadow: collected
                ? null
                : [
                    BoxShadow(
                      color: AsterionPalette.magenta.withValues(alpha: 0.55),
                      blurRadius: 18,
                    ),
                  ],
          ),
          child: Center(
            child: StormOrb(value: value, size: size * 0.86, collected: collected),
          ),
        ),
      );
}

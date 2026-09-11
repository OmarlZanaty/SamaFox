import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'olympus_symbols.dart';

const _gold = Color(0xFFE3B84A);
const _goldDim = Color(0xFF8A6A22);
const _violet = Color(0xFF3B1D6E);

/// The 6×5 pay-anywhere board, inside an ornate purple-and-gold frame.
///
/// Purely presentational: [OlympusScreen] owns the timing of the deal, the
/// highlight, the burst and the refill, and this renders whatever state it is
/// handed. Cells animate themselves — a symbol that changes identity falls in
/// from above, which is what makes a cascade read as a tumble rather than a
/// dissolve.
///
/// The board is always laid out LTR even when the app is in Arabic. A
/// pay-anywhere grid has no reading order, so mirroring it would gain nothing
/// and would move the board off-centre against Zeus on the right.
class OlympusGrid extends StatelessWidget {
  const OlympusGrid({
    super.key,
    required this.cols,
    required this.rows,
    required this.grid,
    required this.nameOf,
    required this.scatterBadge,
    this.highlighted = const {},
    this.clearing = const {},
    this.multValues = const {},
    this.reducedMotion = false,
    this.highContrast = false,
    this.art,
  });

  final int cols, rows;

  /// Symbol id per cell, row-major; null = an empty gap mid-cascade.
  final List<String?> grid;

  /// Localized symbol name, for accessibility labels.
  final String Function(String id) nameOf;

  /// Localized word for the scatter tile's badge.
  final String scatterBadge;

  final Set<int> highlighted;
  final Set<int> clearing;

  /// Board index → lightning multiplier face value.
  final Map<int, int> multValues;

  final bool reducedMotion;
  final bool highContrast;
  final OlympusArt? art;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: cols / rows,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xE62A1258), Color(0xE6160831)],
          ),
          border: Border.all(color: _gold.withValues(alpha: 0.75), width: 2),
          boxShadow: [
            BoxShadow(color: _violet.withValues(alpha: 0.6), blurRadius: 26, spreadRadius: 2),
            BoxShadow(color: _gold.withValues(alpha: 0.18), blurRadius: 10, spreadRadius: -2),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Delivered frame art replaces the painted meander outright — the
            // two would fight each other if both were drawn.
            Positioned.fill(
              child: IgnorePointer(
                child: art?.forScene('frame_grid') != null
                    ? CustomPaint(painter: _FrameArtPainter(art!.forScene('frame_grid')!))
                    : const _FrameOrnament(),
              ),
            ),
            LayoutBuilder(
              builder: (context, outer) {
                // Delivered frame art has its own aperture, and it is not the
                // uniform 8px the painted frame wants: the meander rails on top
                // and bottom are far thicker than the side ropes. These
                // fractions are measured from frame_grid.png, so the symbols sit
                // inside the opening instead of spilling over the gold.
                final framed = art?.forScene('frame_grid') != null;
                final pad = framed
                    ? EdgeInsets.fromLTRB(
                        outer.maxWidth * 0.048,
                        outer.maxHeight * 0.188,
                        outer.maxWidth * 0.050,
                        outer.maxHeight * 0.209,
                      )
                    : const EdgeInsets.all(8);
                return Padding(
                  padding: pad,
                  child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellW = constraints.maxWidth / cols;
                  final cellH = constraints.maxHeight / rows;
                  return Stack(
                    children: [
                      for (var i = 0; i < cols * rows; i++)
                        Positioned(
                          left: (i % cols) * cellW,
                          top: (i ~/ cols) * cellH,
                          width: cellW,
                          height: cellH,
                          child: Padding(
                            padding: EdgeInsets.all(cellW * 0.04),
                            child: _Cell(
                              index: i,
                              symbol: grid.length > i ? grid[i] : null,
                              multValue: multValues[i],
                              highlighted: highlighted.contains(i),
                              clearing: clearing.contains(i),
                              reducedMotion: reducedMotion,
                              highContrast: highContrast,
                              nameOf: nameOf,
                              art: art,
                              winFlame: art?.forFx('fx_win_flame'),
                              scatterBadge: scatterBadge,
                            ),
                          ),
                        ),
                    ],
                  );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One cell. Owns its own drop-in animation so the parent can stay a plain
/// stateless render of the current board.
class _Cell extends StatefulWidget {
  const _Cell({
    required this.index,
    required this.symbol,
    required this.multValue,
    required this.highlighted,
    required this.clearing,
    required this.reducedMotion,
    required this.highContrast,
    required this.nameOf,
    required this.art,
    required this.winFlame,
    required this.scatterBadge,
  });

  final int index;
  final String? symbol;
  final int? multValue;
  final bool highlighted, clearing, reducedMotion, highContrast;
  final String Function(String id) nameOf;
  final OlympusArt? art;
  final ui.Image? winFlame;
  final String scatterBadge;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> with SingleTickerProviderStateMixin {
  late final AnimationController _drop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.symbol != null) _drop.forward(from: widget.reducedMotion ? 1 : 0);
  }

  @override
  void didUpdateWidget(covariant _Cell old) {
    super.didUpdateWidget(old);
    // A cell whose symbol changed identity is a *new* symbol that has just
    // fallen into place — replay the drop. A cell that only changed highlight
    // or multiplier value has not moved and must not re-animate.
    final arrived = widget.symbol != null && widget.symbol != old.symbol;
    if (arrived) _drop.forward(from: widget.reducedMotion ? 1 : 0);
  }

  @override
  void dispose() {
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = widget.symbol;
    if (symbol == null) return const SizedBox.shrink();

    final tile = OlympusSymbolTile(
      symbol: symbol,
      label: widget.nameOf(symbol),
      art: widget.art?.forSymbol(symbol),
      winFlame: widget.winFlame,
      badge: symbol == 'SCATTER' ? widget.scatterBadge : null,
      multValue: widget.multValue,
      highlighted: widget.highlighted,
      highContrast: widget.highContrast,
    );

    return AnimatedOpacity(
      duration: Duration(milliseconds: widget.reducedMotion ? 90 : 200),
      opacity: widget.clearing ? 0 : 1,
      child: AnimatedScale(
        duration: Duration(milliseconds: widget.reducedMotion ? 90 : 240),
        curve: widget.clearing ? Curves.easeIn : Curves.easeOut,
        scale: widget.clearing ? 0.2 : 1,
        child: AnimatedBuilder(
          animation: _drop,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_drop.value);
            return FractionalTranslation(
              translation: Offset(0, -(1 - t) * 1.15),
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
            );
          },
          child: widget.highlighted && !widget.reducedMotion
              ? _WinPulse(child: tile)
              : tile,
        ),
      ),
    );
  }
}

/// A winning symbol breathes until it bursts, so the player can see what is
/// being counted before it leaves the board.
class _WinPulse extends StatefulWidget {
  const _WinPulse({required this.child});
  final Widget child;

  @override
  State<_WinPulse> createState() => _WinPulseState();
}

class _WinPulseState extends State<_WinPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.12).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        ),
        child: widget.child,
      );
}

/// Greek key meander along the top and bottom rails, plus corner rosettes —
/// the cheapest way to make a plain rounded rectangle read as an Olympus gate.
class _FrameOrnament extends StatelessWidget {
  const _FrameOrnament();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _OrnamentPainter());
}

class _OrnamentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = _gold.withValues(alpha: 0.34);

    // Meander band, drawn as a repeating key motif inset from each long rail.
    const inset = 3.5;
    final step = size.width / 26;
    for (final top in [true, false]) {
      final y = top ? inset : size.height - inset;
      final dir = top ? 1.0 : -1.0;
      final path = Path();
      for (var x = step; x < size.width - step; x += step * 2) {
        path
          ..moveTo(x, y)
          ..lineTo(x, y + dir * step * 0.55)
          ..lineTo(x + step * 0.9, y + dir * step * 0.55)
          ..lineTo(x + step * 0.9, y + dir * step * 0.22);
      }
      canvas.drawPath(path, stroke);
    }

    // Corner rosettes.
    final fill = Paint()..color = _goldDim.withValues(alpha: 0.5);
    for (final c in [
      const Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      canvas.drawCircle(c, 7, fill);
      canvas.drawCircle(c, 7, stroke);
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3;
        canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * 7, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrnamentPainter oldDelegate) => false;
}

/// Blits the delivered frame artwork over the board.
class _FrameArtPainter extends CustomPainter {
  const _FrameArtPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _FrameArtPainter old) => old.image != image;
}

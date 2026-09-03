import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'aetherfall_symbols.dart';

/// The 6×5 pay-anywhere board, drawn as glassy chambers inside a circular
/// compass frame. This widget is purely presentational — [AetherfallScreen]
/// owns the timing of population, highlight, dissolve and refill; this just
/// renders whatever state it is handed and animates implicitly between calls.
class AetherfallGrid extends StatelessWidget {
  const AetherfallGrid({
    super.key,
    required this.cols,
    required this.rows,
    required this.grid,
    this.highlighted = const {},
    this.clearing = const {},
    this.chargeValues = const {},
    this.locked = const {},
    this.highContrast = false,
    this.shapeCoded = false,
    this.art,
  });

  final int cols, rows;

  /// Symbol id per cell, row-major; null = empty (mid-cascade gap).
  final List<String?> grid;
  final Set<int> highlighted;
  final Set<int> clearing;
  final Map<int, int> chargeValues;

  /// Cells pinned by a Constellation Lock, marked with a thread.
  final Set<int> locked;
  final bool highContrast;
  final bool shapeCoded;
  final AetherfallArt? art;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: cols / rows,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating compass ring — pure decoration behind the chambers.
          const Positioned.fill(
            child: IgnorePointer(child: _CompassRing()),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const RadialGradient(
                colors: [Color(0x334DD8E6), Color(0x110B1030)],
              ),
              border: Border.all(color: const Color(0x554DD8E6)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cols * rows,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                ),
                itemBuilder: (context, i) {
                  final symbol = grid[i];
                  final isClearing = clearing.contains(i);
                  return AnimatedScale(
                    duration: const Duration(milliseconds: 260),
                    curve: isClearing ? Curves.easeIn : Curves.elasticOut,
                    scale: isClearing ? 0.15 : 1.0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: isClearing ? 0.0 : (symbol == null ? 0.0 : 1.0),
                      child: symbol == null
                          ? const SizedBox.shrink()
                          : _maybeLocked(
                              locked.contains(i),
                              SymbolTile(
                                symbol: symbol,
                                art: art?.forSymbol(symbol),
                                chargeValue: chargeValues[i],
                                highlighted: highlighted.contains(i),
                                highContrast: highContrast,
                                shapeCoded: shapeCoded,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A pinned cell wears a mint constellation thread across its foot, so the
  /// player can see which symbol is being held in place for the next tumble.
  Widget _maybeLocked(bool isLocked, Widget tile) {
    if (!isLocked) return tile;
    final thread = art?.forFx('fx_constellation_thread');
    return Stack(
      fit: StackFit.expand,
      children: [
        tile,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF7CE8B0), width: 2.4),
              boxShadow: const [
                BoxShadow(color: Color(0x807CE8B0), blurRadius: 10, spreadRadius: -1),
              ],
            ),
          ),
        ),
        if (thread != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 0.9,
              child: AspectRatio(
                aspectRatio: 2,
                child: CustomPaint(painter: _LockThreadPainter(thread)),
              ),
            ),
          ),
        // A pin badge, so a locked cell is unmistakable even against a tile
        // whose own colour is close to mint.
        const Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFF7CE8B0)),
          ),
        ),
      ],
    );
  }
}

class _LockThreadPainter extends CustomPainter {
  const _LockThreadPainter(this.image);

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
  bool shouldRepaint(covariant _LockThreadPainter old) => old.image != image;
}

class _CompassRing extends StatefulWidget {
  const _CompassRing();

  @override
  State<_CompassRing> createState() => _CompassRingState();
}

class _CompassRingState extends State<_CompassRing> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: CustomPaint(painter: _CompassPainter()),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 * 1.04;
    final paint = Paint()
      ..color = const Color(0x334DD8E6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, paint);
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final long = i % 6 == 0;
      final inner = radius - (long ? 10 : 5);
      final p1 = center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      final p2 = center + Offset(inner * math.cos(angle), inner * math.sin(angle));
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) => false;
}

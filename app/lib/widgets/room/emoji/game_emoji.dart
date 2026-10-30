import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The two "game" emojis, drawn in code (no raster art).
///
/// [result] is the server's draw (dice 1–6, slot 0–2). While [rollPhase] is
/// not null (0–1) the emoji is still rolling and shows changing faces; once it
/// is null the result is held. Without a result (the picker) a sample face is
/// shown.
class GameEmoji extends StatelessWidget {
  const GameEmoji({super.key, required this.id, required this.size, this.result, this.rollPhase});

  final String id;
  final double size;
  final int? result;
  final double? rollPhase;

  @override
  Widget build(BuildContext context) {
    final rolling = rollPhase;
    if (id == 'dice') {
      final face = rolling != null ? 1 + (rolling * 17).floor() % 6 : (result ?? 5);
      final angle = rolling != null ? rolling * 4 * math.pi * (1 - rolling * .5) : 0.0;
      return SizedBox(
        width: size,
        height: size,
        child: Transform.rotate(
          angle: angle,
          child: CustomPaint(painter: _DicePainter(face.clamp(1, 6))),
        ),
      );
    }
    final reels = rolling != null
        ? [for (var i = 0; i < 3; i++) ((rolling * 23).floor() + i * 2) % kSlotSymbols.length]
        : List.filled(3, (result ?? 2).clamp(0, kSlotSymbols.length - 1));
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SlotPainter(reels, rolling)),
    );
  }
}

/// Slot outcomes 0–2, the same symbol on all three reels.
const kSlotSymbols = ['🍒', '🍋', '7'];

class _DicePainter extends CustomPainter {
  _DicePainter(this.face);
  final int face;

  static const _pips = <int, List<Offset>>{
    1: [Offset(.5, .5)],
    2: [Offset(.27, .27), Offset(.73, .73)],
    3: [Offset(.27, .27), Offset(.5, .5), Offset(.73, .73)],
    4: [Offset(.27, .27), Offset(.73, .27), Offset(.27, .73), Offset(.73, .73)],
    5: [Offset(.27, .27), Offset(.73, .27), Offset(.5, .5), Offset(.27, .73), Offset(.73, .73)],
    6: [Offset(.27, .25), Offset(.73, .25), Offset(.27, .5), Offset(.73, .5), Offset(.27, .75), Offset(.73, .75)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cube = Rect.fromCenter(center: size.center(Offset.zero), width: s * .82, height: s * .82);
    final r = RRect.fromRectAndRadius(cube, Radius.circular(s * .18));
    canvas.drawRRect(r.shift(Offset(0, s * .04)), Paint()..color = Colors.black.withValues(alpha: .35));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFDCDDE6)],
        ).createShader(cube),
    );
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .025
      ..color = const Color(0xFFB9BBC8));
    final pip = Paint()..color = face == 1 ? const Color(0xFFE11D48) : const Color(0xFF1F1B2E);
    for (final p in _pips[face]!) {
      canvas.drawCircle(
        Offset(cube.left + p.dx * cube.width, cube.top + p.dy * cube.height),
        s * (face == 1 ? .1 : .068),
        pip,
      );
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) => old.face != face;
}

class _SlotPainter extends CustomPainter {
  _SlotPainter(this.reels, this.rollPhase);
  final List<int> reels;
  final double? rollPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final body = Rect.fromCenter(center: size.center(Offset.zero), width: s * .92, height: s * .62);
    final rr = RRect.fromRectAndRadius(body, Radius.circular(s * .12));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD86B), Color(0xFFB7791F)],
        ).createShader(body),
    );
    final reelW = body.width * .27;
    final gap = (body.width - reelW * 3) / 4;
    for (var i = 0; i < 3; i++) {
      final reel = Rect.fromLTWH(body.left + gap + i * (reelW + gap), body.top + body.height * .14,
          reelW, body.height * .72);
      canvas.drawRRect(RRect.fromRectAndRadius(reel, Radius.circular(s * .05)),
          Paint()..color = Colors.white);
      final symbol = kSlotSymbols[reels[i]];
      final tp = TextPainter(
        text: TextSpan(
          text: symbol,
          style: TextStyle(
            fontSize: reelW * .72,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFE11D48),
            decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // While rolling the symbols slide down through the reel window.
      final slide = rollPhase != null ? ((rollPhase! * 23 + i * .3) % 1 - .5) * reel.height * .5 : 0.0;
      canvas.save();
      canvas.clipRect(reel);
      tp.paint(canvas, reel.center - Offset(tp.width / 2, tp.height / 2 - slide));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SlotPainter old) => true;
}

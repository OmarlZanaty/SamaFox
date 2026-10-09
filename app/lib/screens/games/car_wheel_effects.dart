import 'dart:math';
import 'package:flutter/material.dart';
import 'car_wheel_art.dart';

class CarWheelFloatingWin extends StatelessWidget {
  final String text;
  const CarWheelFloatingWin({super.key, required this.text});
  @override
  Widget build(BuildContext context) => IgnorePointer(
          child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1200),
          builder: (_, t, child) => Opacity(
              opacity: (1 - t).clamp(0, 1),
              child: Transform.translate(
                  offset: Offset(0, -35 * t), child: child,),),
          child: Text(text,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  color: cwGoldLight,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: Color(0xFF481421), offset: Offset(0, 2)),
                  ],),),
        ),
      ),);
}

/// A chip thrown from the dock to where it was placed: an arc with a little
/// bounce. Each flight owns its animation, so several can be in the air without
/// rebuilding the screen.
class CarWheelFlyingChip extends StatelessWidget {
  final Offset from, to;
  final int amount;
  final VoidCallback onDone;
  const CarWheelFlyingChip({
    super.key,
    required this.from,
    required this.to,
    required this.amount,
    required this.onDone,
  });

  static const size = 34.0;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        onEnd: onDone,
        builder: (_, t, child) {
          final e = Curves.easeOutCubic.transform(t);
          final p = Offset.lerp(from, to, e)! +
              Offset(0, -sin(e * pi) * (from - to).distance * .28);
          final s = t < .85 ? .7 + .4 * e : 1.1 - (t - .85) / .15 * .1;
          return Positioned(
            left: p.dx - size / 2,
            top: p.dy - size / 2,
            child:
                RepaintBoundary(child: Transform.scale(scale: s, child: child)),
          );
        },
        child: IgnorePointer(
          child: CarWheelChip(amount: amount, size: size, glow: true),
        ),
      );
}

/// Coins bursting out of a point and falling away; one painter, fixed pool.
class CarWheelCoinBurst extends StatelessWidget {
  final bool big;
  const CarWheelCoinBurst({super.key, this.big = false});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: big ? 2200 : 1400),
            builder: (_, t, __) => CustomPaint(
              size: Size.infinite,
              painter: _BurstPainter(t, big ? 70 : 12),
            ),
          ),
        ),
      );
}

class _BurstPainter extends CustomPainter {
  final double t;
  final int count;
  _BurstPainter(this.t, this.count);

  @override
  void paint(Canvas c, Size size) {
    final origin = Offset(size.width / 2, size.height * .42);
    for (var i = 0; i < count; i++) {
      final a = i * 2.399963;
      final v = size.width * (.25 + (i * 37 % 100) / 100 * .45);
      final spin = (i * 13 % 60) / 10;
      final r = size.width * (.012 + (i * 17 % 100) / 100 * .012);
      final p = origin +
          Offset(
            cos(a) * v * t,
            sin(a) * v * t * .7 + size.height * .55 * t * t,
          );
      final fade = (1 - t).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      // A coin seen edge-on as it turns: squash its width.
      final squash = (cos(spin + t * 14)).abs().clamp(.25, 1.0);
      final rect =
          Rect.fromCenter(center: p, width: r * 2 * squash, height: r * 2);
      c.drawOval(
        rect,
        Paint()..color = const Color(0xFFB8741C).withValues(alpha: fade),
      );
      c.drawOval(
        rect.deflate(r * .22),
        Paint()..color = cwGold.withValues(alpha: fade),
      );
      c.drawOval(
        Rect.fromCenter(
          center: p - Offset(r * .25 * squash, r * .3),
          width: r * .6 * squash,
          height: r * .45,
        ),
        Paint()..color = Colors.white.withValues(alpha: .7 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Rises from below and settles: the result plaque.
class CarWheelPopIn extends StatelessWidget {
  final Widget child;
  final bool reduced, shake;
  const CarWheelPopIn({
    super.key,
    required this.child,
    this.reduced = false,
    this.shake = false,
  });

  @override
  Widget build(BuildContext context) => reduced
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          builder: (_, t, c) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(
                shake ? sin(t * 55) * 4 * (1 - t).clamp(0, 1) : 0,
                24 * (1 - t),
              ),
              child: Transform.scale(scale: .85 + .15 * t, child: c),
            ),
          ),
          child: child,
        );
}

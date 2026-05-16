import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Canvas-painted fireworks overlay for legendary gifts.
/// Performance:
///  - Hard cap 300 particles on screen
///  - Wrapped in RepaintBoundary by the consumer
///  - Reduces budget on low-end devices via [reducedQuality]
class FireworksOverlay extends StatefulWidget {
  const FireworksOverlay({
    super.key,
    required this.palette,
    required this.duration,
    this.burstCount = 4,
    this.reducedQuality = false,
    this.onComplete,
  });

  final List<Color> palette;
  final Duration duration;
  final int burstCount;
  final bool reducedQuality;
  final VoidCallback? onComplete;

  @override
  State<FireworksOverlay> createState() => _FireworksOverlayState();
}

class _FireworksOverlayState extends State<FireworksOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Particle> _particles = [];
  final math.Random _rand = math.Random();
  Duration? _last;
  Duration _elapsed = Duration.zero;
  final Set<int> _firedBursts = {};
  bool _completed = false;

  int get _particlesPerBurst => widget.reducedQuality ? 25 : 50;
  int get _maxParticles => widget.reducedQuality ? 150 : 300;
  int get _effectiveBurstCount => widget.reducedQuality ? 2 : widget.burstCount;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration now) {
    final last = _last;
    _last = now;
    if (last == null) return;
    final dt = (now - last).inMicroseconds / 1e6;
    _elapsed = _elapsed + (now - last);
    _scheduleBursts();
    _step(dt);
    if (mounted) setState(() {});
    if (_elapsed >= widget.duration && _particles.isEmpty && !_completed) {
      _completed = true;
      widget.onComplete?.call();
      _ticker.stop();
    }
  }

  void _scheduleBursts() {
    final totalMs = widget.duration.inMilliseconds;
    if (totalMs <= 0) return;
    for (int i = 0; i < _effectiveBurstCount; i++) {
      if (_firedBursts.contains(i)) continue;
      final triggerAt = (totalMs / _effectiveBurstCount) * i;
      if (_elapsed.inMilliseconds >= triggerAt) {
        _spawnBurst();
        _firedBursts.add(i);
      }
    }
  }

  void _spawnBurst() {
    final size = context.size ?? const Size(360, 640);
    final origin = Offset(
      _rand.nextDouble() * size.width * 0.6 + size.width * 0.2,
      _rand.nextDouble() * size.height * 0.5 + size.height * 0.15,
    );
    final count = _particlesPerBurst;
    for (int i = 0; i < count; i++) {
      if (_particles.length >= _maxParticles) {
        _particles.removeAt(0);
      }
      final angle = (2 * math.pi * i) / count + _rand.nextDouble() * 0.2;
      final speed = 150 + _rand.nextDouble() * 150;
      final color = widget.palette.isEmpty
          ? const Color(0xFFFFD700)
          : widget.palette[_rand.nextInt(widget.palette.length)];
      _particles.add(_Particle(
        position: origin,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        color: color,
        size: 4 + _rand.nextDouble() * 4,
        life: 1.0,
        rotation: _rand.nextDouble() * math.pi * 2,
        rotationSpeed: (_rand.nextDouble() - 0.5) * 6,
      ));
    }
  }

  void _step(double dt) {
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.update(dt);
      if (p.life <= 0) _particles.removeAt(i);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FireworksPainter(_particles),
        size: Size.infinite,
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.life,
    required this.rotation,
    required this.rotationSpeed,
  });

  Offset position;
  Offset velocity;
  Color color;
  double size;
  double life;
  double rotation;
  double rotationSpeed;

  void update(double dt) {
    position = position + velocity * dt;
    velocity = Offset(velocity.dx * 0.985, velocity.dy + 220 * dt);
    rotation += rotationSpeed * dt;
    life -= dt / 1.2;
    size *= 0.985;
  }
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.particles);

  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;
    for (final p in particles) {
      if (p.life <= 0) continue;
      final paint = Paint()
        ..color = p.color.withOpacity(p.life.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      canvas.save();
      canvas.translate(p.position.dx, p.position.dy);
      canvas.rotate(p.rotation);
      _drawStar(canvas, Offset.zero, p.size, paint);
      canvas.restore();
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    const points = 5;
    const inner = 0.45;
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : radius * inner;
      final theta = (i * math.pi) / points - math.pi / 2;
      final x = center.dx + math.cos(theta) * r;
      final y = center.dy + math.sin(theta) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) => true;
}

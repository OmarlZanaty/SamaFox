import 'dart:math';
import 'package:flutter/material.dart';

class _Particle {
  double x;
  double y;
  double speed;
  double size;
  double opacity;
  double rotation;
  double rotationSpeed;
  double wobble;
  double wobbleSpeed;
  String emoji;

  _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.rotation,
    required this.rotationSpeed,
    required this.wobble,
    required this.wobbleSpeed,
    required this.emoji,
  });
}

class GiftRainOverlay extends StatefulWidget {
  final bool active;
  const GiftRainOverlay({super.key, required this.active});

  @override
  State<GiftRainOverlay> createState() => _GiftRainOverlayState();
}

class _GiftRainOverlayState extends State<GiftRainOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _rand = Random();
  final List<_Particle> _particles = [];

  static const _emojis = ['💎', '✨', '🌟', '💫', '⭐', '🎁', '💝', '🌸', '🔥', '👑'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    );
    _controller.addListener(_updateParticles);
    if (widget.active) _startRain();
  }

  void _startRain() {
    _particles.clear();
    for (int i = 0; i < 35; i++) {
      _spawnParticle(initialY: _rand.nextDouble() * -800);
    }
    _controller.repeat();
  }

  void _spawnParticle({double? initialY}) {
    _particles.add(_Particle(
      x: _rand.nextDouble(),
      y: initialY ?? -0.05,
      speed: 0.003 + _rand.nextDouble() * 0.005,
      size: 12 + _rand.nextDouble() * 18,
      opacity: 0.6 + _rand.nextDouble() * 0.4,
      rotation: _rand.nextDouble() * pi * 2,
      rotationSpeed: (_rand.nextDouble() - 0.5) * 0.15,
      wobble: _rand.nextDouble() * pi * 2,
      wobbleSpeed: 0.03 + _rand.nextDouble() * 0.04,
      emoji: _emojis[_rand.nextInt(_emojis.length)],
    ));
  }

  void _updateParticles() {
    if (!mounted) return;
    for (final p in _particles) {
      p.y += p.speed;
      p.rotation += p.rotationSpeed;
      p.wobble += p.wobbleSpeed;
      p.x += sin(p.wobble) * 0.002;
    }
    _particles.removeWhere((p) => p.y > 1.1);
    while (_particles.length < 35) {
      _spawnParticle();
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(GiftRainOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _startRain();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _particles.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _particles.isEmpty) return const SizedBox();
    final size = MediaQuery.of(context).size;

    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _RainPainter(_particles, size),
          child: Stack(
            children: _particles.map((p) {
              return Positioned(
                left: p.x * size.width + sin(p.wobble) * 15,
                top: p.y * size.height,
                child: Transform.rotate(
                  angle: p.rotation,
                  child: Opacity(
                    opacity: p.opacity.clamp(0.0, 1.0),
                    child: Text(
                      p.emoji,
                      style: TextStyle(fontSize: p.size),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _RainPainter extends CustomPainter {
  final List<_Particle> particles;
  final Size screenSize;
  _RainPainter(this.particles, this.screenSize);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_RainPainter old) => true;
}
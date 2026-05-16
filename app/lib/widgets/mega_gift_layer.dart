import 'dart:math';
import 'package:flutter/material.dart';
import '../models/gift.dart';
import '../services/gift_animation_service.dart';

class MegaGiftLayer extends StatefulWidget {
  final GiftAnimationData data;
  final VoidCallback onFinish;

  const MegaGiftLayer({
    super.key,
    required this.data,
    required this.onFinish,
  });

  @override
  State<MegaGiftLayer> createState() => _MegaGiftLayerState();
}

class _MegaGiftLayerState extends State<MegaGiftLayer>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _glowController;
  late AnimationController _particleController;
  late Animation<double> _introOpacity;
  late Animation<double> _outroOpacity;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.data.durationMs),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _introOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.12, curve: Curves.easeOut),
      ),
    );

    _outroOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.82, 1.0, curve: Curves.easeIn),
      ),
    );

    _mainController.forward();
    _mainController.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _glowController.stop();
        _particleController.stop();
        widget.onFinish();
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  double get _opacity {
    final p = _mainController.value;
    if (p < 0.12) return _introOpacity.value;
    if (p > 0.82) return _outroOpacity.value;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (_, __) {
        return Opacity(
          opacity: _opacity.clamp(0.0, 1.0),
          child: _buildAnimation(context),
        );
      },
    );
  }

  Widget _buildAnimation(BuildContext context) {
    switch (widget.data.animationType) {
      case GiftAnimationType.dragon:
        return _dragonAnimation(context);
      case GiftAnimationType.rocket:
        return _rocketAnimation(context);
      case GiftAnimationType.castle:
        return _castleAnimation(context);
      default:
        return const SizedBox();
    }
  }

  Widget _dragonAnimation(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final progress = _mainController.value;
    final glow = _glowController.value;

    // Dragon flies from left, curves through screen
    final curveY = sin(progress * pi) * -80;
    final x = -320.0 + (size.width + 640) * progress;
    final scaleX = progress < 0.5 ? 1.0 : -1.0; // flip when going back

    return Stack(
      children: [
        // Background flash on entry
        if (progress < 0.15)
          Positioned.fill(
            child: Container(
              color: Colors.deepOrange.withOpacity((0.15 - progress) * 3),
            ),
          ),

        // Fire trail particles
        ...List.generate(8, (i) {
          final trailX = x - (i * 30 * (progress < 0.5 ? 1 : -1));
          final trailOpacity = (1 - i / 8) * 0.6;
          return Positioned(
            left: trailX - 20,
            top: size.height * 0.28 + curveY + i * 3.0,
            child: Opacity(
              opacity: trailOpacity.clamp(0.0, 1.0),
              child: Text(
                i % 2 == 0 ? '🔥' : '💨',
                style: TextStyle(fontSize: 20 - i * 1.5),
              ),
            ),
          );
        }),

        // Ground shadow
        Positioned(
          bottom: size.height * 0.1,
          left: x - 80,
          child: Container(
            width: 160,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(80),
              color: Colors.black.withOpacity(0.25 * (1 - (curveY.abs() / 200))),
            ),
          ),
        ),

        // Dragon glow aura
        Positioned(
          left: x - 80,
          top: size.height * 0.28 + curveY - 40,
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (_, __) => Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.deepOrange.withOpacity(0.25 + glow * 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Dragon image
        Positioned(
          left: x - 160,
          top: size.height * 0.22 + curveY,
          child: Transform.scale(
            scaleX: scaleX,
            child: Image.asset(
              'assets/mega/dragon.png',
              width: 320,
              errorBuilder: (_, __, ___) => const Text('🐉',
                  style: TextStyle(fontSize: 120)),
            ),
          ),
        ),

        // Spark burst at peak
        if (progress > 0.45 && progress < 0.55)
          Positioned(
            left: size.width / 2 - 60,
            top: size.height * 0.2 + curveY,
            child: Text(
              '✨💥✨',
              style: TextStyle(
                fontSize: 40,
                shadows: [
                  Shadow(
                    color: Colors.orange.withOpacity(0.8),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _rocketAnimation(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final progress = _mainController.value;
    final glow = _glowController.value;

    // Phase 1: launch (0-0.4), Phase 2: hold (0.4-0.6), Phase 3: return (0.6-1.0)
    double rocketY;
    double rocketScale;
    double angle = 0;

    if (progress < 0.4) {
      // Launch upward
      final t = progress / 0.4;
      rocketY = size.height + 100 - (size.height + 250) * Curves.easeIn.transform(t);
      rocketScale = 0.8 + t * 0.4;
    } else if (progress < 0.6) {
      // Peak - shake/hover
      final shake = sin(progress * 60) * 6;
      rocketY = -120 + shake;
      rocketScale = 1.2;
    } else {
      // Fall back
      final t = (progress - 0.6) / 0.4;
      rocketY = -120 + (size.height + 250) * Curves.easeIn.transform(t);
      rocketScale = 1.2 - t * 0.4;
      angle = t * pi; // flip
    }

    final rocketX = size.width / 2 - 60;

    return Stack(
      children: [
        // Sky flash on launch
        if (progress < 0.08)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity((0.08 - progress) * 8),
            ),
          ),

        // Stars burst at peak
        if (progress > 0.38 && progress < 0.62)
          ...List.generate(12, (i) {
            final angle2 = (i / 12) * pi * 2;
            final dist = 80 + sin(_particleController.value * pi * 2 + i) * 20;
            return Positioned(
              left: rocketX + 60 + cos(angle2) * dist,
              top: rocketY + 60 + sin(angle2) * dist,
              child: Text(
                i % 3 == 0 ? '⭐' : (i % 3 == 1 ? '✨' : '💫'),
                style: TextStyle(fontSize: 12 + (i % 3) * 4.0),
              ),
            );
          }),

        // Exhaust trail
        ...List.generate(10, (i) {
          if (progress > 0.6 && progress < 0.65) return const SizedBox();
          final trailY = rocketY + 110 + i * 18.0;
          final fade = (1 - i / 10) * 0.7;
          return Positioned(
            left: rocketX + 35,
            top: trailY,
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (_, __) => Container(
                  width: 30 - i * 2.5,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: RadialGradient(
                      colors: [
                        Colors.orange.withOpacity(0.8 + glow * 0.2),
                        Colors.red.withOpacity(0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),

        // Glow corona
        Positioned(
          left: rocketX - 20,
          top: rocketY - 20,
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (_, __) => Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.orange.withOpacity(0.2 + glow * 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Rocket
        Positioned(
          left: rocketX,
          top: rocketY,
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: rocketScale,
              child: Image.asset(
                'assets/mega/rocket.png',
                width: 120,
                errorBuilder: (_, __, ___) =>
                const Text('🚀', style: TextStyle(fontSize: 80)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _castleAnimation(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final progress = _mainController.value;
    final glow = _glowController.value;
    final particle = _particleController.value;

    // Castle rises from bottom
    final castleY = progress < 0.3
        ? size.height - (size.height * 0.55) * Curves.elasticOut.transform(progress / 0.3)
        : size.height * 0.18;

    // Gold coins scatter
    final coins = List.generate(16, (i) {
      final angle2 = (i / 16) * pi * 2;
      final dist = 60 + sin(particle * pi * 2 + i * 0.7) * 40 + progress * 80;
      final coinX = size.width / 2 + cos(angle2) * dist;
      final coinY = castleY + 120 + sin(angle2) * dist * 0.5;
      final coinOpacity = progress > 0.15 ? min(1.0, (progress - 0.15) * 4) : 0.0;

      return Positioned(
        left: coinX - 10,
        top: coinY - 10,
        child: Opacity(
          opacity: (coinOpacity * (1 - max(0, (progress - 0.85) * 6.67))).clamp(0.0, 1.0),
          child: Text(
            i % 4 == 0 ? '💰' : (i % 4 == 1 ? '⭐' : (i % 4 == 2 ? '👑' : '💎')),
            style: TextStyle(fontSize: 14 + (i % 3) * 4.0),
          ),
        ),
      );
    });

    return Stack(
      children: [
        // Golden aura background
        if (progress > 0.1)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (_, __) => Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [
                      Colors.amber.withOpacity((0.08 + glow * 0.06) * min(1, progress * 4)),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Explosion GIF overlay
        if (progress > 0.05 && progress < 0.5)
          Positioned(
            left: size.width / 2 - 150,
            top: castleY - 50,
            child: Opacity(
              opacity: (min(1.0, (progress - 0.05) * 5) * min(1.0, (0.5 - progress) * 5)).clamp(0.0, 1.0),
              child: Image.asset(
                'assets/mega/explosion.gif',
                width: 300,
                height: 300,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
          ),

        // Coins
        ...coins,

        // Ground shadow
        Positioned(
          bottom: size.height * 0.05,
          left: size.width / 2 - 100,
          child: Container(
            width: 200,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              gradient: RadialGradient(
                colors: [
                  Colors.black.withOpacity(0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Castle glow
        Positioned(
          left: size.width / 2 - 160,
          top: castleY - 40,
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (_, __) => Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.amber.withOpacity(0.2 + glow * 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Castle image
        Positioned(
          left: size.width / 2 - 130,
          top: castleY,
          child: Image.asset(
            'assets/mega/castle.png',
            width: 260,
            errorBuilder: (_, __, ___) =>
            const Text('🏰', style: TextStyle(fontSize: 120)),
          ),
        ),

        // Crown + sparkle on top
        if (progress > 0.25)
          Positioned(
            left: size.width / 2 - 20,
            top: castleY - 30,
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (_, __) => Text(
                '👑',
                style: TextStyle(
                  fontSize: 36,
                  shadows: [
                    Shadow(
                      color: Colors.amber.withOpacity(0.6 + glow * 0.4),
                      blurRadius: 20 + glow * 15,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
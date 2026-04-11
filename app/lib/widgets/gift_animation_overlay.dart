import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_config.dart';
import '../services/gift_animation_service.dart';
import 'package:confetti/confetti.dart';
import '../animations/gift_animation_registry.dart';
import 'dart:math';

class GiftAnimationOverlay extends StatefulWidget {
  final GiftAnimationData giftData;
  final VoidCallback onComplete;

  /// If true, overlay blocks touches behind it.
  /// If false, touches pass through (animation is just visual).
  final bool blockTouches;

  /// If true, tap anywhere will skip animation.
  final bool tapToSkip;

  const GiftAnimationOverlay({
    Key? key,
    required this.giftData,
    required this.onComplete,
    this.blockTouches = false,
    this.tapToSkip = true,
  }) : super(key: key);

  @override
  State<GiftAnimationOverlay> createState() => _GiftAnimationOverlayState();
}

class _GiftAnimationOverlayState extends State<GiftAnimationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _comboTimerController;
  late final Animation<double> _bgOpacity;
  late final Animation<double> _blur;
  late final Animation<double> _scale;
  late final Animation<double> _glow;
  late final Animation<Offset> _slide;
  late final Animation<double> _contentOpacity;
  late ConfettiController _confettiController;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();


    _controller = AnimationController(
      duration: Duration(milliseconds: widget.giftData.durationMs),
      vsync: this,
    );

    _comboTimerController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    if (widget.giftData.quantity >= 10 || widget.giftData.comboCount >= 5) {
      _confettiController.play();
    }
    // background fade in/out
    _bgOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.35), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.35, end: 0.35), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.35, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _blur = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 10.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 10.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // gift entrance (pop)
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.6, end: 0.8)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.8, end: 2.2)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
    ]).animate(_controller);

    // slide up then slightly up more
    _slide = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0, 0.35), end: const Offset(0, 0.0))
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0, 0.0), end: const Offset(0, -0.06))
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 45,
      ),
    ]).animate(_controller);

    // content fade in then out
    _contentOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 27),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // glow pulse
    _glow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.55).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.55, end: 0.35).chain(CurveTween(curve: Curves.easeInOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.35, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
    ]).animate(_controller);

    _controller.forward();

    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed) {


        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _comboTimerController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _showExplosion(Offset pos) {
    final overlay = Overlay.of(context);

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: pos.dx - 50,
        top: pos.dy - 50,
        child: IgnorePointer(
          child: Image.asset(
            "assets/mega/explosion.gif",
            width: 120,
            height: 120,
          ),
        ),
      ),
    );

    overlay.insert(entry);

    Future.delayed(const Duration(milliseconds: 700), () {
      entry.remove();
    });
  }

  Offset _arcPosition(double t, Offset start, Offset end) {

    final midX = (start.dx + end.dx) / 2;

    // height of arc
    final peakY = (start.dy < end.dy ? start.dy : end.dy) - 200;

    final p0 = start;
    final p1 = Offset(midX, peakY);
    final p2 = end;

    final x = (1 - t) * (1 - t) * p0.dx +
        2 * (1 - t) * t * p1.dx +
        t * t * p2.dx;

    final y = (1 - t) * (1 - t) * p0.dy +
        2 * (1 - t) * t * p1.dy +
        t * t * p2.dy;

    return Offset(x, y);
  }

  bool _isEmojiLike(String value) {
    if (value.isEmpty) return false;

    final lower = value.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        value.contains('/') ||
        value.contains('.png') ||
        value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.webp') ||
        value.contains('.gif')) {
      return false;
    }
    return value.runes.length <= 6;
  }

  void _restartComboTimer() {
    if (!_comboTimerController.isAnimating) return;

    _comboTimerController.reset();
    _comboTimerController.forward();
  }

  @override
  void didUpdateWidget(GiftAnimationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.giftData.comboCount > oldWidget.giftData.comboCount) {
      _restartComboTimer();
    }
  }

  Widget _buildGiftVisual() {
    final raw = widget.giftData.giftImageUrl.trim();

    if (raw.isEmpty) {
      return const Center(
        child: Icon(Icons.card_giftcard, size: 78, color: Colors.white),
      );
    }

    if (_isEmojiLike(raw)) {
      return Center(child: Text(raw, style: const TextStyle(fontSize: 28)));
    }

    if (raw.startsWith('assets/')) {
      return Image.asset(raw, fit: BoxFit.cover);
    }

    final url = raw.startsWith('/') ? '${AppConfig.apiBaseUrl}$raw' : raw;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
    );
  }

  void _skip() {
    if (_disposed) return;
    if (!_controller.isAnimating) return;
    _controller.stop();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final overlay = AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Stack(
          children: [


            if (widget.giftData.giftName == "Car")
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.8,
                    child: Image.asset(
                      "assets/effects/fireworks.gif",
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

            // background dim
            Positioned.fill(
              child: Opacity(
                opacity: _bgOpacity.value,
                child: Container(color: Colors.black),
              ),
            ),

            // blur layer
            if (_blur.value > 0.5)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _blur.value,
                    sigmaY: _blur.value,
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),

            if (widget.giftData.quantity > 1)
              Positioned(
                top: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    "🔥 COMBO ${widget.giftData.quantity}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // decorative sparkles (NO Positioned INSIDE Column issue because we're already in Stack)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (_contentOpacity.value * 0.9).clamp(0.0, 1.0),
                  child: Stack(
                    children: [
                      Positioned(left: 28, top: 70, child: Transform.rotate(angle: _controller.value * 6.28, child: const Text('✨', style: TextStyle(fontSize: 28)))),
                      Positioned(right: 30, top: 90, child: Transform.rotate(angle: -_controller.value * 6.28, child: const Text('✨', style: TextStyle(fontSize: 26)))),
                      Positioned(left: 36, bottom: 130, child: Transform.rotate(angle: _controller.value * 6.28, child: const Text('⭐', style: TextStyle(fontSize: 22)))),
                      Positioned(right: 36, bottom: 150, child: Transform.rotate(angle: -_controller.value * 6.28, child: const Text('⭐', style: TextStyle(fontSize: 24)))),
                    ],
                  ),
                ),
              ),
            ),

            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                emissionFrequency: 0.05,
                numberOfParticles: 20,
                gravity: 0.2,
              ),
            ),

            // main content centered
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {

                final pos = _arcPosition(
                  _controller.value,
                  widget.giftData.startOffset,
                  widget.giftData.endOffset,
                );

                final t = _controller.value;

                // smooth grow in middle
                final flightScale = 1 + (sin(t * pi) * 7.2);

                return Stack(
                  children: [

                    // ✨ spark trail behind gift
                    Positioned(
                      left: pos.dx - 12,
                      top: pos.dy - 12,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.7,
                          child: Transform.rotate(
                            angle: _controller.value * 6.28,
                            child: const Text(
                              "✨",
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ✨ second sparkle for richer trail
                    Positioned(
                      left: pos.dx - 4,
                      top: pos.dy - 18,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.5,
                          child: Transform.rotate(
                            angle: -_controller.value * 6.28,
                            child: const Text(
                              "✨",
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 🎁 main flying gift
                    Positioned(
                      left: pos.dx - 35,
                      top: pos.dy - 35,
                      child: Transform.scale(
                        scale: widget.giftData.startOffset == widget.giftData.endOffset
                            ? _scale.value * 1.6
                            : flightScale,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.6),
                                blurRadius: 25,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: _buildGiftVisual(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          ],
        );
      },
    );

    // Tap-to-skip + optionally block touches
    final wrapped = widget.tapToSkip
        ? GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: overlay,
    )
        : overlay;

    return widget.blockTouches ? wrapped : IgnorePointer(ignoring: true, child: wrapped);
  }
}

import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:confetti/confetti.dart';
import '../config/app_config.dart';
import '../services/gift_animation_service.dart';

class GiftAnimationOverlay extends StatefulWidget {
  final GiftAnimationData giftData;
  final VoidCallback onComplete;
  final bool blockTouches;
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
  late final AnimationController _glowPulse;
  late final AnimationController _trailController;
  late final ConfettiController _confettiController;

  // Animations
  late final Animation<double> _bgOpacity;
  late final Animation<double> _blur;
  late final Animation<double> _contentOpacity;
  late final Animation<double> _bannerSlide;
  late final Animation<double> _giftScale;

  bool _disposed = false;

  // Trail positions
  final List<Offset> _trail = [];
  static const int _trailLength = 12;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.giftData.durationMs),
    );

    _glowPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _trailController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    );

    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));

    if (widget.giftData.quantity >= 5 || widget.giftData.comboCount >= 3) {
      _confettiController.play();
    }

    _bgOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.45), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.45, end: 0.45), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 0.45, end: 0.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _blur = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 8.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 8.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _contentOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _bannerSlide = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 60.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 60),
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: -30.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
    ]).animate(_controller);

    _giftScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.15)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_controller);

    _controller.addListener(_updateTrail);
    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_disposed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  void _updateTrail() {
    if (!mounted) return;
    final pos = _getArcPosition(_controller.value);
    _trail.add(pos);
    if (_trail.length > _trailLength) {
      _trail.removeAt(0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _glowPulse.dispose();
    _trailController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Offset _getArcPosition(double t) {
    if (!mounted) return Offset.zero;
    final start = widget.giftData.startOffset;
    final end = widget.giftData.endOffset;

    final midX = (start.dx + end.dx) / 2;
    final peakOffset = (start - end).distance * 0.45;
    final peakY = min(start.dy, end.dy) - peakOffset.clamp(80.0, 260.0);

    final p1 = Offset(midX, peakY);

    final x = (1 - t) * (1 - t) * start.dx +
        2 * (1 - t) * t * p1.dx +
        t * t * end.dx;
    final y = (1 - t) * (1 - t) * start.dy +
        2 * (1 - t) * t * p1.dy +
        t * t * end.dy;

    return Offset(x, y);
  }

  bool _isEmojiLike(String value) {
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    if (lower.startsWith('http') ||
        value.contains('/') ||
        value.contains('.png') ||
        value.contains('.jpg') ||
        value.contains('.gif')) return false;
    return value.runes.length <= 6;
  }

  Widget _buildGiftVisual({double size = 70}) {
    final raw = widget.giftData.giftImageUrl.trim();

    if (raw.isEmpty) {
      return Icon(Icons.card_giftcard, size: size * 0.8, color: Colors.white);
    }
    if (_isEmojiLike(raw)) {
      return Text(raw, style: TextStyle(fontSize: size * 0.55));
    }
    if (raw.startsWith('assets/')) {
      return raw.endsWith('.svg')
          ? SvgPicture.asset(raw, fit: BoxFit.contain)
          : Image.asset(raw, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.card_giftcard, size: size * 0.8));
    }

    final url = raw.startsWith('http') ? raw : '${AppConfig.apiBaseUrl}$raw';

    if (url.endsWith('.svg')) {
      return SvgPicture.network(url, fit: BoxFit.contain);
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) =>
          Icon(Icons.card_giftcard, size: size * 0.8, color: Colors.white),
    );
  }

  void _skip() {
    if (_disposed || !_controller.isAnimating) return;
    _controller.stop();
    widget.onComplete();
  }

  Color get _giftColor {
    final name = widget.giftData.giftName.toLowerCase();
    if (name.contains('dragon') || name.contains('fire')) return Colors.deepOrange;
    if (name.contains('diamond') || name.contains('ماس')) return Colors.cyanAccent;
    if (name.contains('crown') || name.contains('تاج')) return Colors.amber;
    if (name.contains('rocket') || name.contains('صاروخ')) return Colors.blueAccent;
    return Colors.purpleAccent;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    final overlay = AnimatedBuilder(
      animation: Listenable.merge([_controller, _glowPulse]),
      builder: (_, __) {
        final pos = _getArcPosition(_controller.value);
        final t = _controller.value;
        final glow = _glowPulse.value;

        // Rotation follows arc tangent
        final posPrev = _getArcPosition((t - 0.01).clamp(0.0, 1.0));
        final delta = pos - posPrev;
        final angle = delta.distance > 0.5 ? atan2(delta.dy, delta.dx) - pi / 2 : 0.0;

        // Scale: bigger in mid-arc
        final flightScale = 0.9 + sin(t * pi) * 0.55;

        return Stack(
          children: [
            // ── Dim background ──
            Positioned.fill(
              child: Opacity(
                opacity: _bgOpacity.value,
                child: Container(color: Colors.black),
              ),
            ),

            // ── Blur layer ──
            if (_blur.value > 0.5)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: _blur.value, sigmaY: _blur.value),
                  child: const SizedBox.shrink(),
                ),
              ),

            // ── Sparkle decorations ──
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: _contentOpacity.value,
                  child: Stack(
                    children: [
                      Positioned(
                          left: 24,
                          top: 80,
                          child: _SpinningEmoji(
                              emoji: '✨',
                              size: 28,
                              speed: _controller.value)),
                      Positioned(
                          right: 28,
                          top: 100,
                          child: _SpinningEmoji(
                              emoji: '⭐',
                              size: 24,
                              speed: _controller.value,
                              reverse: true)),
                      Positioned(
                          left: 40,
                          bottom: 160,
                          child: _SpinningEmoji(
                              emoji: '💫',
                              size: 20,
                              speed: _controller.value)),
                      Positioned(
                          right: 40,
                          bottom: 140,
                          child: _SpinningEmoji(
                              emoji: '🌟',
                              size: 22,
                              speed: _controller.value,
                              reverse: true)),
                    ],
                  ),
                ),
              ),
            ),

            // ── Confetti ──
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                numberOfParticles: 25,
                gravity: 0.25,
                colors: [
                  _giftColor,
                  Colors.amber,
                  Colors.white,
                  Colors.pink,
                  Colors.cyanAccent,
                ],
              ),
            ),

            // ── Trail ──
            ..._trail.asMap().entries.map((entry) {
              final idx = entry.key;
              final trailPos = entry.value;
              final trailOpacity = (idx / _trailLength) * 0.55;
              final trailSize = 8.0 + (idx / _trailLength) * 20;

              return Positioned(
                left: trailPos.dx - trailSize / 2,
                top: trailPos.dy - trailSize / 2,
                child: Opacity(
                  opacity: trailOpacity.clamp(0.0, 1.0),
                  child: Container(
                    width: trailSize,
                    height: trailSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _giftColor.withOpacity(0.8),
                          _giftColor.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            // ── Emoji sparks on trail ──
            if (_trail.length > 4)
              ...List.generate(3, (i) {
                final trailIdx = (_trail.length - 1 - i * 3).clamp(0, _trail.length - 1);
                final tp = _trail[trailIdx];
                return Positioned(
                  left: tp.dx - 8,
                  top: tp.dy - 8,
                  child: Opacity(
                    opacity: (0.4 - i * 0.12).clamp(0.0, 1.0),
                    child: Text(
                      i == 0 ? '✨' : '💫',
                      style: TextStyle(fontSize: 14 - i * 2.0),
                    ),
                  ),
                );
              }),

            // ── Glow corona at gift position ──
            Positioned(
              left: pos.dx - 50,
              top: pos.dy - 50,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _giftColor.withOpacity(0.35 + glow * 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Main flying gift ──
            Positioned(
              left: pos.dx - 40,
              top: pos.dy - 40,
              child: Transform.rotate(
                angle: angle,
                child: Transform.scale(
                  scale: flightScale,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                      boxShadow: [
                        BoxShadow(
                          color: _giftColor.withOpacity(0.55 + glow * 0.2),
                          blurRadius: 22 + glow * 8,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _buildGiftVisual(size: 64),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Combo badge ──
            if (widget.giftData.quantity > 1 || widget.giftData.comboCount > 1)
              Positioned(
                top: 50,
                right: 20,
                child: Transform.translate(
                  offset: Offset(0, _bannerSlide.value),
                  child: Opacity(
                    opacity: _contentOpacity.value,
                    child: _ComboBadge(
                      count: max(widget.giftData.quantity,
                          widget.giftData.comboCount),
                      color: _giftColor,
                    ),
                  ),
                ),
              ),

            // ── Sender → Receiver banner ──
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Transform.translate(
                offset: Offset(0, _bannerSlide.value),
                child: Opacity(
                  opacity: _contentOpacity.value,
                  child: _GiftBanner(
                    senderName: widget.giftData.senderName,
                    receiverName: widget.giftData.receiverName,
                    giftName: widget.giftData.giftName,
                    color: _giftColor,
                  ),
                ),
              ),
            ),

            // ── Landing burst at end ──
            if (t > 0.88)
              Positioned(
                left: widget.giftData.endOffset.dx - 40,
                top: widget.giftData.endOffset.dy - 40,
                child: Opacity(
                  opacity: ((t - 0.88) * 8).clamp(0.0, 1.0) *
                      (1 - ((t - 0.95) * 14).clamp(0.0, 1.0)),
                  child: const Text('💥', style: TextStyle(fontSize: 60)),
                ),
              ),
          ],
        );
      },
    );

    final wrapped = widget.tapToSkip
        ? GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: overlay,
    )
        : overlay;

    return widget.blockTouches
        ? wrapped
        : IgnorePointer(ignoring: true, child: wrapped);
  }
}

// ── Supporting widgets ────────────────────────────────────────────

class _SpinningEmoji extends StatelessWidget {
  final String emoji;
  final double size;
  final double speed;
  final bool reverse;

  const _SpinningEmoji({
    required this.emoji,
    required this.size,
    required this.speed,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    final angle = speed * pi * 2 * (reverse ? -1 : 1);
    return Transform.rotate(
      angle: angle,
      child: Text(emoji, style: TextStyle(fontSize: size)),
    );
  }
}

class _ComboBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _ComboBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.9), color.withOpacity(0.6)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(
            'x$count COMBO',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftBanner extends StatelessWidget {
  final String senderName;
  final String receiverName;
  final String giftName;
  final Color color;

  const _GiftBanner({
    required this.senderName,
    required this.receiverName,
    required this.giftName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '🎁',
                    style: TextStyle(
                      fontSize: 18,
                      shadows: [
                        Shadow(color: color, blurRadius: 12),
                      ],
                    ),
                  ),
                ),
                Text(
                  receiverName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (giftName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      giftName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
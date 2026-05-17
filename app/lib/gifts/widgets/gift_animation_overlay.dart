import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/gift.dart';
import '../services/gift_socket_service.dart';
import 'broadcast_banner_layer.dart';
import 'fireworks_overlay.dart';

/// Full-screen gift animation stack. Mount above the voice room UI.
///
/// On every [gift_sent] socket event we spawn one flying gift per quantity,
/// staggered by ~180ms. Each flight goes:
///   sender seat (small) → centre of screen (BIG, covers ~70% of view) → recipient seat (small)
///
/// VIP (LEGENDARY tier) gifts ALSO trigger:
///   - fullscreen fireworks
///   - a one-shot fanfare sound from assets/sounds/vip_gift.mp3
///   - a VIP banner that paints over everything else in the room
class GiftAnimationOverlay extends StatefulWidget {
  const GiftAnimationOverlay({
    super.key,
    required this.socket,
    required this.resolvePosition,
  });

  final GiftSocketService socket;
  final Offset Function(int userId) resolvePosition;

  @override
  State<GiftAnimationOverlay> createState() => _GiftAnimationOverlayState();
}

class _GiftAnimationOverlayState extends State<GiftAnimationOverlay>
    with TickerProviderStateMixin {
  StreamSubscription<GiftSendEvent>? _sentSub;
  final List<_Flight> _flights = [];
  final List<_VipBurst> _vipBursts = [];
  int _flightSeq = 0;

  /// One reusable audio player for VIP fanfare. Keeps a single decoder alive.
  final AudioPlayer _vipPlayer = AudioPlayer();

  static const int _maxConcurrent = 24;
  static const int _staggerMs = 180;

  @override
  void initState() {
    super.initState();
    widget.socket.bind();
    _sentSub = widget.socket.sentStream.listen(_onGift);
    _vipPlayer.setReleaseMode(ReleaseMode.stop);
  }

  void _onGift(GiftSendEvent event) {
    final qty = event.quantity.clamp(1, 30);
    for (int i = 0; i < qty; i++) {
      Future.delayed(Duration(milliseconds: i * _staggerMs), () {
        if (!mounted) return;
        _spawnFlight(event, i, qty);
      });
    }

    // VIP tier (LEGENDARY) → fireworks + sound + banner
    if (event.gift.tier == GiftTier.legendary) {
      _triggerVip(event);
    }
  }

  void _spawnFlight(GiftSendEvent event, int index, int total) {
    while (_flights.length >= _maxConcurrent) {
      final old = _flights.removeAt(0);
      old.controller.dispose();
    }

    final start = widget.resolvePosition(event.senderId);
    final end = widget.resolvePosition(event.recipientId);

    final dur = Duration(
      milliseconds: event.gift.animationMs.clamp(2000, 5500),
    );
    final controller = AnimationController(vsync: this, duration: dur);

    final flight = _Flight(
      id: ++_flightSeq,
      event: event,
      start: start,
      end: end,
      controller: controller,
      index: index,
      total: total,
    );

    setState(() => _flights.add(flight));

    controller.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        if (mounted) setState(() => _flights.remove(flight));
        controller.dispose();
      }
    });
    controller.forward();
  }

  void _triggerVip(GiftSendEvent event) {
    // VIP banner + fireworks for ~5s
    final burst = _VipBurst(
      id: ++_flightSeq,
      event: event,
      createdAt: DateTime.now(),
    );
    setState(() => _vipBursts.add(burst));
    Future.delayed(const Duration(milliseconds: 5000), () {
      if (!mounted) return;
      setState(() => _vipBursts.remove(burst));
    });

    // Sound — best-effort, never throws. Asset must exist at assets/sounds/vip_gift.mp3
    () async {
      try {
        await _vipPlayer.stop();
        await _vipPlayer.play(AssetSource('sounds/vip_gift.mp3'), volume: 0.9);
      } catch (e) {
        // Asset missing or platform error — silent. Logged once to avoid spam.
        debugPrint('[GiftOverlay] vip sound failed: $e');
      }
    }();
  }

  @override
  void dispose() {
    _sentSub?.cancel();
    for (final f in _flights) {
      f.controller.dispose();
    }
    _vipPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Translucent dim while any flight is at centre stage.
          if (_flights.isNotEmpty) _AggregateDimLayer(flights: _flights),

          // In-flight gifts.
          for (final f in _flights) _FlightWidget(flight: f),

          // VIP fireworks (one layer per active burst, capped above).
          for (final v in _vipBursts)
            Positioned.fill(
              key: ValueKey('vip-fireworks-${v.id}'),
              child: const RepaintBoundary(
                child: FireworksOverlay(
                  duration: Duration(milliseconds: 5000),
                  palette: [
                    Color(0xFFFFD700),
                    Color(0xFFFF4081),
                    Color(0xFFFFFFFF),
                    Color(0xFF00E5FF),
                    Color(0xFFE040FB),
                  ],
                ),
              ),
            ),

          // VIP banner — explicitly above everything else in this overlay.
          for (final v in _vipBursts)
            _VipBanner(key: ValueKey('vip-banner-${v.id}'), event: v.event),

          // Cross-room broadcasts (small toast for legendary in other rooms).
          BroadcastBannerLayer(socket: widget.socket),
        ],
      ),
    );
  }
}

class _Flight {
  _Flight({
    required this.id,
    required this.event,
    required this.start,
    required this.end,
    required this.controller,
    required this.index,
    required this.total,
  });
  final int id;
  final GiftSendEvent event;
  final Offset start;
  final Offset end;
  final AnimationController controller;
  final int index;
  final int total;
}

class _VipBurst {
  _VipBurst({required this.id, required this.event, required this.createdAt});
  final int id;
  final GiftSendEvent event;
  final DateTime createdAt;
}

class _AggregateDimLayer extends StatelessWidget {
  const _AggregateDimLayer({required this.flights});
  final List<_Flight> flights;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(flights.map((f) => f.controller).toList()),
      builder: (_, __) {
        double maxIntensity = 0;
        for (final f in flights) {
          final t = f.controller.value;
          double intensity;
          if (t < 0.35) {
            intensity = (t / 0.35) * 0.45;
          } else if (t < 0.7) {
            intensity = 0.45;
          } else {
            intensity = (1 - (t - 0.7) / 0.3) * 0.45;
          }
          if (intensity > maxIntensity) maxIntensity = intensity;
        }
        if (maxIntensity <= 0.01) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(color: Colors.black.withOpacity(maxIntensity)),
          ),
        );
      },
    );
  }
}

class _FlightWidget extends StatelessWidget {
  const _FlightWidget({required this.flight});
  final _Flight flight;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final centre = Offset(screen.width / 2, screen.height / 2);

    final spreadAngle =
        flight.total > 1 ? (flight.index - (flight.total - 1) / 2) * 0.18 : 0.0;
    final spreadOffset = Offset(
      math.cos(spreadAngle) * 28,
      math.sin(spreadAngle) * 28,
    );

    final bigSize = math.min(screen.width, screen.height) * 0.7;
    const smallSize = 96.0;

    return AnimatedBuilder(
      animation: flight.controller,
      builder: (context, _) {
        final t = flight.controller.value;
        Offset pos;
        double size;
        double opacity;
        double rotation;

        if (t < 0.35) {
          final u = Curves.easeOutCubic.transform(t / 0.35);
          pos = Offset.lerp(flight.start, centre + spreadOffset, u)!;
          size = smallSize + (bigSize - smallSize) * u;
          opacity = (u * 1.5).clamp(0.0, 1.0);
          rotation = (1 - u) * 0.6; // unwinding spin on entry
        } else if (t < 0.7) {
          pos = centre + spreadOffset;
          size = bigSize;
          opacity = 1.0;
          // Subtle bob at centre
          final centreT = (t - 0.35) / 0.35;
          rotation = math.sin(centreT * math.pi * 2) * 0.04;
        } else {
          final u = Curves.easeInCubic.transform((t - 0.7) / 0.3);
          pos = Offset.lerp(centre + spreadOffset, flight.end, u)!;
          size = bigSize - (bigSize - smallSize) * u;
          opacity = 1.0 - u * 0.4;
          rotation = u * 0.6;
        }

        return Positioned(
          left: pos.dx - size / 2,
          top: pos.dy - size / 2,
          width: size,
          height: size,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: rotation,
              child: _GiftVisual(gift: flight.event.gift, progress: t),
            ),
          ),
        );
      },
    );
  }
}

/// Visual for an in-flight gift. The emoji + colour pair is hashed from
/// the gift's id so each gift has a stable, distinct look. Also rotates
/// through 4 decoration styles so adjacent gifts feel different.
class _GiftVisual extends StatelessWidget {
  const _GiftVisual({required this.gift, required this.progress});
  final Gift gift;
  final double progress;

  static const List<String> _emojiPool = [
    '💖','🌹','⭐','🎁','💎','👑','🏆','🚀','🛥️','🏰',
    '🌌','🦄','🐉','🎂','🍰','☕','🍫','🎈','🍾','💍',
    '🧸','🎀','🌟','🎆','✈️','🚗','🔥','✨','🌈','🎉',
  ];

  // Gradient pairs ordered roughly: pinks, oranges, blues, purples, greens.
  static const List<List<Color>> _colorPool = [
    [Color(0xFFFF80AB), Color(0xFFF50057)],
    [Color(0xFFFFAB91), Color(0xFFD84315)],
    [Color(0xFFFFD54F), Color(0xFFFF6F00)],
    [Color(0xFFFFF59D), Color(0xFFF57F17)],
    [Color(0xFFA5D6A7), Color(0xFF2E7D32)],
    [Color(0xFF80DEEA), Color(0xFF00838F)],
    [Color(0xFF80D8FF), Color(0xFF0277BD)],
    [Color(0xFF9FA8DA), Color(0xFF283593)],
    [Color(0xFFB39DDB), Color(0xFF4527A0)],
    [Color(0xFFE1BEE7), Color(0xFF6A1B9A)],
    [Color(0xFFF48FB1), Color(0xFFAD1457)],
    [Color(0xFFFFE082), Color(0xFFEF6C00)],
  ];

  /// Stable hash of the gift id (cuid) → int.
  static int _hash(String s) {
    var h = 5381;
    for (var i = 0; i < s.length; i++) {
      h = ((h << 5) + h + s.codeUnitAt(i)) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final h = _hash(gift.id);
    final emoji = _emojiPool[h % _emojiPool.length];
    final colors = _colorPool[(h ~/ 31) % _colorPool.length];
    final style = h % 4; // 0..3 decoration variants

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow halo, breathing with progress
            Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [colors.first.withOpacity(0.55), Colors.transparent],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),

            // Style-specific decoration ring
            _decoration(style, side, colors),

            // Solid inner disc
            Container(
              width: side * 0.62,
              height: side * 0.62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.first.withOpacity(0.5),
                    blurRadius: side * 0.10,
                    spreadRadius: side * 0.02,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: side * 0.32,
                  shadows: const [
                    Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),

            // Gift name strip — only when big
            if (side > 140)
              Positioned(
                bottom: side * 0.10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    gift.nameAr ?? gift.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: side * 0.045,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _decoration(int style, double side, List<Color> colors) {
    switch (style) {
      case 0:
        // Dashed rotating ring
        return Transform.rotate(
          angle: progress * math.pi * 2,
          child: Container(
            width: side * 0.85,
            height: side * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.first.withOpacity(0.6), width: 2),
            ),
          ),
        );
      case 1:
        // Double concentric rings
        return Stack(alignment: Alignment.center, children: [
          Container(
            width: side * 0.88,
            height: side * 0.88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
            ),
          ),
          Container(
            width: side * 0.76,
            height: side * 0.76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.last.withOpacity(0.5), width: 1.5),
            ),
          ),
        ]);
      case 2:
        // Sparkle dots around the disc
        return SizedBox(
          width: side * 0.92,
          height: side * 0.92,
          child: Stack(
            children: List.generate(8, (i) {
              final a = i * math.pi / 4 + progress * math.pi * 2;
              final r = side * 0.42;
              return Positioned(
                left: side * 0.46 + math.cos(a) * r - 4,
                top: side * 0.46 + math.sin(a) * r - 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: colors.first, blurRadius: 6)],
                  ),
                ),
              );
            }),
          ),
        );
      case 3:
      default:
        // Pulsing aura ring
        final pulse = 0.85 + 0.10 * math.sin(progress * math.pi * 4);
        return Container(
          width: side * 0.92 * pulse,
          height: side * 0.92 * pulse,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                colors.first.withOpacity(0.0),
                colors.first.withOpacity(0.6),
                colors.last.withOpacity(0.6),
                colors.first.withOpacity(0.0),
              ],
            ),
          ),
        );
    }
  }
}

/// Full-width banner that shows above seats during a VIP send.
class _VipBanner extends StatefulWidget {
  const _VipBanner({super.key, required this.event});
  final GiftSendEvent event;

  @override
  State<_VipBanner> createState() => _VipBannerState();
}

class _VipBannerState extends State<_VipBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final senderName = widget.event.sender?.name ?? '?';
    final recipientName = widget.event.recipient?.name ?? '?';
    final giftName = widget.event.gift.nameAr ?? widget.event.gift.name;
    final qty = widget.event.quantity;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        double slide;
        double opacity;
        if (t < 0.15) {
          final u = Curves.easeOutBack.transform(t / 0.15);
          slide = -1 + u;
          opacity = u;
        } else if (t < 0.85) {
          slide = 0;
          opacity = 1;
        } else {
          final u = (t - 0.85) / 0.15;
          slide = -u;
          opacity = (1 - u).clamp(0.0, 1.0);
        }

        return Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Transform.translate(
            offset: Offset(0, slide * 80),
            child: Opacity(
              opacity: opacity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF6F00), Color(0xFFE040FB)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(color: Color(0x88FFD700), blurRadius: 24, spreadRadius: 2),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          children: [
                            TextSpan(text: senderName),
                            const TextSpan(text: ' أرسل '),
                            if (qty > 1) TextSpan(text: '×$qty '),
                            TextSpan(
                              text: giftName,
                              style: const TextStyle(color: Color(0xFFFFEB3B)),
                            ),
                            const TextSpan(text: ' إلى '),
                            TextSpan(text: recipientName),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('👑', style: TextStyle(fontSize: 22)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

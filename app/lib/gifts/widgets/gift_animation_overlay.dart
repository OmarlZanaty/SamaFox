import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/gift.dart';
import '../services/gift_socket_service.dart';
import 'broadcast_banner_layer.dart';

/// Full-screen gift animation stack. Mount above the voice room UI.
///
/// On every [gift_sent] socket event we spawn one flying gift per quantity,
/// staggered by ~180ms. Each flight goes:
///   sender seat (small) → centre of screen (BIG, covers ~70% of view) → recipient seat (small)
///
/// The caller passes [resolvePosition] which returns the global-y-in-overlay
/// coordinates of a user's seat (or screen centre if not seated). When sender
/// and recipient are the same person the flight loops around itself.
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
  int _flightSeq = 0;

  // Maximum simultaneous flights to keep performance reasonable.
  static const int _maxConcurrent = 24;
  // Staggered delay between successive flights of the same multi-quantity send.
  static const int _staggerMs = 180;

  @override
  void initState() {
    super.initState();
    widget.socket.bind();
    _sentSub = widget.socket.sentStream.listen(_onGift);
  }

  void _onGift(GiftSendEvent event) {
    final qty = event.quantity.clamp(1, 30);
    for (int i = 0; i < qty; i++) {
      Future.delayed(Duration(milliseconds: i * _staggerMs), () {
        if (!mounted) return;
        _spawnFlight(event, i, qty);
      });
    }
  }

  void _spawnFlight(GiftSendEvent event, int index, int total) {
    // Cap concurrent flights — drop oldest if over budget.
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

  @override
  void dispose() {
    _sentSub?.cancel();
    for (final f in _flights) {
      f.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Translucent dim overlay while any flight is at the centre stage.
          if (_flights.isNotEmpty)
            _AggregateDimLayer(flights: _flights),

          // Each in-flight gift.
          for (final f in _flights) _FlightWidget(flight: f),

          // Cross-room broadcasts (legendary "X sent Y in room Z" banners).
          BroadcastBannerLayer(socket: widget.socket),
        ],
      ),
    );
  }
}

/// Internal state for one in-flight gift.
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

  /// Index within a multi-quantity send (0..total-1). Used for slight curve offsets.
  final int index;
  final int total;
}

/// Renders a translucent dim background whenever any flight is between
/// 35% and 70% of its progress (centre-stage moment).
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

    // Spread multi-quantity slightly so they don't perfectly overlap.
    final spreadAngle =
        flight.total > 1 ? (flight.index - (flight.total - 1) / 2) * 0.18 : 0.0;
    final spreadOffset = Offset(
      math.cos(spreadAngle) * 28,
      math.sin(spreadAngle) * 28,
    );

    // Big size at centre — ~70% of the smaller screen edge.
    final bigSize = math.min(screen.width, screen.height) * 0.7;
    const smallSize = 96.0;

    return AnimatedBuilder(
      animation: flight.controller,
      builder: (context, _) {
        final t = flight.controller.value;
        Offset pos;
        double size;
        double opacity;

        if (t < 0.35) {
          // Phase 1: sender seat → centre (growing)
          final u = Curves.easeOutCubic.transform(t / 0.35);
          pos = Offset.lerp(flight.start, centre + spreadOffset, u)!;
          size = smallSize + (bigSize - smallSize) * u;
          opacity = (u * 1.5).clamp(0.0, 1.0);
        } else if (t < 0.7) {
          // Phase 2: hold at centre (BIG)
          pos = centre + spreadOffset;
          size = bigSize;
          opacity = 1.0;
        } else {
          // Phase 3: centre → recipient seat (shrinking)
          final u = Curves.easeInCubic.transform((t - 0.7) / 0.3);
          pos = Offset.lerp(centre + spreadOffset, flight.end, u)!;
          size = bigSize - (bigSize - smallSize) * u;
          opacity = 1.0 - u * 0.5;
        }

        return Positioned(
          left: pos.dx - size / 2,
          top: pos.dy - size / 2,
          width: size,
          height: size,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: _GiftVisual(gift: flight.event.gift),
          ),
        );
      },
    );
  }
}

/// Compact tier+category visual that doesn't require a WebView — just a
/// radial gradient circle with the matching emoji + glow shadow. Same look
/// as the picker fallback, so the in-flight gift matches the selected card.
class _GiftVisual extends StatelessWidget {
  const _GiftVisual({required this.gift});
  final Gift gift;

  static const Map<String, String> _categoryEmoji = {
    'love': '💖',
    'fun': '🎁',
    'luxury': '💎',
    'festive': '🎆',
  };

  static const Map<GiftTier, List<Color>> _tierGradient = {
    GiftTier.small: [Color(0xFFFF80AB), Color(0xFFF50057)],
    GiftTier.medium: [Color(0xFFFFD54F), Color(0xFFFF6F00)],
    GiftTier.large: [Color(0xFF80D8FF), Color(0xFF0277BD)],
    GiftTier.legendary: [Color(0xFFE040FB), Color(0xFF4A148C)],
  };

  @override
  Widget build(BuildContext context) {
    final emoji = _categoryEmoji[gift.category] ?? '🎁';
    final colors = _tierGradient[gift.tier] ?? const [Color(0xFFFF80AB), Color(0xFFF50057)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow halo
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
            // Gift name strip (only visible at big sizes)
            if (side > 140)
              Positioned(
                bottom: side * 0.18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
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
}

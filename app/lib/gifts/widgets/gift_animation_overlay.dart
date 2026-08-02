import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/gift.dart';
import '../services/gift_socket_service.dart';
import 'broadcast_banner_layer.dart';
import 'fireworks_overlay.dart';
import 'gift_player.dart';

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

  /// Sound for ordinary (non-VIP) gifts. Fired the instant the broadcast
  /// `gift_sent` event arrives — the same event every client in the room gets —
  /// so the sound lands at the same moment for the sender and everyone else.
  /// It is a bundled asset, so there is no download to wait on.
  final AudioPlayer _giftPlayer = AudioPlayer();

  /// A x50 send is one event, but combos can still arrive back to back. Don't
  /// retrigger the chime more than this often or it turns into noise.
  static const Duration _giftSoundThrottle = Duration(milliseconds: 320);
  DateTime? _lastGiftSoundAt;

  static const int _maxConcurrent = 24;
  static const int _staggerMs = 180;

  @override
  void initState() {
    super.initState();
    widget.socket.bind();
    _sentSub = widget.socket.sentStream.listen(_onGift);
    _vipPlayer.setReleaseMode(ReleaseMode.stop);
    _giftPlayer.setReleaseMode(ReleaseMode.stop);
    // Low latency mode keeps the asset decoded so playback starts immediately
    // rather than a few hundred ms after the event.
    _giftPlayer.setPlayerMode(PlayerMode.lowLatency);
  }

  /// Plays the ordinary-gift chime. Best-effort: never throws, never blocks the
  /// animation. VIDEO gifts carry their own audio track and LEGENDARY gifts get
  /// the fanfare instead, so neither doubles up with this.
  void _playGiftSound(GiftSendEvent event) {
    if (event.gift.tier == GiftTier.legendary) return;
    if (event.gift.format == GiftFormat.video) return;
    final now = DateTime.now();
    if (_lastGiftSoundAt != null && now.difference(_lastGiftSoundAt!) < _giftSoundThrottle) {
      return;
    }
    _lastGiftSoundAt = now;
    () async {
      try {
        await _giftPlayer.stop();
        await _giftPlayer.play(AssetSource('sounds/gift_send.wav'), volume: 0.75);
      } catch (e) {
        debugPrint('[GiftOverlay] gift sound failed: $e');
      }
    }();
  }

  void _onGift(GiftSendEvent event) {
    // Fire the sound FIRST, before any animation work, so it is as close to the
    // socket event as possible on every device.
    _playGiftSound(event);

    // Video gifts carry sound and a real clip — repeating that N times for a
    // ×N send would replay the same video N times over each other. They
    // spawn exactly ONE flight, badged with the send count, and play once.
    // Image/SVG gifts have no audio and are cheap to repeat, so those keep
    // spawning one flight per unit as before.
    if (event.gift.format == GiftFormat.video) {
      _spawnFlight(event, 0, 1, displayQuantity: event.quantity.clamp(1, 30));
    } else {
      final qty = event.quantity.clamp(1, 30);
      for (int i = 0; i < qty; i++) {
        Future.delayed(Duration(milliseconds: i * _staggerMs), () {
          if (!mounted) return;
          _spawnFlight(event, i, qty);
        });
      }
    }

    // VIP tier (LEGENDARY) → fireworks + sound + banner
    if (event.gift.tier == GiftTier.legendary) {
      _triggerVip(event);
    }
  }

  void _spawnFlight(GiftSendEvent event, int index, int total, {int? displayQuantity}) {
    while (_flights.length >= _maxConcurrent) {
      final old = _flights.removeAt(0);
      old.controller.dispose();
    }

    final start = widget.resolvePosition(event.senderId);
    final end = widget.resolvePosition(event.recipientId);

    // A video gift's flight must outlast its clip, otherwise the flight is
    // removed mid-playback and the video is cut short. Image/SVG gifts keep the
    // tighter window so a burst of them stays snappy.
    final dur = Duration(
      milliseconds: event.gift.format == GiftFormat.video
          ? event.gift.animationMs.clamp(2000, 15000) + 400
          : event.gift.animationMs.clamp(2000, 5500),
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
      displayQuantity: displayQuantity,
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
        await _vipPlayer.play(AssetSource('sounds/vip_gift.wav'), volume: 0.9);
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
    _giftPlayer.dispose();
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
    this.displayQuantity,
  });
  final int id;
  final GiftSendEvent event;
  final Offset start;
  final Offset end;
  final AnimationController controller;
  final int index;
  final int total;
  /// Set only for the single-flight video case — the ×N badge to show since
  /// this one flight represents the whole send, not one unit of it.
  final int? displayQuantity;
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
              child: _GiftVisual(gift: flight.event.gift, quantity: flight.displayQuantity),
            ),
          ),
        );
      },
    );
  }
}

/// Visual for an in-flight gift — the gift's OWN art: its static icon, or for
/// a VIDEO-format gift its uploaded clip (via the existing [GiftPlayer],
/// previously built but never mounted anywhere live). [quantity] is only set
/// for the single-flight video case, where it renders as a "×N" badge since
/// one flight is standing in for the whole send.
class _GiftVisual extends StatelessWidget {
  const _GiftVisual({required this.gift, this.quantity});
  final Gift gift;
  final int? quantity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final isVideo = gift.format == GiftFormat.video;
        return Stack(
          alignment: Alignment.center,
          children: [
            // A video clip is a rectangle with its own background: cropping it
            // into a circle chopped the artwork and showed a black disc. Show
            // the whole frame for video, keep the round badge for icons.
            SizedBox(
              width: side * (isVideo ? 1.0 : 0.9),
              height: side * (isVideo ? 1.0 : 0.9),
              child: isVideo
                  ? GiftPlayer(gift: gift, onComplete: () {}, onError: () {})
                  : ClipOval(
                      child: GiftPlayer(gift: gift, onComplete: () {}, onError: () {}),
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

            // ×N badge — this one flight represents the whole send.
            if (quantity != null && quantity! > 1)
              Positioned(
                top: side * 0.06,
                right: side * 0.06,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF50057),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                  ),
                  child: Text(
                    '×$quantity',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: side * 0.06,
                      fontWeight: FontWeight.w800,
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

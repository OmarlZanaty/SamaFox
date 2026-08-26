import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift.dart';
import '../services/gift_socket_service.dart';

/// Cross-room broadcast banner — listens to `gift_broadcast` from
/// the socket service and surfaces a top notification ticker.
///
/// The banner is the ornate crystal frame artwork: a narrow plaque across the
/// top holds the label and the wide inner panel holds the sender → gift →
/// recipient line. The frame keeps its aspect ratio so the gold corners and
/// crystals never skew, and the text scales down to fit instead of wrapping
/// outside the panel.
class BroadcastBannerLayer extends ConsumerStatefulWidget {
  const BroadcastBannerLayer({super.key, required this.socket});
  final GiftSocketService socket;

  @override
  ConsumerState<BroadcastBannerLayer> createState() => _BroadcastBannerLayerState();
}

class _BroadcastBannerLayerState extends ConsumerState<BroadcastBannerLayer>
    with SingleTickerProviderStateMixin {
  /// Artwork is 419x117. These fractions mark the two transparent text wells
  /// inside the frame, measured off that source image.
  static const String _frameAsset = 'assets/images/gift_broadcast_banner.png';
  static const double _frameAspect = 419 / 117;
  static const Rect _plaque = Rect.fromLTRB(0.36, 0.10, 0.645, 0.35);
  static const Rect _panel = Rect.fromLTRB(0.11, 0.40, 0.90, 0.88);

  final Queue<GiftSendEvent> _queue = Queue();
  GiftSendEvent? _current;
  StreamSubscription? _sub;
  late final AnimationController _ctrl;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _sub = widget.socket.broadcastStream.listen(_enqueue);
  }

  void _enqueue(GiftSendEvent event) {
    _queue.add(event);
    _pump();
  }

  void _pump() {
    if (_current != null || _queue.isEmpty) return;
    setState(() => _current = _queue.removeFirst());
    _ctrl.forward(from: 0);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 6000), _dismiss);
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    if (!mounted) return;
    setState(() => _current = null);
    _pump();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Places a child inside one of the artwork's text wells, using fractions of
  /// the frame so it tracks the image at any width.
  Widget _well(Rect area, double w, double h, Widget child) {
    return Positioned(
      left: area.left * w,
      top: area.top * h,
      width: (area.right - area.left) * w,
      height: (area.bottom - area.top) * h,
      child: Center(
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ev = _current;
    if (ev == null) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack)),
        child: SafeArea(
          child: GestureDetector(
            onTap: () {
              // Tapping the banner takes the viewer into the gift's room.
              if (ev.roomId != null) {
                Navigator.of(context).pushNamed('/room', arguments: ev.roomId);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: AspectRatio(
                aspectRatio: _frameAspect,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final h = c.maxHeight;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(_frameAsset, fit: BoxFit.fill),
                        ),
                        _well(
                          _plaque,
                          w,
                          h,
                          const Text(
                            'هدية كبيرة',
                            style: TextStyle(
                              color: Color(0xFFFFE7A3),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                            ),
                          ),
                        ),
                        _well(
                          _panel,
                          w,
                          h,
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _bannerText(ev),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _bannerText(GiftSendEvent ev) {
    final sender = ev.sender?.name ?? 'مستخدم';
    final recipient = ev.recipient?.name ?? 'مستخدم';
    final gift = ev.gift.nameAr ?? ev.gift.name;
    final qty = ev.quantity > 1 ? ' ×${ev.quantity}' : '';
    return '$sender أهدى $gift$qty إلى $recipient';
  }
}

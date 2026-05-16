import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift_v2.dart';
import '../services/gift_v2_socket_service.dart';

/// Cross-room broadcast banner — listens to `gift_v2_broadcast` from
/// the socket service and surfaces a top notification ticker.
class BroadcastBannerLayer extends ConsumerStatefulWidget {
  const BroadcastBannerLayer({super.key, required this.socket});
  final GiftV2SocketService socket;

  @override
  ConsumerState<BroadcastBannerLayer> createState() => _BroadcastBannerLayerState();
}

class _BroadcastBannerLayerState extends ConsumerState<BroadcastBannerLayer>
    with SingleTickerProviderStateMixin {
  final Queue<GiftV2SendEvent> _queue = Queue();
  GiftV2SendEvent? _current;
  StreamSubscription? _sub;
  late final AnimationController _ctrl;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _sub = widget.socket.broadcastStream.listen(_enqueue);
  }

  void _enqueue(GiftV2SendEvent event) {
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

  @override
  Widget build(BuildContext context) {
    final ev = _current;
    if (ev == null) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: true,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
              .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack)),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF4081), Color(0xFFFFD54F)],
                ),
                borderRadius: BorderRadius.circular(40),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _bannerText(ev),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _bannerText(GiftV2SendEvent ev) {
    final sender = ev.sender?.name ?? 'Someone';
    final recipient = ev.recipient?.name ?? 'someone';
    final gift = ev.gift.nameAr ?? ev.gift.name;
    return '$sender sent $gift to $recipient${ev.quantity > 1 ? ' ×${ev.quantity}' : ''}';
  }
}

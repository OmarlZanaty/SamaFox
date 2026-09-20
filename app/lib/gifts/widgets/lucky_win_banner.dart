import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../widgets/app_network_image.dart';
import '../models/gift.dart';
import '../services/gift_socket_service.dart';

/// هدايا الحظ — the centred "كسب ×N" bar.
///
/// Client spec: *"كل واحد كسب يجيله شريط في نصف الشاشة بعدد الأضعاف اللي
/// كسبها"*. Every win in THIS room plays here for everyone in it; the sender's
/// own loss shows a small "حظ أوفر" so they know the roll happened at all.
///
/// Same discipline as [GiftAnnouncementBar]: one at a time, queued, never at
/// the top (the gift bar lives there), gone in a couple of seconds.
class LuckyWinBanner extends StatefulWidget {
  const LuckyWinBanner({
    super.key,
    required this.socket,
    required this.roomId,
    required this.myUserId,
  });

  final GiftSocketService socket;
  final int roomId;
  final int? myUserId;

  @override
  State<LuckyWinBanner> createState() => _LuckyWinBannerState();
}

const Duration _kWinVisible = Duration(milliseconds: 2600);
const Duration _kLoseVisible = Duration(milliseconds: 1400);
const Duration _kAnim = Duration(milliseconds: 320);

class _LuckyWinBannerState extends State<LuckyWinBanner>
    with SingleTickerProviderStateMixin {
  StreamSubscription<LuckyRollEvent>? _sub;
  final Queue<LuckyRollEvent> _queue = Queue<LuckyRollEvent>();
  LuckyRollEvent? _current;
  Timer? _hide;
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _kAnim);

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.luckyWinStream.listen(_onEvent);
  }

  void _onEvent(LuckyRollEvent e) {
    if (!mounted) return;
    if (e.roomId != null && e.roomId != widget.roomId) return;
    // A loss is the sender's business only.
    if (!e.won && e.senderId != widget.myUserId) return;
    if (_queue.length >= 6) _queue.removeFirst();
    _queue.add(e);
    if (_current == null) _next();
  }

  void _next() {
    _hide?.cancel();
    if (_queue.isEmpty) {
      if (_current != null) {
        _ctrl.reverse().whenComplete(() {
          if (mounted) setState(() => _current = null);
        });
      }
      return;
    }
    setState(() => _current = _queue.removeFirst());
    _ctrl.forward(from: 0);
    _hide = Timer(_current!.won ? _kWinVisible : _kLoseVisible, () {
      if (!mounted) return;
      _ctrl.reverse().whenComplete(() {
        if (mounted) _next();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = _current;
    if (e == null) return const SizedBox.shrink();
    final isMe = e.senderId == widget.myUserId;
    return IgnorePointer(
      child: Align(
        // Mid-screen, a touch above centre so it sits over the seats and clear
        // of both the gift bar (top) and the chat (bottom).
        alignment: const Alignment(0, -0.18),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.7, end: 1).animate(
              CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
            ),
            child: e.won ? _WinCard(event: e, isMe: isMe) : const _LoseChip(),
          ),
        ),
      ),
    );
  }
}

class _WinCard extends StatelessWidget {
  const _WinCard({required this.event, required this.isMe});
  final LuckyRollEvent event;
  final bool isMe;

  Color get _tint {
    if (event.multiplier >= 200) return const Color(0xFFFF3D71); // legendary
    if (event.multiplier >= 50) return const Color(0xFFFFB300);  // gold
    if (event.multiplier >= 20) return const Color(0xFF7C4DFF);  // violet
    return const Color(0xFF00C853);                               // green
  }

  @override
  Widget build(BuildContext context) {
    final name = isMe ? 'أنت' : (event.senderName ?? 'مستخدم');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_tint.withOpacity(0.95), Colors.black.withOpacity(0.85)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.2),
          boxShadow: [
            BoxShadow(color: _tint.withOpacity(0.55), blurRadius: 18, spreadRadius: 1),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(url: event.senderAvatarUrl, size: 40),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    'كسب ${event.payoutCoins} كوينز 🎉',
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '×${event.multiplier}',
                style: TextStyle(color: _tint, fontWeight: FontWeight.w900, fontSize: 20, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoseChip extends StatelessWidget {
  const _LoseChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: const Text(
        'حظ أوفر المرة الجاية 🎲',
        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url == null || url!.isEmpty)
            ? Container(color: Colors.white24, child: const Icon(Icons.person, color: Colors.white70))
            : AppNetworkImage(url!, width: size, height: size, fit: BoxFit.cover, cacheWidth: 96),
      ),
    );
  }
}

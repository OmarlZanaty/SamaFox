import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../services/gift_socket_service.dart';
import '../../widgets/app_network_image.dart';

/// A22 — شريط إعلان الهدية.
///
/// Client spec (17/08 23:01): *"إشعار الهدية نفسه — فلان أهدى هدية كذا إلى
/// فلان — يظهر في منتصف الشاشة في شريط مستقل بشكل جميل. ولو الهدية لأكثر من
/// شخص يكتب: أهدى هدية كذا إلى الجميع."*
///
/// Three things this deliberately does NOT do:
///  • it does not sit at the top — that space belongs to the gift bar and the
///    agent-percentage banner, and the client's whole complaint was that things
///    kept covering the gift bar;
///  • it does not stack — announcements queue and play one at a time, so a busy
///    room never buries the screen in bars;
///  • it does not linger — [_kVisible] keeps it near the 1–1.5s the client
///    asked for on the gift toasts.
class GiftAnnouncementBar extends StatefulWidget {
  const GiftAnnouncementBar({
    super.key,
    required this.socket,
    this.roomId,
    this.myUserId,
  });

  final GiftSocketService socket;

  /// D6/D9 — who is looking. The two requests are for two different bars that
  /// had been built as one:
  ///
  ///  • D6, «حطه علي يمين الشاشه مش النص» — the SENDER's own confirmation of
  ///    the gift he just sent, on the right, near where he tapped;
  ///  • D9, «يظهر في منتصف الشاشة في شريط مستقل» — the room-wide announcement
  ///    that someone gifted someone, centred.
  ///
  /// One widget cannot be both right-aligned and centred, which is why closing
  /// one of these kept reopening the other. The sender id on the event is what
  /// tells them apart: the bar is a confirmation for the person who sent it and
  /// an announcement for everyone else.
  final int? myUserId;

  /// When set, announcements from other rooms are ignored. The server already
  /// scopes the event per room; this is belt-and-braces for a client that is
  /// still joined to a room it has navigated away from.
  final int? roomId;

  @override
  State<GiftAnnouncementBar> createState() => _GiftAnnouncementBarState();
}

/// How long one bar stays on screen before the next in the queue plays.
const Duration _kVisible = Duration(milliseconds: 1500);
const Duration _kSlide = Duration(milliseconds: 260);

class _GiftAnnouncementBarState extends State<GiftAnnouncementBar>
    with SingleTickerProviderStateMixin {
  final Queue<GiftAnnouncement> _queue = Queue<GiftAnnouncement>();
  GiftAnnouncement? _current;
  StreamSubscription<GiftAnnouncement>? _sub;
  Timer? _hideTimer;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _kSlide);
    _sub = widget.socket.announcementStream.listen(_onAnnouncement);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onAnnouncement(GiftAnnouncement a) {
    if (widget.roomId != null && a.roomId != null && a.roomId != widget.roomId) return;
    // A long queue means a spam burst; only the most recent few are worth
    // showing, and dropping the rest keeps the bar from running minutes behind.
    if (_queue.length >= 5) _queue.removeFirst();
    _queue.add(a);
    if (_current == null) _playNext();
  }

  void _playNext() {
    if (!mounted) return;
    if (_queue.isEmpty) {
      setState(() => _current = null);
      return;
    }
    setState(() => _current = _queue.removeFirst());
    _ctrl.forward(from: 0);
    _hideTimer?.cancel();
    _hideTimer = Timer(_kVisible, () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (!mounted) return;
      _playNext();
    });
  }

  String _resolveUrl(String raw) {
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  @override
  Widget build(BuildContext context) {
    final a = _current;
    if (a == null) return const SizedBox.shrink();

    // D6 vs D9 — see [myUserId]. Physically right, never AlignmentDirectional:
    // the room is laid out RTL, where `start` IS the right edge, so a
    // directional value would read as correct here and render on the wrong
    // side. The vertical is the same for both: centreRight/centre is exactly
    // the 50% line, which is where the gift panel's top edge sits (its height
    // is half the screen), so the panel met the bar every time. -0.35 lifts it
    // clear.
    final isMine = widget.myUserId != null && a.senderId == widget.myUserId;
    final alignment = isMine ? const Alignment(1.0, -0.35) : const Alignment(0.0, -0.35);

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: FadeTransition(
            opacity: _ctrl,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1.0)
                  .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack)),
              child: _bar(a, isMine),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(GiftAnnouncement a, bool isMine) {
    final iconUrl = _resolveUrl(a.giftIconUrl);
    return Container(
      // The sender's bar is pinned to the right edge; the announcement keeps
      // equal margins so it reads as centred rather than as a right-hand bar
      // that happens to be narrow. Both cap their width, so a long name wraps
      // inside the bar instead of stretching it back across the screen.
      margin: isMine
          ? const EdgeInsets.only(left: 48, right: 12)
          : const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xE61A0E3E), Color(0xE64A2A8C), Color(0xE61A0E3E)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x99F5C242), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x33F5C242), blurRadius: 22, spreadRadius: 1),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AppNetworkImage(
                iconUrl,
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Text('🎁', style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              a.quantity > 1 ? '${a.text} ×${a.quantity}' : a.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Color(0xAA000000), blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

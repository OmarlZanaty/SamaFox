import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../gifts/services/gift_socket_service.dart';

/// Brief, queued gift announcements without a banner covering the room.
class RoomGiftAnnouncementText extends StatefulWidget {
  const RoomGiftAnnouncementText({
    super.key,
    required this.socket,
    this.roomId,
  });

  final GiftSocketService socket;

  /// When set, announcements from other rooms are ignored. The server already
  /// scopes the event per room; this is belt-and-braces for a client that is
  /// still joined to a room it has navigated away from.
  final int? roomId;

  @override
  State<RoomGiftAnnouncementText> createState() => _RoomGiftAnnouncementTextState();
}

/// How long one bar stays on screen before the next in the queue plays.
const Duration _kVisible = Duration(milliseconds: 1500);
const Duration _kSlide = Duration(milliseconds: 260);

class _RoomGiftAnnouncementTextState extends State<RoomGiftAnnouncementText>
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

  @override
  Widget build(BuildContext context) {
    final a = _current;
    if (a == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: FadeTransition(
          opacity: _ctrl,
          child: Text(a.text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ),
    );
  }
}

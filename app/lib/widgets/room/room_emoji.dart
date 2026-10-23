import '../../l10n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/socket_service.dart';

/// SPEC52 #20 — animated emoji over the sender's mic.
///
/// The catalogue ships with the app (light WebP stickers in
/// `assets/images/emoji/<id>.webp`, an emoji glyph as fallback), so the server
/// only relays `{emojiId, senderId, seatId, timestamp}` — nothing heavy is
/// downloaded per emoji. The ids must match the server's allow-list.
class RoomEmojiDef {
  const RoomEmojiDef(this.id, this.label, this.glyph, {this.drift = 0});
  final String id;
  final String label;
  final String glyph;

  /// Horizontal drift while it plays: +1 = to the right, -1 = to the left.
  final double drift;

  String get asset => 'assets/images/emoji/$id.webp';
}

List<RoomEmojiDef> get kRoomEmojis => [
  RoomEmojiDef('kiss_right', tr('قبلة يمين', "Kiss right"), '😘', drift: 1),
  RoomEmojiDef('kiss_left', tr('قبلة شمال', "Kiss left"), '😘', drift: -1),
  RoomEmojiDef('magnifier', tr('نظارة مكبرة', "Magnifying glasses"), '🧐'),
  RoomEmojiDef('yawn_sleep', tr('تثاؤب ونوم', "Yawn and sleep"), '🥱'),
  RoomEmojiDef('heartbroken', tr('قلب مكسور', "Broken heart"), '💔'),
  RoomEmojiDef('clap', tr('تصفيق', "Clap"), '👏'),
  RoomEmojiDef('cry', tr('بكاء', "Cry"), '😭'),
  RoomEmojiDef('laugh', tr('ضحك', "Laugh"), '😂'),
  RoomEmojiDef('hello_sign', tr('لافتة مرحبا', "Hello sign"), '👋'),
  RoomEmojiDef('heart', tr('قلب', "Heart"), '❤️'),
  RoomEmojiDef('dance', tr('رقص', "Dance"), '💃'),
  RoomEmojiDef('bride_groom', tr('عروس وعريس', "Bride and groom"), '👰'),
  RoomEmojiDef('hug', tr('حضن', "Hug"), '🤗'),
  RoomEmojiDef('couple_kiss', tr('قبلة', "Kiss"), '💏'),
  RoomEmojiDef('spit_right', tr('بصق يمين', "Spit right"), '💦', drift: 1),
  RoomEmojiDef('spit_left', tr('بصق شمال', "Spit left"), '💦', drift: -1),
  RoomEmojiDef('wow', 'Wow', '😮'),
  RoomEmojiDef('angry', tr('غضب', "Angry"), '😡'),
  RoomEmojiDef('shock', tr('صدمة', "Shocked"), '😱'),
  RoomEmojiDef('fire_heart', tr('قلب مشتعل', "Heart on fire"), '❤️‍🔥'),
  RoomEmojiDef('lol', tr('ضحك قوي', "Big laugh"), '🤣'),
  RoomEmojiDef('sleep', tr('نوم', "Sleep"), '😴'),
  RoomEmojiDef('party', tr('احتفال', "Party"), '🥳'),
  RoomEmojiDef('fire_clap', tr('تصفيق ناري', "Fiery clap"), '🔥'),
  RoomEmojiDef('stars', tr('نجوم', "Stars"), '🤩'),
  RoomEmojiDef('crown', tr('تاج', "Crown"), '👑'),
];

RoomEmojiDef? roomEmojiById(String id) {
  for (final e in kRoomEmojis) {
    if (e.id == id) return e;
  }
  return null;
}

Widget roomEmojiArt(RoomEmojiDef e, double size) => Image.asset(
      e.asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: FittedBox(child: Text(e.glyph, style: const TextStyle(decoration: TextDecoration.none))),
      ),
    );

/// The picker (opened by the 😀 button next to the chat input).
class RoomEmojiPicker {
  static Future<void> show(BuildContext context, {required void Function(RoomEmojiDef) onPick}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF160C33),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('إيموجي متحرك', "Animated emoji"), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 6,
                    childAspectRatio: .82,
                  ),
                  itemCount: kRoomEmojis.length,
                  itemBuilder: (_, i) {
                    final e = kRoomEmojis[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(ctx);
                        onPick(e);
                      },
                      child: Column(
                        children: [
                          Expanded(child: roomEmojiArt(e, 44)),
                          Text(e.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoomEmojiEvent {
  RoomEmojiEvent(this.def, this.seatId, this.senderId);
  final RoomEmojiDef def;
  final int seatId;
  final int senderId;
  final int key = DateTime.now().microsecondsSinceEpoch;
}

/// Paints incoming emoji over the sender's mic for ~3 s.
class RoomEmojiLayer extends StatefulWidget {
  const RoomEmojiLayer({super.key, required this.roomId, required this.resolveSeat});
  final int roomId;

  /// Centre of a seat in this layer's coordinates.
  final Offset Function(int seatNumber) resolveSeat;

  static final StreamController<Map<String, dynamic>> _events = StreamController.broadcast();
  static bool _wired = false;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    SocketService().on('room_emoji', (data) {
      if (data is Map) _events.add(Map<String, dynamic>.from(data));
    });
  }

  @override
  State<RoomEmojiLayer> createState() => _RoomEmojiLayerState();
}

class _RoomEmojiLayerState extends State<RoomEmojiLayer> {
  final List<RoomEmojiEvent> _live = [];
  StreamSubscription<Map<String, dynamic>>? _sub;
  static const _max = 6;

  @override
  void initState() {
    super.initState();
    RoomEmojiLayer._wire();
    _sub = RoomEmojiLayer._events.stream.listen((d) {
      if ((d['roomId'] as num?)?.toInt() != widget.roomId) return;
      final def = roomEmojiById('${d['emojiId']}');
      final seat = (d['seatId'] as num?)?.toInt();
      if (def == null || seat == null || !mounted) return;
      setState(() {
        _live.add(RoomEmojiEvent(def, seat, (d['senderId'] as num?)?.toInt() ?? 0));
        while (_live.length > _max) {
          _live.removeAt(0);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final e in _live)
            _FloatingEmoji(
              key: ValueKey(e.key),
              event: e,
              origin: widget.resolveSeat(e.seatId),
              onDone: () {
                if (mounted) setState(() => _live.remove(e));
              },
            ),
        ],
      ),
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({super.key, required this.event, required this.origin, required this.onDone});
  final RoomEmojiEvent event;
  final Offset origin;
  final VoidCallback onDone;

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        // pop in (0–15%), hold with a gentle bob, fade out (80–100%).
        final scale = t < .15 ? Curves.elasticOut.transform(t / .15) : 1.0;
        final opacity = t > .8 ? (1 - (t - .8) / .2) : 1.0;
        final dy = -24 * t + 4 * (t * 6.28 * 2).remainder(6.28).clamp(0, 3.14) / 3.14;
        final dx = widget.event.def.drift * 36 * Curves.easeOut.transform(t);
        return Positioned(
          left: widget.origin.dx - size / 2 + dx,
          top: widget.origin.dy - size / 2 - 18 + dy,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale.clamp(0.0, 1.4), child: child),
          ),
        );
      },
      child: RepaintBoundary(child: roomEmojiArt(widget.event.def, size)),
    );
  }
}

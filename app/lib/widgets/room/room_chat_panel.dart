import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/room_controller_provider.dart';
import '../../models/room_event.dart';
import '../../services/socket_service.dart';
import '../../services/dio_client.dart';
import '../../providers/auth_provider.dart';
import '../../screens/profile_screen.dart';
import '../../utils/image_intrinsic_size.dart';
import 'TopWaveClipper.dart';

// ==========================
// 🔥 NEW: merged feed model
// ==========================
class RoomFeedItem {
  final bool isMessage;
  final SocketMessage? message;
  final RoomEvent? event;

  RoomFeedItem.message(this.message)
      : isMessage = true,
        event = null;

  RoomFeedItem.event(this.event)
      : isMessage = false,
        message = null;
}

class RoomChatPanel extends ConsumerStatefulWidget {
  final int roomId;

  /// Opens the room's own profile card for a chat writer. Supplied by
  /// RoomScreen — the card belongs to the room, so tapping a name must not
  /// navigate away from it.
  final void Function(int userId, String username)? onUserTap;

  const RoomChatPanel({super.key, required this.roomId, this.onUserTap});

  @override
  ConsumerState<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends ConsumerState<RoomChatPanel> {
  /// Default chat-bubble artwork and its 9-slice guides, in source pixels.
  /// Everything outside the slice rect is an end-cap and never stretches, so
  /// the bubble padding below has to clear those caps.
  static const String _bubbleAsset = 'assets/images/chat_bubble.png';
  static const Rect _bubbleSlice = Rect.fromLTRB(30, 13, 118, 23);

  final _text = TextEditingController();
  final _scroll = ScrollController();

  Timer? _typingTimer;
  bool _isTyping = false;

  // ✅ Filter index
  int _filterIndex = 0; // 0: الكل, 1: الهدايا, 2: الدردشة

  @override
  void dispose() {
    _typingTimer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sendTyping(bool typing) {
    ref.read(roomControllerProvider(widget.roomId).notifier).sendTyping(isTyping: typing);
  }

  void _onTextChanged(String v) {
    final nowTyping = v.trim().isNotEmpty;
    if (nowTyping != _isTyping) {
      _isTyping = nowTyping;
      _sendTyping(_isTyping);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        _sendTyping(false);
      }
    });
  }

  void _send() {
    final msg = _text.text.trim();
    if (msg.isEmpty) return;

    ref.read(roomControllerProvider(widget.roomId).notifier)
        .sendRoomMessage(message: msg);

    _text.clear();
    _onTextChanged('');

    Future.delayed(const Duration(milliseconds: 60), () {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// The app's own padding for the bundled bubble — clears its gold end-caps.
  /// Also the floor for a custom design whose inner box the dashboard hasn't
  /// been told about yet, so nothing regresses for existing products.
  static const EdgeInsets _defaultBubblePadding =
      EdgeInsets.symmetric(horizontal: 26, vertical: 12);

  /// Group 12: chat-bubble styling. A custom design (store/dashboard item)
  /// wins; otherwise the bubble is tiered by the sender's level.
  ///
  /// 2026-08-23 — custom designs are 9-SLICED like the bundled one instead of
  /// being stretched whole (`BoxFit.fill`). A decorated bubble's border used to
  /// smear as the message grew, and the text sat on top of it; now only the
  /// slice centre stretches and the writing is confined to the inner box the
  /// dashboard configured. Nothing here decides how tall the bubble is — the
  /// Container wraps its child, so 1, 2 or 5 lines each get a bubble that grew
  /// to fit ("وكبر مع كبر الكلام بالطول والعرض").
  BoxDecoration _bubbleDecoration(SocketMessage m) {
    final url = (m.bubbleUrl ?? '').trim();
    if (url.isNotEmpty) {
      // `centerSlice` is in the SOURCE image's pixels. This used to be handed
      // the BUNDLED artwork's 148x36, so an uploaded bubble of any other size
      // was sliced in the wrong place and its decoration smeared. The real
      // size is resolved once per URL and cached; until it arrives the slice
      // is skipped, which is exactly the pre-existing plain-stretch look.
      final intrinsic = _intrinsicBubbleSize(url);
      final slice = intrinsic == null ? null : m.bubbleLayout.centerSlice(intrinsic);
      return BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        image: DecorationImage(
          image: NetworkImage(url),
          // No slice configured → previous behaviour, so an un-migrated
          // product keeps rendering exactly as it did.
          centerSlice: slice,
          fit: BoxFit.fill,
          onError: (_, __) {},
        ),
      );
    }

    // Default bubble artwork. The source is 148x36 with its flat middle
    // between x 30..118 and y 13..23; 9-slicing there keeps the gold end-caps
    // undistorted no matter how long the message is.
    return const BoxDecoration(
      image: DecorationImage(
        image: AssetImage(_bubbleAsset),
        centerSlice: _bubbleSlice,
        fit: BoxFit.fill,
      ),
    );
  }

  /// Source-pixel size of a custom bubble's artwork, or null while it is still
  /// being resolved. Triggers exactly one resolve per URL and repaints when it
  /// lands.
  Size? _intrinsicBubbleSize(String url) {
    final known = ImageIntrinsicSize.peek(url);
    if (known != null) return known;
    ImageIntrinsicSize.resolve(url).then((size) {
      if (size != null && mounted) setState(() {});
    });
    return null;
  }

  static double _maxBubbleWidth(BuildContext context) =>
      MediaQuery.of(context).size.width * 0.85;

  /// Reference box the fractional inner insets resolve against.
  ///
  /// The bubble's real size depends on the padding, which depends on the
  /// bubble's size — so it is measured against the WIDEST a bubble may get
  /// instead. That errs towards a slightly roomier inner box on short
  /// messages, which is the safe direction: the text can only end up further
  /// inside the artwork, never spilling over its decoration.
  static Size _bubbleReference(BuildContext context) {
    final w = _maxBubbleWidth(context);
    return Size(w, w * 0.3);
  }

  /// Padding that keeps the writing inside the bubble's empty middle.
  EdgeInsets _bubblePadding(SocketMessage m, Size rendered) {
    if ((m.bubbleUrl ?? '').trim().isEmpty) return _defaultBubblePadding;
    final p = m.bubbleLayout.padding(rendered, _defaultBubblePadding);
    // Never tighter than the bundled padding: a mis-set 0.01 inset would put
    // the text hard against the edge.
    return EdgeInsets.only(
      left: p.left < _defaultBubblePadding.left ? _defaultBubblePadding.left : p.left,
      top: p.top < _defaultBubblePadding.top ? _defaultBubblePadding.top : p.top,
      right: p.right < _defaultBubblePadding.right ? _defaultBubblePadding.right : p.right,
      bottom:
          p.bottom < _defaultBubblePadding.bottom ? _defaultBubblePadding.bottom : p.bottom,
    );
  }

  /// Room-admin call shared by the chat user sheet. Sends both camelCase and
  /// snake_case ids because the older endpoints accept either spelling.
  Future<void> _roomAdminAction(
    String path,
    int userId,
    String okText, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await DioClient.dio.post(path, data: {
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'userId': userId,
        'user_id': userId,
        ...extra,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okText)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشلت العملية: $e')));
      }
    }
  }

  /// Opens the writer's card. Prefers the room's own profile dialog (same one
  /// the seats use, so the admin controls are right there); falls back to the
  /// full profile screen only if this panel was mounted without the callback.
  void _openProfile(int userId, String username) {
    if (userId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الملف الشخصي لهذا المستخدم')),
      );
      return;
    }
    final open = widget.onUserTap;
    if (open != null) {
      open(userId, username);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId, roomId: widget.roomId),
      ),
    );
  }

  /// #13: tap a chat message (anywhere on the bubble, not just the tiny name)
  /// → the writer's profile + admin moderation, even before they take a mic.
  void _showChatUserActions(int userId, String username) {
    final st = ref.read(roomControllerProvider(widget.roomId));
    final myId = ref.read(authStateProvider).user?.id;
    final isAdmin = myId != null && (myId == st.ownerId || st.adminIds.contains(myId));
    if (userId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الملف الشخصي لهذا المستخدم')),
      );
      return;
    }
    final isSelf = myId == userId;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(username, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.person, color: Colors.white),
                title: const Text('الملف الشخصي', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sctx);
                  _openProfile(userId, username);
                },
              ),
              if (isAdmin && !isSelf) ...[
                ListTile(
                  leading: const Icon(Icons.mic_off, color: Colors.orangeAccent),
                  title: const Text('منع من صعود المايك', style: TextStyle(color: Colors.orangeAccent)),
                  onTap: () {
                    Navigator.pop(sctx);
                    _roomAdminAction('room-admin/seat-block', userId,
                        'تم منع $username من صعود المايك',
                        extra: {'blocked': true});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('طرد من الغرفة', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(sctx);
                    _roomAdminAction('room-admin/kick', userId, 'تم طرد $username من الغرفة',
                        extra: {'minutes': 0});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: const Text('حظر من الغرفة', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(sctx);
                    _roomAdminAction('room-admin/ban', userId, 'تم حظر $username من الغرفة');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Small VIP / LV pill next to a name.
  static Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.7)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800),
        ),
      );

  /// One achievement icon. Never let a broken url punch a hole in a message.
  static Widget _badgeIcon(String url) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Image.network(
          url,
          width: 18,
          height: 18,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(roomControllerProvider(widget.roomId));

    final messages = st.messages;
    final events = st.events
        .where((event) => event.type == RoomEventType.gift||
        event.type == RoomEventType.join)
        .toList();

    // ==========================
    // 🔥 MERGE CHAT + ACTIVITY
    // ==========================
    final allFeed = <RoomFeedItem>[
      ...messages.map((m) => RoomFeedItem.message(m)),
      ...events.map((e) => RoomFeedItem.event(e)),
    ];

    // ==========================
    // 🔥 SORT BY TIME
    // ==========================
    allFeed.sort((a, b) {
      final aTime = a.isMessage
          ? a.message!.timestamp
          : a.event!.at.millisecondsSinceEpoch;

      final bTime = b.isMessage
          ? b.message!.timestamp
          : b.event!.at.millisecondsSinceEpoch;

      return aTime.compareTo(bTime);
    });

    // ✅ APPLY FILTERING
    final feed = allFeed.where((item) {
      if (_filterIndex == 0) return true; // الكل
      if (_filterIndex == 1) return !item.isMessage && item.event?.type == RoomEventType.gift; // الهدايا
      if (_filterIndex == 2) return item.isMessage; // الدردشة
      return true;
    }).toList();

    // auto scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Align(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
        decoration: BoxDecoration(
          color: Colors.transparent, // 🔥 important
        ),
        child: Column(
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

            // ✅ Updated: Filter Tabs (Right Aligned, Glass Design, Bigger)
            _buildFilterTabs(),

            const SizedBox(height: 12),

            // ==========================
            // 🔥 ONE LIST (CHAT + EVENTS)
            // ==========================
            Expanded(
              child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: ListView.builder(
                    controller: _scroll,
                    reverse: false, // ✅ NORMAL TOP → DOWN
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: feed.length,
                    itemBuilder: (_, i) {
                      final item = feed[i]; // ✅ NORMAL ORDER

                      // ===== CHAT =====
                      if (item.isMessage) {
                        final m = item.message!;

                        final time = DateTime.fromMillisecondsSinceEpoch(m.timestamp);
                        final timeStr =
                            "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: TweenAnimationBuilder(
                            duration: const Duration(milliseconds: 350),
                            tween: Tween(begin: 60.0, end: 0.0), // 👈 slide from RIGHT
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(value, 0),
                                child: Opacity(
                                  opacity: 1 - (value / 60),
                                  child: child,
                                ),
                              );
                            },
                            child: Align(
                              alignment: Alignment.centerRight, // ✅ RIGHT SIDE
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                // #13: the whole bubble opens the writer's card —
                                // the 11px name alone was too small to hit.
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  // Whole bubble opens the same card as the
                                  // name — one behaviour, and the 11px name was
                                  // too small a target on its own.
                                  onTap: () => _openProfile(m.userId, m.username),
                                  onLongPress: () => _showChatUserActions(m.userId, m.username),
                                  child: Stack(
                                  children: [
                                    // 💬 BUBBLE — custom design if the sender
                                    // activated one, otherwise tiered by level.
                                    Container(
                                      constraints: BoxConstraints(maxWidth: _maxBubbleWidth(context)),
                                      // Confined to the artwork's empty middle.
                                      padding: _bubblePadding(m, _bubbleReference(context)),
                                      decoration: _bubbleDecoration(m),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          // Tapping the NAME goes straight to the
                                          // writer's page (with the room's
                                          // kick/mute controls on it) — the
                                          // menu was an extra step in the way
                                          // of "من ده؟ اطرده". The rest of the
                                          // bubble still opens the quick menu.
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => _openProfile(m.userId, m.username),
                                            child: Padding(
                                              // Bigger touch target: 11px text
                                              // was near impossible to hit.
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      m.username,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(0xFFFFD54F),
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        decoration: TextDecoration.underline,
                                                        decorationColor: Color(0x66FFD54F),
                                                      ),
                                                      textAlign: TextAlign.right,
                                                    ),
                                                  ),
                                                  // "فهد  VIP 6 · LV 8" — the
                                                  // writer's standing sits with
                                                  // his name, above the text.
                                                  if (m.vipLevel > 0) ...[
                                                    const SizedBox(width: 6),
                                                    _chip('VIP ${m.vipLevel}', const Color(0xFFFFB300)),
                                                  ],
                                                  const SizedBox(width: 5),
                                                  _chip('LV ${m.level}', const Color(0xFF7C4DFF)),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // شارات المستخدم — under the name,
                                          // before what he wrote.
                                          if (m.badges.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                for (final b in m.badges) _badgeIcon(b),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 2),
                                          Text(
                                            m.message,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            timeStr,
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                        ],
                                      ),
                                    ),

                                    // 🔻 RTL TAIL
                                    Positioned(
                                      right: -6,
                                      bottom: 6,
                                      child: CustomPaint(
                                        size: const Size(16, 16),
                                        painter: _BubbleTailPainter(),
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

                      // ===== ACTIVITY ITEM =====
                      final e = item.event!;
                      final username = (e.username == null || e.username!.trim().isEmpty)
                          ? 'مستخدم'
                          : e.username!.trim();
                      final icon = e.type == RoomEventType.join
                          ? Icons.login_rounded
                          : Icons.card_giftcard_rounded;
                      // "فهد VIP 6 · LV 8 دخل الغرفة" — the entrant's standing
                      // belongs on the line, not just his name.
                      final standing = [
                        if ((e.vipLevel ?? 0) > 0) 'VIP ${e.vipLevel}',
                        if ((e.level ?? 0) > 0) 'LV ${e.level}',
                      ].join(' · ');
                      final line = standing.isEmpty
                          ? '$username ${e.text}'
                          : '$username  $standing  ${e.text}';

                      // Gift and join lines open the same card as a chat
                      // bubble — the tap has to work under كل تبويب: الكل,
                      // الهدايا and الدردشة, not only on messages.
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: e.userId == null
                              ? null
                              : () => _openProfile(e.userId!, username),
                          child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1a4a1a), Color(0xFF2d7a2d), Color(0xFF1a4a1a)],
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                            ),
                            border: Border.all(color: const Color(0xFF4caf50), width: 1.5),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, color: Colors.white, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // شارات الداخل، بعد السطر.
                              for (final b in e.badges) _badgeIcon(b),
                            ],
                          ),
                        ),
                        ),
                      );
                    },
                  )
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Updated: Tab Builder (Explicitly Right Aligned for RTL)
  Widget _buildFilterTabs() {
    return Align(
      alignment: Alignment.centerRight, // 👈 Force alignment to the right
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min, // 👈 Only take needed space
          children: [
            _tabItem(0, "الكل"),
            const SizedBox(width: 12),
            _tabItem(1, "الهدايا"),
            const SizedBox(width: 12),
            _tabItem(2, "الدردشة"),
          ],
        ),
      ),
    );
  }

  Widget _tabItem(int index, String label) {
    final isSelected = _filterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _filterIndex = index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // ✅ Glass effect
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), // ✅ Bigger button
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withOpacity(0.25) // Selected glass
                  : Colors.white.withOpacity(0.08), // Unselected glass
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: isSelected ? Colors.white54 : Colors.white12,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 14, // ✅ Bigger text
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                shadows: isSelected ? [
                  Shadow(
                    blurRadius: 10.0,
                    color: Colors.black45,
                    offset: Offset(2.0, 2.0),
                  ),
                ] : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.deepPurple.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
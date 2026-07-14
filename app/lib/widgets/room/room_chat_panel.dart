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
  const RoomChatPanel({super.key, required this.roomId});

  @override
  ConsumerState<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends ConsumerState<RoomChatPanel> {
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

  /// #13: tap a chat-writer's name → profile + (admin) kick from room, even
  /// before they take a mic.
  void _showChatUserActions(int userId, String username) {
    final st = ref.read(roomControllerProvider(widget.roomId));
    final myId = ref.read(authStateProvider).user?.id;
    final isAdmin = myId != null && (myId == st.ownerId || st.adminIds.contains(myId));
    if (myId == userId) return; // no actions on self
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
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: const Text('طرد من الغرفة', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(sctx);
                    try {
                      await DioClient.dio.post('room-admin/kick', data: {
                        'roomId': widget.roomId,
                        'room_id': widget.roomId,
                        'userId': userId,
                        'user_id': userId,
                        'minutes': 0,
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تم طرد $username من الغرفة')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر الطرد: $e')));
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

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
                                child: Stack(
                                  children: [
                                    // 💬 BUBBLE
                                    Container(
                                      constraints: BoxConstraints(
                                        maxWidth: MediaQuery.of(context).size.width * 0.85,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple.withOpacity(0.6), // 🔥 visible
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          GestureDetector(
                                            onTap: () => _showChatUserActions(m.userId, m.username),
                                            child: Text(
                                              m.username,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
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
                      final line = '$username ${e.text}';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
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
                            ],
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
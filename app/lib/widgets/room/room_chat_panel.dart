import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/room_controller_provider.dart';
import '../../models/room_event.dart';
import '../../services/socket_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(roomControllerProvider(widget.roomId));

    final messages = st.messages;
    final events = st.events;

    // ==========================
    // 🔥 MERGE CHAT + ACTIVITY
    // ==========================
    final feed = <RoomFeedItem>[
      ...messages.map((m) => RoomFeedItem.message(m)),
      ...events.map((e) => RoomFeedItem.event(e)),
    ];

    // ==========================
    // 🔥 SORT BY TIME
    // ==========================
    feed.sort((a, b) {
      final aTime = a.isMessage
          ? a.message!.timestamp
          : a.event!.at.millisecondsSinceEpoch;

      final bTime = b.isMessage
          ? b.message!.timestamp
          : b.event!.at.millisecondsSinceEpoch;

      return aTime.compareTo(bTime);
    });

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
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),


            const SizedBox(height: 8),

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
                                        Text(
                                          m.username,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                          textAlign: TextAlign.right,
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

                    // ===== ACTIVITY =====
                    // In _RoomChatPanelState build(), replace the activity item builder:

// ===== ACTIVITY ITEM =====
                    final e = item.event!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Right side: badge + name + coins
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Kingdom/team badge (if available)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFf9a825),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    e.badge ?? 'نشاط', // replace with actual badge if available
                                    style: const TextStyle(
                                      color: Color(0xFF4e2d00),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Name
                                Text(
                                  e.username ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Coins
                                const Icon(Icons.monetization_on, color: Color(0xFFffe082), size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  '${e.coins ?? 0}',
                                  style: const TextStyle(color: Color(0xFFffe082), fontSize: 12),
                                ),
                              ],
                            ),
                            // Left side: action buttons
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Gift button
                                GestureDetector(
                                  onTap: () {/* open gift sheet */},
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF388e3c),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.card_giftcard, color: Colors.white, size: 14),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Message button
                                GestureDetector(
                                  onTap: () {/* open chat */},
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1565c0),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.chat_bubble, color: Colors.white, size: 14),
                                  ),
                                ),
                              ],
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
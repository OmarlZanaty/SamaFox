import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/room_controller_provider.dart';
import '../providers/room_live_provider.dart';

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
  void initState() {
    super.initState();
    ref.read(roomLiveProvider(widget.roomId).notifier).bind();
  }

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

    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    ref.read(roomControllerProvider(widget.roomId).notifier).sendRoomMessage(message: msg);

    _text.clear();
    _onTextChanged('');

    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(roomLiveProvider(widget.roomId)).messages;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        // ✅ this is the ONLY panel
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),

        // ✅ IMPORTANT: kill any implicit padding from Material
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Column(
            children: [
              // header
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Row(
                  children: const [
                    Icon(Icons.chat_bubble_outline, color: Colors.white70, size: 18),
                    SizedBox(width: 6),
                    Text('Chat', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),

              // messages
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${m.username}: ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            TextSpan(
                              text: m.message,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // input
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        onChanged: _onTextChanged,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Type...',
                          hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _send,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


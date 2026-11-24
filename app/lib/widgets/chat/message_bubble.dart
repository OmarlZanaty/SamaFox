import 'package:flutter/material.dart';
import '../../models/direct_message.dart';
import '../../services/room_link_handler.dart';
import 'chat_ui_helpers.dart';
import 'reaction_picker.dart';
import 'voice_message_bubble.dart';
import 'bubble_skin.dart';
import '../app_network_image.dart';
import '../../l10n/tr.dart';

class MessageBubble extends StatelessWidget {
  final DirectMessage m;
  final bool isMe;
  final bool isDark;
  final VoidCallback? onLongPress;
  final Future<void> Function(String emoji)? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final VoidCallback? onPlayVoice;

  const MessageBubble({
    super.key,
    required this.m,
    required this.isMe,
    required this.isDark,
    this.onReact,
    this.onRetry,
    this.onPin,
    this.onUnpin,
    this.onPlayVoice,
    this.onLongPress, // ✅ add

  });

  String? get _imageUrl {
    final u = m.metadata?['imageUrl'];
    return (u is String && u.isNotEmpty) ? u : null;
  }

  void _openFullImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: AppNetworkImage(
              url,
              fit: BoxFit.contain,
              cacheWidth: 1600,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined, size: 64, color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final status = receiptFor(
      isMe: isMe,
      deliveredAt: m.deliveredAt,
      readAt: m.readAt,
      localSending: m.localStatus == LocalMsgStatus.sending,
    );

    final statusColor = isDark ? Colors.white70 : Colors.black54;

    Widget core;
    if (m.type == 'voice') {
      core = VoiceMessageBubble(
        createdAt: m.createdAt,
        isMe: isMe,
        isDark: isDark,
        onPlay: onPlayVoice ?? () {},
        trailing: isMe ? receiptIcon(status, color: statusColor) : null,
      );
    } else {
      final bg = isMe
          ? (isDark ? Colors.white12 : Colors.black.withOpacity(0.06))
          : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04));

      // C6 — the sender's bought bubble, the same rendering the room uses. With
      // no design equipped this falls back to the flat DM bubble, so a user who
      // owns nothing sees no change at all.
      core = BubbleSkin(
        bubbleUrl: m.bubbleUrl,
        layout: m.bubbleLayout,
        maxWidthFactor: 0.78,
        defaultPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        plainDecoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: align,
          children: [
            if (m.type == 'room_invite' && m.metadata != null) ...[
              Text(tr('${m.metadata!['inviterName'] ?? ''} يدعوك للانضمام إلى غرفة:', '${m.metadata!['inviterName'] ?? ''} invites you to join a room:'),
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
              if (m.metadata!['roomImageUrl'] is String)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Image.network(
                  m.metadata!['roomImageUrl'] as String, height: 100, width: double.infinity,
                  fit: BoxFit.cover, cacheWidth: 480,
                  errorBuilder: (_, __, ___) => const Icon(Icons.meeting_room, size: 48),
                )),
              Text('${m.metadata!['roomName'] ?? ''}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              Text('ID: ${m.metadata!['roomDisplayId'] ?? m.metadata!['roomId'] ?? ''}',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12)),
              TextButton.icon(onPressed: () {
                final token = m.metadata!['token'];
                if (token is String) RoomLinkHandler.instance.accept(token);
              }, icon: const Icon(Icons.login), label: Text(tr('دخول الغرفة', 'Enter room'))),
            ] else if (m.type == 'image' && _imageUrl != null) ...[
              GestureDetector(
                onTap: () => _openFullImage(context, _imageUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppNetworkImage(
                    _imageUrl!,
                    width: 220,
                    height: 220,
                    fit: BoxFit.cover,
                    cacheWidth: 480,
                    placeholder: const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 220,
                      height: 120,
                      child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
                    ),
                  ),
                ),
              ),
              if (m.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    m.text,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                  ),
                ),
            ] else Text(
              m.text,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(shortTime(m.createdAt), style: TextStyle(fontSize: 11, color: statusColor)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  receiptIcon(status, color: statusColor),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          GestureDetector(
            onLongPress: () async {
              if (onLongPress != null) {
                onLongPress!(); // ✅ open your bottom sheet (copy/delete + reactions)
                return;
              }

              // fallback: old behavior
              if (m.id <= 0) return;
              final emoji = await showReactionPicker(context, current: m.myReaction);
              if (emoji != null && onReact != null) await onReact!(emoji);
            },
            child: core,
          ),

          // Reactions
          ReactionsRow(
            reactions: m.reactions,
            myReaction: m.myReaction,
            onTap: () async {
              if (m.id <= 0) return;
              final emoji = await showReactionPicker(context, current: m.myReaction);
              if (emoji != null && onReact != null) await onReact!(emoji);
            },
          ),

          // Failed retry
          if (isMe && m.localStatus == LocalMsgStatus.failed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: onRetry,
                child: Text(
                  'Failed. Tap to retry',
                  style: TextStyle(color: Colors.red[400], fontSize: 12),
                ),
              ),
            ),

          // Pin indicator
          if (m.pinnedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('📌 Pinned', style: TextStyle(fontSize: 11, color: statusColor)),
            ),
        ],
      ),
    );
  }
}

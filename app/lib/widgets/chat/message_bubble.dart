import 'package:flutter/material.dart';
import '../../models/direct_message.dart';
import 'chat_ui_helpers.dart';
import 'reaction_picker.dart';
import 'voice_message_bubble.dart';

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

      core = Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: align,
          children: [
            Text(
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
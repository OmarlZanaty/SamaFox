import 'package:flutter/material.dart';
import 'chat_ui_helpers.dart';

class VoiceMessageBubble extends StatelessWidget {
  final String createdAt;
  final bool isMe;
  final bool isDark;
  final VoidCallback onPlay;
  final Widget? trailing; // receipts, etc.

  const VoiceMessageBubble({
    super.key,
    required this.createdAt,
    required this.isMe,
    required this.isDark,
    required this.onPlay,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe
        ? (isDark ? Colors.white12 : Colors.black.withOpacity(0.06))
        : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onPlay,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.play_arrow, size: 22, color: isDark ? Colors.white : Colors.black87),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 120,
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
            ),
          ),
          const SizedBox(width: 10),
          Text(shortTime(createdAt), style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black54)),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );
  }
}
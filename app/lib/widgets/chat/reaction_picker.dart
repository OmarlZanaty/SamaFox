import 'package:flutter/material.dart';

Future<String?> showReactionPicker(BuildContext context, {String? current}) {
  const emojis = ['❤️', '😂', '🔥', '👍', '😮', '😢'];
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            borderRadius: BorderRadius.circular(18),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black87
                : Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: emojis.map((e) {
                  final selected = (current == e);
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, e),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: selected
                            ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.white12
                            : Colors.black.withOpacity(0.06))
                            : Colors.transparent,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ReactionsRow extends StatelessWidget {
  final Map<String, int> reactions;
  final String? myReaction;
  final VoidCallback? onTap;

  const ReactionsRow({
    super.key,
    required this.reactions,
    required this.myReaction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final entries = reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white12
              : Colors.black.withOpacity(0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: entries.take(3).map((e) {
            final isMine = (myReaction == e.key);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${e.key} ${e.value}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
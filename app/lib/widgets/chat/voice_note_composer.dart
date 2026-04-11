import 'package:flutter/material.dart';

class VoiceNoteComposer extends StatelessWidget {
  final bool isRecording;
  final Duration elapsed;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const VoiceNoteComposer({
    super.key,
    required this.isRecording,
    required this.elapsed,
    required this.onStart,
    required this.onStop,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isRecording) {
      return IconButton(
        onPressed: onStart,
        icon: Icon(Icons.mic, color: isDark ? Colors.white70 : Colors.black54),
      );
    }

    final mm = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$mm:$ss', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onStop,
          icon: const Icon(Icons.stop_circle, size: 28),
        ),
        IconButton(
          onPressed: onCancel,
          icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
        ),
        IconButton(
          onPressed: onSend,
          icon: Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
        ),
      ],
    );
  }
}
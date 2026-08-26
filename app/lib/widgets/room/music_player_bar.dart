import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/music_provider.dart';

/// Floating music control bar.
///
/// It is deliberately draggable: the owner asked to be able to push it out of
/// the way ("انقله في المكان اللي انا مش محتاج اتعامل فيه"), so it never sits
/// on top of the seats or the chat. It only renders while the room actually
/// has music playing, and only for people allowed to control it.
///
/// Buttons, in the order requested:
///   ⏪ previous · ▶ play · ⏸ pause · ⏭ next · ✖ stop (bar disappears)
class MusicPlayerBar extends ConsumerStatefulWidget {
  const MusicPlayerBar({super.key, required this.roomId, required this.canControl});

  final int roomId;
  final bool canControl;

  @override
  ConsumerState<MusicPlayerBar> createState() => _MusicPlayerBarState();
}

class _MusicPlayerBarState extends ConsumerState<MusicPlayerBar> {
  /// null until the first layout, then it starts pinned to the left edge just
  /// under the header — out of the way of the seats.
  Offset? _offset;

  static const double _barWidth = 232;
  static const double _barHeight = 62;

  StreamSubscription<String>? _deniedSub;

  @override
  void initState() {
    super.initState();
    // Fires if the server refuses a control action — e.g. the user was demoted
    // while the bar was still on screen.
    _deniedSub = ref
        .read(roomMusicProvider(widget.roomId).notifier)
        .deniedStream
        .listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, textDirection: TextDirection.rtl),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  void dispose() {
    _deniedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = ref.watch(roomMusicProvider(widget.roomId));
    if (!music.active || !widget.canControl) return const SizedBox.shrink();

    final notifier = ref.read(roomMusicProvider(widget.roomId).notifier);
    final size = MediaQuery.of(context).size;
    final maxX = (size.width - _barWidth).clamp(0.0, double.infinity);
    final maxY = (size.height - _barHeight - 24).clamp(0.0, double.infinity);

    final offset = _offset ?? Offset(8, size.height * 0.22);
    final clamped = Offset(
      offset.dx.clamp(0.0, maxX),
      offset.dy.clamp(0.0, maxY),
    );

    return Positioned(
      left: clamped.dx,
      top: clamped.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _offset = Offset(
            (clamped.dx + d.delta.dx).clamp(0.0, maxX),
            (clamped.dy + d.delta.dy).clamp(0.0, maxY),
          );
        }),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _barWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1655), Color(0xFF6B4CE6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B4CE6).withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      music.isPlaying ? Icons.graphic_eq : Icons.music_note,
                      size: 14,
                      color: music.isPlaying ? Colors.greenAccent : Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        music.currentTitle.isEmpty ? 'موسيقى الغرفة' : music.currentTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(color: Colors.white, fontSize: 11.5),
                      ),
                    ),
                    if (music.queue.length > 1)
                      Text(
                        '${music.index + 1}/${music.queue.length}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ctrl(Icons.fast_rewind, 'السابق', notifier.previous),
                    _ctrl(
                      Icons.play_arrow,
                      'تشغيل',
                      notifier.resume,
                      dim: music.isPlaying,
                    ),
                    _ctrl(
                      Icons.pause,
                      'إيقاف مؤقت',
                      notifier.pause,
                      dim: !music.isPlaying,
                    ),
                    _ctrl(Icons.fast_forward, 'التالي', notifier.next),
                    _ctrl(Icons.close, 'إنهاء', notifier.stop, color: Colors.redAccent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ctrl(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool dim = false,
    Color color = Colors.white,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Icon(
            icon,
            size: 22,
            color: dim ? color.withOpacity(0.35) : color,
          ),
        ),
      ),
    );
  }
}

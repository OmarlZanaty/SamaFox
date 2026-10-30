import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../room_emoji.dart';

/// Plays a room emoji INSIDE the sender's own avatar circle: pop in, wiggle
/// for ~3 s, then fade back to the photo. Dice/slot roll for ~1.2 s and then
/// hold the server's result. A new emoji from the same user replaces the one
/// that is playing.
class SeatEmoji extends StatefulWidget {
  const SeatEmoji({super.key, required this.senderId, required this.child});

  final int senderId;
  final Widget child;

  static const duration = Duration(milliseconds: 3000);

  @override
  State<SeatEmoji> createState() => _SeatEmojiState();
}

class _SeatEmojiState extends State<SeatEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: SeatEmoji.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _event = null);
    });
  StreamSubscription<RoomEmojiEvent>? _sub;
  RoomEmojiEvent? _event;

  @override
  void initState() {
    super.initState();
    _sub = roomEmojiEvents.stream.listen((e) {
      if (!mounted || e.senderId != widget.senderId) return;
      setState(() => _event = e);
      _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(SeatEmoji old) {
    super.didUpdateWidget(old);
    if (old.senderId != widget.senderId && _event != null) {
      _c.stop();
      _event = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    if (e == null) return widget.child;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) => _frame(e, _c.value, box.biggest.shortestSide),
          ),
        ),
      ),
    ]);
  }

  Widget _frame(RoomEmojiEvent e, double t, double side) {
    // Pop in (0 → 1.15 → 1) during the first 12%, fade back out in the last 10%.
    final double scale = t < .08
        ? Curves.easeOut.transform(t / .08) * 1.15
        : t < .14
            ? 1.15 - .15 * ((t - .08) / .06)
            : 1.0;
    final double fade = t > .9 ? (1 - (t - .9) / .1).clamp(0.0, 1.0) : 1.0;
    final rollEnd = 1200 / SeatEmoji.duration.inMilliseconds;
    final rolling = e.def.isGame && t < rollEnd;
    // Lively wiggle/bounce once it is in; a game emoji only wiggles after it lands.
    final live = t >= .14 && !rolling;
    final double wiggle = live ? math.sin(t * math.pi * 2 * 5) * (8 * math.pi / 180) : 0.0;
    final double bounce = live ? -math.sin(t * math.pi * 2 * 3).abs() * side * .05 : 0.0;
    final art = roomEmojiArt(
      e.def,
      side * .92,
      result: e.result,
      rollPhase: rolling ? t / rollEnd : null,
    );
    return Opacity(
      opacity: fade,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(colors: [Color(0xFF3B2470), Color(0xFF160C33)]),
        ),
        child: Center(
          child: Transform.translate(
            offset: Offset(0, bounce),
            child: Transform.rotate(
              angle: wiggle,
              child: Transform.scale(scale: scale, child: art),
            ),
          ),
        ),
      ),
    );
  }
}

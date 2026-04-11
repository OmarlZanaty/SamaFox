import 'package:flutter/material.dart';

class TypingIndicatorBar extends StatelessWidget {
  final bool isTyping;
  final String partnerName;
  final bool isDark;

  const TypingIndicatorBar({
    super.key,
    required this.isTyping,
    required this.partnerName,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (!isTyping) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          _Dots(isDark: isDark),
          const SizedBox(width: 8),
          Text(
            '$partnerName is typing…',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  final bool isDark;
  const _Dots({required this.isDark});

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark ? Colors.white70 : Colors.black54;

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        double op(int i) {
          // 3 dots pulse
          final p = (t * 3 - i).abs();
          final v = (1 - p).clamp(0.2, 1.0);
          return v;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Opacity(
              opacity: op(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: base, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
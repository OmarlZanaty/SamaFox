import 'dart:async';

import 'package:flutter/material.dart';

/// #43 — "لو اسم الروم طويل ومش ظاهر كامل، يمشي من الشمال لليمين لحد ما يظهر
/// الاسم كامل — سواء داخل الروم أو على كارت الروم في القائمة بالخارج."
///
/// Renders exactly like a normal single-line [Text] when the string fits, and
/// only starts scrolling when it genuinely overflows — a name that fits should
/// never wander, which is why this measures first instead of animating
/// unconditionally.
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.velocity = 26,
    this.pause = const Duration(seconds: 1),
    this.gap = 40,
  });

  final String text;
  final TextStyle? style;

  /// Alignment used only in the non-overflowing case.
  final TextAlign textAlign;

  /// Logical pixels per second.
  final double velocity;

  /// Hold at each end before travelling back.
  final Duration pause;

  /// Blank space after the text before it wraps back into view.
  final double gap;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  Timer? _timer;
  bool _running = false;

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A renamed room restarts the cycle from the beginning.
    if (oldWidget.text != widget.text) {
      _stop();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _stop();
    _scroll.dispose();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  /// Starts the back-and-forth once, after the first frame that proves the text
  /// really is wider than its box.
  void _ensureRunning() {
    if (_running) return;
    _running = true;
    _timer = Timer(widget.pause, _cycle);
  }

  Future<void> _cycle() async {
    while (mounted && _scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) {
        // The name now fits (window resize, rename) — stop rather than spin.
        _running = false;
        return;
      }
      final ms = (max / widget.velocity * 1000).clamp(600, 20000).toInt();
      await _scroll.animateTo(
        max,
        duration: Duration(milliseconds: ms),
        curve: Curves.linear,
      );
      if (!mounted) return;
      await Future<void>.delayed(widget.pause);
      if (!mounted || !_scroll.hasClients) return;
      await _scroll.animateTo(
        0,
        duration: Duration(milliseconds: ms),
        curve: Curves.linear,
      );
      if (!mounted) return;
      await Future<void>.delayed(widget.pause);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        final overflows = painter.width > constraints.maxWidth;
        if (!overflows) {
          _stop();
          return Text(
            widget.text,
            maxLines: 1,
            textAlign: widget.textAlign,
            style: style,
          );
        }

        // Scheduled rather than called inline: starting an animation during
        // layout would throw.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureRunning();
        });

        return SizedBox(
          height: painter.height,
          child: ListView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              Text(widget.text, maxLines: 1, style: style),
              SizedBox(width: widget.gap),
            ],
          ),
        );
      },
    );
  }
}

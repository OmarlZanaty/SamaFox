import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'yummy_fx.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

/// Free spins: the intro card, the counter strip shown while they play, and
/// the summary. The spins themselves are replayed on the main machine by the
/// screen; nothing here decides or changes an outcome.

/// "8 FREE SPINS · ×2". Starts on tap, or by itself after [autoStart].
class YummyFreeSpinsIntro extends StatefulWidget {
  final int count, multiplier;
  final YummyStrings strings;
  final bool reduced, lite;
  final Duration autoStart;
  final VoidCallback onStart;
  const YummyFreeSpinsIntro({
    super.key,
    required this.count,
    required this.multiplier,
    required this.strings,
    required this.onStart,
    this.reduced = false,
    this.lite = false,
    this.autoStart = const Duration(seconds: 4),
  });

  @override
  State<YummyFreeSpinsIntro> createState() => _YummyFreeSpinsIntroState();
}

class _YummyFreeSpinsIntroState extends State<YummyFreeSpinsIntro> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.autoStart, _start);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_done || !mounted) return;
    _done = true;
    _timer?.cancel();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _start,
      child: Semantics(
        liveRegion: true,
        label:
            '${widget.count} ${strings.text('freeSpins')} ×${widget.multiplier}',
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0xE67A1FA2), Color(0xF2140530)],
                  ),
                ),
              ),
            ),
            if (!widget.reduced)
              Positioned.fill(
                child: YummyCoinRain(
                  seconds: 1.6,
                  perSecond: 14,
                  lite: widget.lite,
                ),
              ),
            _PopIn(
              animate: !widget.reduced,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Bob(
                    animate: !widget.reduced,
                    child: Image.asset(
                      '${yummyArt}bonus_open.png',
                      height: 170,
                      cacheWidth: 400,
                      errorBuilder: (_, __, ___) =>
                          const Text('🎁', style: TextStyle(fontSize: 110)),
                    ),
                  ),
                  YummyOutlinedText('${widget.count}', size: 76),
                  YummyOutlinedText(strings.text('freeSpins'), size: 40),
                  const SizedBox(height: 10),
                  YummyMultiplierBadge(
                    multiplier: widget.multiplier,
                    big: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.text('freeSpinsRule'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: yummyGold,
                      foregroundColor: yummyInk,
                      minimumSize: const Size(180, 54),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      strings.text('start'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The strip over the machine while free spins play: spin 3/8, ×2, total.
class YummyFreeSpinsHud extends StatelessWidget {
  final int spin, count, multiplier, total;
  final YummyStrings strings;
  const YummyFreeSpinsHud({
    super.key,
    required this.spin,
    required this.count,
    required this.multiplier,
    required this.total,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: '${strings.text('freeSpin')} $spin / $count',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB03CE0), Color(0xFFFF4B86)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x88FF4B86), blurRadius: 14),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.card_giftcard, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  alignment: AlignmentDirectional.centerStart,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${strings.text('freeSpin')}  $spin / $count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              YummyMultiplierBadge(multiplier: multiplier),
              const SizedBox(width: 8),
              const Icon(Icons.toll, color: yummyGold, size: 20),
              const SizedBox(width: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(end: total.toDouble()),
                duration: const Duration(milliseconds: 700),
                builder: (context, value, _) => Text(
                  '${value.round()}',
                  style: const TextStyle(
                    color: yummyGold,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// "FREE SPINS WIN 12,400" with coins. Closes on tap or after [autoClose].
class YummyFreeSpinsSummary extends StatefulWidget {
  final int total, count;
  final bool capped;
  final YummyStrings strings;
  final bool reduced, lite;
  final Duration autoClose;
  final VoidCallback onDone;
  const YummyFreeSpinsSummary({
    super.key,
    required this.total,
    required this.count,
    required this.strings,
    required this.onDone,
    this.capped = false,
    this.reduced = false,
    this.lite = false,
    this.autoClose = const Duration(seconds: 5),
  });

  @override
  State<YummyFreeSpinsSummary> createState() => _YummyFreeSpinsSummaryState();
}

class _YummyFreeSpinsSummaryState extends State<YummyFreeSpinsSummary> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.autoClose, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
    if (_done || !mounted) return;
    _done = true;
    _timer?.cancel();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: Semantics(
        liveRegion: true,
        label: '${strings.text('freeSpinsWin')} ${widget.total}',
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0xE6B03CE0), Color(0xF2140530)],
                  ),
                ),
              ),
            ),
            if (!widget.reduced && widget.total > 0)
              Positioned.fill(
                child: YummyCoinRain(seconds: 2.6, lite: widget.lite),
              ),
            _PopIn(
              animate: !widget.reduced,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  YummyOutlinedText(strings.text('freeSpinsWin'), size: 40),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: yummyGold, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.toll, color: yummyGold, size: 34),
                        const SizedBox(width: 10),
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: widget.reduced ? widget.total.toDouble() : 0,
                            end: widget.total.toDouble(),
                          ),
                          duration: const Duration(milliseconds: 1800),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => Text(
                            '${value.round()}',
                            style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.count} ${strings.text('freeSpins')}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  if (widget.capped)
                    Text(
                      strings.text('capped'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    strings.text('tapToContinue'),
                    style: const TextStyle(fontSize: 15, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round "×3" badge; [big] for the intro card.
class YummyMultiplierBadge extends StatelessWidget {
  final int multiplier;
  final bool big, active;
  const YummyMultiplierBadge({
    super.key,
    required this.multiplier,
    this.big = false,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    final size = big ? 64.0 : 36.0;
    return AnimatedScale(
      scale: active ? 1 : .82,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active
              ? const RadialGradient(
                  colors: [Color(0xFFFFF6B8), yummyGold, Color(0xFFFF9A25)],
                )
              : const RadialGradient(
                  colors: [Color(0xFF8C7BA8), Color(0xFF4A3A66)],
                ),
          border: Border.all(color: Colors.white, width: big ? 3 : 2),
          boxShadow: active
              ? const [BoxShadow(color: Color(0x99FFB300), blurRadius: 10)]
              : null,
        ),
        child: Text(
          '×$multiplier',
          style: TextStyle(
            fontSize: big ? 26 : 14,
            fontWeight: FontWeight.w900,
            color: active ? yummyInk : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// Gold gradient title with a dark outline, used by every overlay.
class YummyOutlinedText extends StatelessWidget {
  final String text;
  final double size;
  const YummyOutlinedText(this.text, {super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        children: [
          Text(
            text,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = size / 6
                ..color = const Color(0xFF2A0B4F),
            ),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFBD0), yummyGold, Color(0xFFFF9A25)],
            ).createShader(bounds),
            child: Text(
              text,
              style: base.copyWith(
                color: Colors.white,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopIn extends StatelessWidget {
  final Widget child;
  final bool animate;
  const _PopIn({required this.child, required this.animate});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? .3 : 1, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: child,
      );
}

/// A gentle hover for the open chest; runs a fixed number of cycles so the
/// overlay can settle.
class _Bob extends StatefulWidget {
  final Widget child;
  final bool animate;
  const _Bob({required this.child, required this.animate});
  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(count: 4);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = _c.value * 2 * math.pi;
          return Transform.translate(
            offset: Offset(0, math.sin(t) * 6),
            child: Transform.rotate(angle: math.sin(t) * .03, child: child),
          );
        },
      );
}

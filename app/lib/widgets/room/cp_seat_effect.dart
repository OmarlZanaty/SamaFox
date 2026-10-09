import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/socket_service.dart';

/// A CP pair sitting on two neighbouring seats.
class CpEffectPair {
  const CpEffectPair({required this.link, required this.seatA, required this.seatB});
  final CpSeatLink link;
  final int seatA;
  final int seatB;
}

/// تأثير CP Level — a premium heart drawn around two CP partners who sit on
/// neighbouring mics.
///
/// Layered BEHIND the seat grid (see SeatsGrid), so faces, mics, names and the
/// coins line always stay on top of it. It is removed simply by not being in
/// the next seat snapshot: a partner leaving the mic or the room, or the level
/// no longer qualifying, all produce a snapshot without the link.
///
/// Everything it needs to know — which effect, how fast, for how long — comes
/// from the server (لوحة التحكم ← CP Level Management).
class CpSeatEffectLayer extends StatefulWidget {
  const CpSeatEffectLayer({
    super.key,
    required this.pairs,
    required this.seatKeys,
    required this.seatSize,
  });

  final List<CpEffectPair> pairs;
  final Map<int, GlobalKey> seatKeys;
  final double seatSize;

  @override
  State<CpSeatEffectLayer> createState() => _CpSeatEffectLayerState();
}

class _CpSeatEffectLayerState extends State<CpSeatEffectLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  /// Seat centres in this layer's coordinates, measured after layout.
  final Map<int, Offset> _centres = {};

  /// When each pair first appeared, for effects with a finite duration.
  final Map<String, DateTime> _since = {};

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant CpSeatEffectLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final live = widget.pairs.map((p) => p.link.id).toSet();
    _since.removeWhere((k, _) => !live.contains(k));
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final me = context.findRenderObject();
    if (me is! RenderBox || !me.hasSize) return;
    final next = <int, Offset>{};
    for (final p in widget.pairs) {
      for (final seat in [p.seatA, p.seatB]) {
        final box = widget.seatKeys[seat]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final topLeft = box.localToGlobal(Offset.zero, ancestor: me);
        // The avatar sits at the top of the card; its label is underneath.
        next[seat] = topLeft + Offset(box.size.width / 2, widget.seatSize / 2);
      }
    }
    bool changed = next.length != _centres.length;
    if (!changed) {
      for (final e in next.entries) {
        if ((_centres[e.key] ?? Offset.infinite) != e.value) {
          changed = true;
          break;
        }
      }
    }
    if (changed) setState(() => _centres..clear()..addAll(next));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final visible = <_HeartSpec>[];
    for (final p in widget.pairs) {
      final a = _centres[p.seatA];
      final b = _centres[p.seatB];
      if (a == null || b == null) continue;
      final since = _since.putIfAbsent(p.link.id, () => now);
      final dur = p.link.durationSec;
      if (dur > 0 && now.difference(since).inSeconds >= dur) continue;
      visible.add(_HeartSpec(a: a, b: b, speed: p.link.animationSpeed.clamp(0.25, 4.0), level: p.link.level));
    }
    if (visible.isEmpty) {
      // Re-check once the seats have laid out.
      if (widget.pairs.isNotEmpty) _scheduleMeasure();
      return const SizedBox.expand();
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _HeartPainter(specs: visible, t: _ctrl.value, seatSize: widget.seatSize),
        ),
      ),
    );
  }
}

class _HeartSpec {
  const _HeartSpec({required this.a, required this.b, required this.speed, required this.level});
  final Offset a;
  final Offset b;
  final double speed;
  final int level;
}

class _HeartPainter extends CustomPainter {
  _HeartPainter({required this.specs, required this.t, required this.seatSize});
  final List<_HeartSpec> specs;
  final double t; // 0..1, repeating
  final double seatSize;

  static const _gold = Color(0xFFFFD36E);
  static const _pink = Color(0xFFFF4F9A);
  static const _violet = Color(0xFFB36BFF);

  /// The classic parametric heart, normalised to roughly [-1,1] × [-1,1].
  static Offset _heart(double u) {
    final s = math.sin(u);
    final x = 16 * s * s * s;
    final y = 13 * math.cos(u) - 5 * math.cos(2 * u) - 2 * math.cos(3 * u) - math.cos(4 * u);
    return Offset(x / 17, -y / 17);
  }

  Path _heartPath(Offset c, double w, double h, double squashX) {
    final path = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final p = _heart(i / steps * 2 * math.pi);
      final pt = Offset(c.dx + p.dx * w / 2 * squashX, c.dy + p.dy * h / 2);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in specs) {
      _paintOne(canvas, s);
    }
  }

  void _paintOne(Canvas canvas, _HeartSpec s) {
    final phase = (t * s.speed) % 1.0;
    final tau = 2 * math.pi;
    final mid = Offset((s.a.dx + s.b.dx) / 2, (s.a.dy + s.b.dy) / 2);
    final span = (s.a - s.b).distance;
    // Big enough that each avatar sits inside one lobe of the heart.
    final w = span + seatSize * 1.75;
    final h = w * 0.9;
    // The lobes are in the upper half of the curve, so drop the centre a little.
    final centre = mid + Offset(0, h * 0.12);

    // 3D: a slow turn about the vertical axis (x squash) with a pulse.
    final turn = math.sin(phase * tau);
    final squash = 0.86 + 0.14 * math.cos(phase * tau);
    final pulse = 1 + 0.035 * math.sin(phase * tau * 2);
    final ww = w * pulse;
    final hh = h * pulse;

    final glowAlpha = (0.55 + 0.25 * math.sin(phase * tau * 2)).clamp(0.0, 1.0);

    // Back face: the far side of the turning heart, dimmer and offset, is what
    // sells the depth.
    final back = _heartPath(centre + Offset(turn * seatSize * 0.18, 2), ww * 0.97, hh * 0.97, squash);
    canvas.drawPath(
      back,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _violet.withOpacity(0.28),
    );

    final front = _heartPath(centre - Offset(turn * seatSize * 0.1, 0), ww, hh, squash);
    final bounds = front.getBounds();
    final gradient = SweepGradient(
      center: Alignment.center,
      transform: GradientRotation(phase * tau),
      colors: const [_gold, _pink, _violet, _gold],
    ).createShader(bounds);

    // Glow.
    canvas.drawPath(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..shader = gradient
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
        ..color = Colors.white.withOpacity(glowAlpha),
    );
    // Soft fill so the heart reads as a shape, never opaque enough to hide anything.
    canvas.drawPath(
      front,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = RadialGradient(
          colors: [_pink.withOpacity(0.10), _pink.withOpacity(0.0)],
        ).createShader(bounds),
    );
    // Crisp rim.
    canvas.drawPath(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = gradient,
    );

    // Light pulses: heart outlines expanding outwards and fading.
    for (var k = 0; k < 2; k++) {
      final p = ((phase * 2) + k * 0.5) % 1.0;
      final ring = _heartPath(centre, ww * (1 + p * 0.28), hh * (1 + p * 0.28), squash);
      canvas.drawPath(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * (1 - p)
          ..color = _gold.withOpacity(0.45 * (1 - p)),
      );
    }

    // Particles orbiting the rim.
    final metrics = front.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final m = metrics.first;
      const count = 22;
      for (var i = 0; i < count; i++) {
        final f = ((i / count) + phase * 0.6) % 1.0;
        final tan = m.getTangentForOffset(f * m.length);
        if (tan == null) continue;
        final twinkle = 0.5 + 0.5 * math.sin((phase * 6 + i * 0.7) * tau);
        final r = 1.2 + 1.8 * twinkle;
        final outward = Offset(-tan.vector.dy, tan.vector.dx) * (3 + 4 * twinkle);
        canvas.drawCircle(
          tan.position + outward,
          r,
          Paint()
            ..color = (i.isEven ? _gold : Colors.white).withOpacity(0.35 + 0.55 * twinkle)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
        );
      }
    }

    // Crystal accents at the top cusp and the tip.
    _crystal(canvas, Offset(centre.dx, bounds.top + hh * 0.2), 5.5 + 1.5 * math.sin(phase * tau * 2), phase);
    _crystal(canvas, Offset(centre.dx, bounds.bottom), 7 + 2 * math.sin(phase * tau * 2 + 1), phase);
  }

  void _crystal(Canvas canvas, Offset c, double r, double phase) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(math.pi / 4 + math.sin(phase * 2 * math.pi) * 0.25);
    final rect = Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFFFF4C2), _gold, Color(0xFFFF9EC7)]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.9),
    );
    canvas.restore();
    canvas.drawCircle(
      c,
      r * 2.2,
      Paint()
        ..color = _gold.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _HeartPainter old) => true;
}

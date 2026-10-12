import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'yummy_symbols.dart';

/// Shared visual effects for YUMMY: the fragment shaders (with Dart
/// fallbacks), a sleeping ambient clock, particles, the drifting backdrop and
/// the animated logo. Everything here is decoration and must degrade to a
/// still picture when motion is reduced or the phone is a lite one.

class YummyShaders {
  YummyShaders._();
  static ui.FragmentProgram? shine;
  static ui.FragmentProgram? symbol;
  static Future<void>? _loading;

  /// Loads both programs once. A device that cannot compile them keeps null
  /// and every caller falls back to gradients.
  static Future<void> load() => _loading ??= () async {
        try {
          shine =
              await ui.FragmentProgram.fromAsset('shaders/yummy_shine.frag');
        } catch (e) {
          debugPrint('[YUMMY] shine shader unavailable: $e');
        }
        try {
          symbol =
              await ui.FragmentProgram.fromAsset('shaders/yummy_symbol.frag');
        } catch (e) {
          debugPrint('[YUMMY] symbol shader unavailable: $e');
        }
      }();
}

/// Seconds since the screen opened, ticking only while "awake". Ambient loops
/// (backdrop drift, logo bob, idle glints, bulbs) read it; it falls asleep
/// after [idleAfter] without a [wake], so an idle screen stops drawing frames
/// and saves the battery (and lets widget tests settle).
class YummyClock extends ChangeNotifier implements ValueListenable<double> {
  YummyClock(
    TickerProvider vsync, {
    this.idleAfter = const Duration(seconds: 25),
  }) {
    _ticker = vsync.createTicker(_onTick);
  }
  final Duration idleAfter;
  late final Ticker _ticker;
  double _base = 0, _value = 0;
  Duration _elapsed = Duration.zero, _lastWake = Duration.zero;
  bool enabled = true;
  bool _busy = false;

  @override
  double get value => _value;
  bool get running => _ticker.isActive;

  /// Keeps the clock running while true (a spin, a celebration).
  set busy(bool value) {
    _busy = value;
    if (value) wake();
  }

  void wake() {
    if (!enabled) return;
    if (_ticker.isActive) {
      _lastWake = _elapsed;
      return;
    }
    _base = _value;
    _elapsed = _lastWake = Duration.zero;
    _ticker.start();
  }

  void sleep() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    _value = _base + elapsed.inMicroseconds / 1e6;
    if (_busy) _lastWake = elapsed;
    if (!enabled || (!_busy && elapsed - _lastWake > idleAfter)) {
      _ticker.stop();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

enum YummyParticleKind { droplet, star, coin, spark }

class YummyParticle {
  double x, y, vx, vy, size, rot, spin, age = 0, life, gravity, drag;
  final Color color;
  final YummyParticleKind kind;
  YummyParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.color,
    required this.kind,
    this.rot = 0,
    this.spin = 0,
    this.gravity = 900,
    this.drag = .6,
  });
}

/// A small, capped particle system painted with plain canvas calls.
class YummyParticles {
  YummyParticles({this.cap = 160});
  int cap;
  final List<YummyParticle> items = [];
  final math.Random _random = math.Random();
  bool get isEmpty => items.isEmpty;

  double _r(double a, double b) => a + _random.nextDouble() * (b - a);

  void _add(YummyParticle p) {
    if (items.length >= cap) items.removeAt(0);
    items.add(p);
  }

  /// Juice droplets flying out of a popped fruit.
  void splash(Offset at, Color color, double scale, {int count = 12}) {
    for (var i = 0; i < count; i++) {
      final a = _r(0, math.pi * 2);
      final speed = _r(120, 420) * scale;
      _add(
        YummyParticle(
          x: at.dx,
          y: at.dy,
          vx: math.cos(a) * speed,
          vy: math.sin(a) * speed - 160 * scale,
          size: _r(3, 7.5) * scale,
          life: _r(.45, .8),
          color: i.isEven ? color : Color.lerp(color, Colors.white, .45)!,
          kind: YummyParticleKind.droplet,
          gravity: 1100 * scale,
        ),
      );
    }
    for (var i = 0; i < 4; i++) {
      _add(
        YummyParticle(
          x: at.dx + _r(-12, 12) * scale,
          y: at.dy + _r(-12, 12) * scale,
          vx: _r(-40, 40),
          vy: _r(-90, -20),
          size: _r(6, 11) * scale,
          life: _r(.35, .6),
          color: Colors.white,
          kind: YummyParticleKind.star,
          gravity: 0,
          spin: _r(-4, 4),
        ),
      );
    }
  }

  /// A few twinkles around a winning or wild cell.
  void twinkle(Rect cell, {int count = 2, Color color = Colors.white}) {
    for (var i = 0; i < count; i++) {
      _add(
        YummyParticle(
          x: _r(cell.left, cell.right),
          y: _r(cell.top, cell.bottom),
          vx: _r(-15, 15),
          vy: _r(-50, -10),
          size: _r(4, 9) * cell.width / 70,
          life: _r(.4, .8),
          color: color,
          kind: YummyParticleKind.star,
          gravity: 0,
          spin: _r(-3, 3),
        ),
      );
    }
  }

  /// A trail of sparks along a reel as a WILD expands over it.
  void trail(Offset at, double scale) {
    for (var i = 0; i < 3; i++) {
      _add(
        YummyParticle(
          x: at.dx + _r(-20, 20) * scale,
          y: at.dy,
          vx: _r(-60, 60) * scale,
          vy: _r(-60, 60) * scale,
          size: _r(2, 4) * scale,
          life: _r(.3, .6),
          color: i == 0 ? Colors.white : yummyGold,
          kind: YummyParticleKind.spark,
          gravity: 0,
          drag: 2,
        ),
      );
    }
  }

  /// Coins thrown up from [at] (a win) or rained from the top of [area].
  void coins(Rect area, {Offset? from, int count = 14, double scale = 1}) {
    for (var i = 0; i < count; i++) {
      final burst = from != null;
      _add(
        YummyParticle(
          x: burst ? from.dx : _r(area.left, area.right),
          y: burst ? from.dy : area.top - _r(10, 120),
          vx: burst ? _r(-260, 260) * scale : _r(-30, 30),
          vy: burst ? _r(-720, -380) * scale : _r(80, 260),
          size: _r(9, 15) * scale,
          life: burst ? _r(.9, 1.4) : _r(1.6, 2.6),
          color: yummyGold,
          kind: YummyParticleKind.coin,
          rot: _r(0, math.pi),
          spin: _r(5, 11),
          gravity: burst ? 1300 * scale : 380,
          drag: .2,
        ),
      );
    }
  }

  void step(double dt) {
    if (dt <= 0) return;
    for (final p in items) {
      p.age += dt;
      p.vy += p.gravity * dt;
      final damp = math.max(0.0, 1 - p.drag * dt);
      p.vx *= damp;
      p.vy *= damp;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.spin * dt;
    }
    items.removeWhere((p) => p.age >= p.life);
  }

  static final Paint _fill = Paint();
  static final Paint _glow = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  void paint(Canvas canvas) {
    for (final p in items) {
      final fade = (1 - p.age / p.life).clamp(0.0, 1.0);
      switch (p.kind) {
        case YummyParticleKind.droplet:
          final speed = math.sqrt(p.vx * p.vx + p.vy * p.vy);
          final stretch = 1 + math.min(speed / 600, 1.2);
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(math.atan2(p.vy, p.vx));
          _fill.color = p.color.withValues(alpha: fade);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * stretch,
              height: p.size,
            ),
            _fill,
          );
          _fill.color = Colors.white.withValues(alpha: fade * .7);
          canvas.drawCircle(
            Offset(p.size * .15, -p.size * .2),
            p.size * .18,
            _fill,
          );
          canvas.restore();
        case YummyParticleKind.star:
        case YummyParticleKind.spark:
          final pulse = math.sin(math.min(1.0, p.age / p.life) * math.pi);
          final r = p.size * (p.kind == YummyParticleKind.star ? pulse : 1);
          if (r <= .3) break;
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rot);
          _glow.color = p.color.withValues(alpha: .55 * fade);
          canvas.drawCircle(Offset.zero, r * .9, _glow);
          _fill.color = p.color.withValues(alpha: fade);
          canvas.drawPath(_star(r), _fill);
          canvas.restore();
        case YummyParticleKind.coin:
          final face = math.cos(p.rot);
          final w = p.size * math.max(.12, face.abs());
          final rect = Rect.fromCenter(
            center: Offset(p.x, p.y),
            width: w * 2,
            height: p.size * 2,
          );
          _fill.color = const Color(0xFFB86E00).withValues(alpha: fade);
          canvas.drawOval(rect.shift(const Offset(1.2, 0)), _fill);
          _fill.color = (face > 0 ? yummyGold : const Color(0xFFFFB300))
              .withValues(alpha: fade);
          canvas.drawOval(rect, _fill);
          if (w > p.size * .35) {
            _fill.color = const Color(0xFFFFF4B8).withValues(alpha: fade);
            canvas.drawOval(rect.deflate(p.size * .32), _fill);
            _fill.color = const Color(0xFFE09A00).withValues(alpha: fade);
            canvas.drawOval(
              Rect.fromCenter(
                center: rect.center,
                width: rect.width * .28,
                height: rect.height * .42,
              ),
              _fill,
            );
          }
      }
    }
  }

  static Path _star(double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final d = i.isEven ? r : r * .28;
      final point = Offset(math.cos(a) * d, math.sin(a) * d);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }
}

/// Paints a [YummyParticles] system that something else steps.
class YummyParticlesPainter extends CustomPainter {
  final YummyParticles particles;
  YummyParticlesPainter(this.particles, Listenable repaint)
      : super(repaint: repaint);
  @override
  void paint(Canvas canvas, Size size) => particles.paint(canvas);
  @override
  bool shouldRepaint(YummyParticlesPainter old) => false;
}

/// The glint used on the frame and logo: the fragment shader when it loaded,
/// otherwise a moving linear gradient. [progress] outside 0..1 draws nothing.
Shader yummyShineShader(Rect bounds, double progress, {double intensity = .9}) {
  final program = YummyShaders.shine;
  if (program != null) {
    return program.fragmentShader()
      ..setFloat(0, bounds.width)
      ..setFloat(1, bounds.height)
      ..setFloat(2, progress)
      ..setFloat(3, .18)
      ..setFloat(4, intensity);
  }
  final c = -0.3 + progress * 1.6;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withValues(alpha: 0),
      Colors.white.withValues(alpha: .75 * intensity),
      Colors.white.withValues(alpha: 0),
    ],
    stops: [
      (c - .12).clamp(0.0, 1.0),
      c.clamp(0.0, 1.0),
      (c + .12).clamp(0.0, 1.0),
    ],
  ).createShader(bounds);
}

/// Sweeps a glint over [child] every [period] seconds of the [clock].
class YummyShine extends StatelessWidget {
  final YummyClock? clock;
  final Widget child;
  final double period, offset, intensity;
  const YummyShine({
    super.key,
    required this.clock,
    required this.child,
    this.period = 4.5,
    this.offset = 0,
    this.intensity = .9,
  });

  @override
  Widget build(BuildContext context) {
    final clock = this.clock;
    if (clock == null) return child;
    return AnimatedBuilder(
      animation: clock,
      child: child,
      builder: (context, child) {
        // The sweep takes 0.9 s of each period; the rest is rest.
        final phase = ((clock.value + offset) % period) / .9;
        if (!clock.running || phase > 1) return child!;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) =>
              yummyShineShader(bounds, phase, intensity: intensity),
          child: child,
        );
      },
    );
  }
}

/// Background: the art drifts slowly behind two layers of floating candy
/// bokeh that move at different speeds (parallax). Still when [clock] is null.
class YummyBackdrop extends StatelessWidget {
  final YummyClock? clock;
  final bool freeSpins;
  const YummyBackdrop({super.key, required this.clock, this.freeSpins = false});

  @override
  Widget build(BuildContext context) {
    final art = Image.asset(
      '${yummyArt}background.png',
      fit: BoxFit.cover,
      cacheWidth: 720,
      errorBuilder: (_, __, ___) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [yummySky, yummyDeep],
          ),
        ),
      ),
    );
    final tint = AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      color: freeSpins ? const Color(0x667A1FA2) : const Color(0x00000000),
    );
    final clock = this.clock;
    if (clock == null) {
      return Stack(fit: StackFit.expand, children: [art, tint]);
    }
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final t = clock.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(math.sin(t / 9) * 14, math.cos(t / 11) * 10),
              child: Transform.scale(scale: 1.08, child: art),
            ),
            tint,
            CustomPaint(painter: _BokehPainter(t, freeSpins)),
          ],
        );
      },
    );
  }
}

class _BokehPainter extends CustomPainter {
  final double t;
  final bool freeSpins;
  _BokehPainter(this.t, this.freeSpins);
  static const _colors = [
    Color(0xFFFFFFFF),
    Color(0xFFFFE27A),
    Color(0xFFFF8FB8),
    Color(0xFF8FE3FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    // Layer 0 is far (small, slow, faint), layer 1 near (big, faster).
    for (var layer = 0; layer < 2; layer++) {
      final count = layer == 0 ? 14 : 7;
      final speed = layer == 0 ? 9.0 : 22.0;
      for (var i = 0; i < count; i++) {
        final seed = i * 7.31 + layer * 3.7;
        final x = (math.sin(seed) * .5 + .5) * size.width +
            math.sin(t * .3 + seed) * 18 * (layer + 1);
        final span = size.height + 80;
        final y = size.height + 40 - ((t * speed + seed * 97) % span);
        final r = (layer == 0 ? 3.0 : 8.0) + (seed * 13 % 5);
        final color = freeSpins
            ? const Color(0xFFFFB0F0)
            : _colors[(i + layer) % _colors.length];
        paint
          ..color = color.withValues(alpha: layer == 0 ? .22 : .16)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, layer == 0 ? 1.5 : 4);
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BokehPainter old) =>
      old.t != t || old.freeSpins != freeSpins;
}

/// The YUMMY logo, bobbing gently with a glint and a squash on each bounce.
class YummyLogo extends StatelessWidget {
  final YummyClock? clock;
  final double height;
  const YummyLogo({super.key, required this.clock, this.height = 104});

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      '${yummyArt}logo.png',
      height: height,
      width: height * 2.5,
      cacheWidth: 512,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'YUMMY',
          style: TextStyle(
            fontSize: height * .5,
            fontWeight: FontWeight.w900,
            color: yummyGold,
            shadows: const [
              Shadow(color: yummyDeep, offset: Offset(3, 4), blurRadius: 2),
            ],
          ),
        ),
      ),
    );
    final clock = this.clock;
    if (clock == null) return logo;
    return AnimatedBuilder(
      animation: clock,
      child: YummyShine(clock: clock, period: 5, offset: 1.2, child: logo),
      builder: (context, child) {
        final t = clock.value;
        final bob = math.sin(t * 2.1);
        // Squash a little at the bottom of the bob, stretch at the top.
        final squash = 1 + bob * .025;
        return Transform.translate(
          offset: Offset(0, bob * 4),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(2 - squash, squash, 1)
              ..rotateZ(math.sin(t * .9) * .015),
            child: child,
          ),
        );
      },
    );
  }
}

/// Coins raining down (and a first burst from the middle) for [seconds].
/// Owns its own ticker; draws nothing when [reduced].
class YummyCoinRain extends StatefulWidget {
  final double seconds;
  final int perSecond;
  final bool reduced, lite;
  const YummyCoinRain({
    super.key,
    this.seconds = 2.5,
    this.perSecond = 26,
    this.reduced = false,
    this.lite = false,
  });

  @override
  State<YummyCoinRain> createState() => _YummyCoinRainState();
}

class _YummyCoinRainState extends State<YummyCoinRain>
    with SingleTickerProviderStateMixin {
  late final YummyParticles _particles =
      YummyParticles(cap: widget.lite ? 40 : 140);
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _age = 0, _owed = 0;
  Size _size = Size.zero;
  bool _burst = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (!widget.reduced) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = math.min(.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    _age += dt;
    if (_size != Size.zero) {
      final scale = (_size.width / 400).clamp(.7, 1.6);
      if (!_burst) {
        _burst = true;
        _particles.coins(
          Offset.zero & _size,
          from: Offset(_size.width / 2, _size.height * .55),
          count: widget.lite ? 8 : 22,
          scale: scale,
        );
      }
      if (_age < widget.seconds) {
        _owed += dt * (widget.lite ? widget.perSecond / 3 : widget.perSecond);
        final count = _owed.floor();
        _owed -= count;
        if (count > 0) {
          _particles.coins(Offset.zero & _size, count: count, scale: scale);
        }
      }
    }
    _particles.step(dt);
    _repaint.value++;
    if (_age > widget.seconds && _particles.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            return CustomPaint(
              size: Size.infinite,
              painter: YummyParticlesPainter(_particles, _repaint),
            );
          },
        ),
      );
}

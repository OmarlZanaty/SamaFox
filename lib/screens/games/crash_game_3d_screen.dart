import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum CrashState { waiting, running, crashed }

class Vector3 {
  final double x;
  final double y;
  final double z;

  const Vector3(this.x, this.y, this.z);

  Vector3 operator +(Vector3 other) =>
      Vector3(x + other.x, y + other.y, z + other.z);
  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);
}

class CrashGame3DScreen extends StatefulWidget {
  const CrashGame3DScreen({super.key});

  @override
  State<CrashGame3DScreen> createState() => _CrashGame3DScreenState();
}

class _CrashGame3DScreenState extends State<CrashGame3DScreen>
    with TickerProviderStateMixin {
  CrashState _state = CrashState.waiting;
  double _multiplier = 1.0;
  double _crashPoint = 2.0;
  int _balance = 1000;
  int _betAmount = 50;
  bool _hasBet = false;
  bool _cashedOut = false;
  int _countdown = 3;
  List<double> _history = [];
  List<Vector3> _graphPoints = [];
  late Ticker _ticker;
  DateTime? _roundStart;
  bool _autoCashout = false;
  double _autoCashoutAt = 2.0;
  late AnimationController _shakeController;
  late AnimationController _explosionController;
  late AnimationController _cameraController;
  bool _flashRed = false;

  final Random _rng = Random();
  final TextEditingController _betController = TextEditingController(text: '50');
  final TextEditingController _autoController =
      TextEditingController(text: '2.0');

  final List<_Star> _stars = [];
  Timer? _countdownTimer;
  Timer? _nextRoundTimer;
  Timer? _flashTimer;

  Vector3 _cameraPos = const Vector3(0, 1.1, -7.5);

  @override
  void initState() {
    super.initState();
    _generateStars();
    _ticker = createTicker(_onTick);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _explosionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _ticker.start();
    _startWaitingCountdown();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _countdownTimer?.cancel();
    _nextRoundTimer?.cancel();
    _flashTimer?.cancel();
    _betController.dispose();
    _autoController.dispose();
    _shakeController.dispose();
    _explosionController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  void _generateStars() {
    _stars.clear();
    for (int i = 0; i < 90; i++) {
      _stars.add(
        _Star(
          x: _rng.nextDouble() * 2 - 1,
          y: _rng.nextDouble() * 0.9,
          z: 2 + _rng.nextDouble() * 30,
          size: 0.7 + _rng.nextDouble() * 1.9,
          alpha: 0.2 + _rng.nextDouble() * 0.7,
        ),
      );
    }
  }

  void _startWaitingCountdown() {
    _countdownTimer?.cancel();
    _state = CrashState.waiting;
    _countdown = 3;
    _multiplier = 1.0;
    _graphPoints = [];
    _cashedOut = false;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _state != CrashState.waiting) {
        timer.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() {
          _countdown -= 1;
        });
      } else {
        timer.cancel();
        _startRound();
      }
    });

    setState(() {});
  }

  double _generateCrashPoint() {
    if (_rng.nextDouble() < 0.6) {
      return 1.2 + _rng.nextDouble() * 1.3;
    } else if (_rng.nextDouble() < 0.75) {
      return 2.5 + _rng.nextDouble() * 2.5;
    } else {
      return 5.0 + _rng.nextDouble() * 5.0;
    }
  }

  void _startRound() {
    _nextRoundTimer?.cancel();
    _roundStart = DateTime.now();
    _state = CrashState.running;
    _multiplier = 1.0;
    _crashPoint = _generateCrashPoint();
    _graphPoints.clear();
    _cashedOut = false;

    if (_hasBet) {
      _balance -= _betAmount;
      if (_balance < 0) {
        _balance = 0;
      }
    }

    setState(() {});
  }

  void _onTick(Duration _) {
    if (!mounted) return;

    if (_state == CrashState.running && _roundStart != null) {
      final int elapsed = DateTime.now().difference(_roundStart!).inMilliseconds;
      final double timeT = elapsed / 1000.0;
      _multiplier = 1.0 + timeT * 0.5 + pow(elapsed / 2000.0, 1.8);

      final double x = min(1.0, elapsed / 8500.0);
      final double multiplierRatio = ((_multiplier - 1.0) / 9.0).clamp(0.0, 1.0);
      final double z = 14.0 - multiplierRatio * 11.0;
      final double y = sin(timeT * 2.1) * 0.08;
      _graphPoints.add(Vector3((x - 0.5) * 8.0, y, z));
      if (_graphPoints.length > 260) {
        _graphPoints.removeAt(0);
      }

      if (_autoCashout && _hasBet && !_cashedOut && _multiplier >= _autoCashoutAt) {
        _cashOut();
      }

      if (_multiplier >= _crashPoint) {
        _handleCrash();
      }
    }

    if (mounted) setState(() {});
  }

  void _handleCrash() {
    _state = CrashState.crashed;
    _history = [
      _crashPoint,
      ..._history,
    ].take(10).toList();

    _shakeController.forward(from: 0);
    _explosionController.forward(from: 0);

    _flashRed = true;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() {
          _flashRed = false;
        });
      }
    });

    _nextRoundTimer?.cancel();
    _nextRoundTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _startWaitingCountdown();
      }
    });
  }

  void _placeBet() {
    if (_state != CrashState.waiting) return;
    final int parsed = int.tryParse(_betController.text.trim()) ?? _betAmount;
    if (parsed <= 0 || parsed > _balance) return;

    setState(() {
      _betAmount = parsed;
      _hasBet = true;
      _cashedOut = false;
    });
  }

  void _cashOut() {
    if (_state != CrashState.running || !_hasBet || _cashedOut) return;
    final int payout = (_betAmount * _multiplier).round();
    setState(() {
      _balance += payout;
      _cashedOut = true;
      _hasBet = false;
    });
  }

  Color _multiplierColor() {
    final t = ((_multiplier - 1.0) / 6.0).clamp(0.0, 1.0);
    return Color.lerp(Colors.greenAccent, Colors.redAccent, t)!;
  }

  @override
  Widget build(BuildContext context) {
    final bool canPlaceBet = _state == CrashState.waiting;
    final bool canCashOut = _state == CrashState.running && _hasBet && !_cashedOut;

    final double shake = sin(_shakeController.value * pi * 8) *
        (1.0 - _shakeController.value) *
        8;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        title: const Text('💥 Crash 3D'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Balance: \\$$_balance',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHistoryBar(),
            const SizedBox(height: 8),
            Transform.translate(
              offset: Offset(shake * 0.35, shake * 0.15),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                height: 220,
                decoration: BoxDecoration(
                  color: _flashRed
                      ? const Color(0x55FF1A1A)
                      : const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _cameraController,
                          _explosionController,
                          _shakeController,
                        ]),
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _Crash3DPainter(
                              graphPoints: _graphPoints,
                              multiplier: _multiplier,
                              state: _state,
                              cameraPulse: _cameraController.value,
                              explosionProgress: _explosionController.value,
                              stars: _stars,
                            ),
                          );
                        },
                      ),
                      Center(child: _buildFloatingMultiplier()),
                      if (_state == CrashState.waiting)
                        Positioned(
                          top: 14,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Text(
                              'انتظار… $_countdown',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (_state == CrashState.crashed)
                        Positioned.fill(
                          child: Center(
                            child: Transform.scale(
                              scale: 1 + _explosionController.value * 0.35,
                              child: const Text(
                                '💥 CRASH!',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x99FF0000),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildBetControls(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _GradientActionButton(
                      onTap: canPlaceBet ? _placeBet : null,
                      text: 'رهان',
                      gradient: const LinearGradient(
                        colors: [Color(0xFF059669), Color(0xFF10B981)],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GradientActionButton(
                      onTap: canCashOut ? _cashOut : null,
                      text: 'اسحب الآن',
                      gradient: const LinearGradient(
                        colors: [Color(0xFFB45309), Color(0xFFF59E0B)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingMultiplier() {
    final double shake = sin(_shakeController.value * pi * 14) *
        (1.0 - _shakeController.value) *
        10;
    final Matrix4 perspective = Matrix4.identity()
      ..setEntry(3, 2, 0.0014)
      ..rotateX(-0.12)
      ..rotateY(0.1 * sin(_cameraController.value * pi * 2));

    return Transform(
      alignment: Alignment.center,
      transform: perspective,
      child: Transform.translate(
        offset: Offset(shake, 0),
        child: Transform.scale(
          scale: 1.0 + ((_multiplier - 1.0) / 8).clamp(0.0, 0.4),
          child: Text(
            '${_multiplier.toStringAsFixed(2)}×',
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w900,
              color: _state == CrashState.crashed
                  ? Colors.redAccent
                  : _multiplierColor(),
              shadows: [
                Shadow(
                  color: _multiplierColor().withOpacity(0.55),
                  blurRadius: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryBar() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemBuilder: (_, index) {
          final value = _history[index];
          final bool high = value >= 2.0;
          return Chip(
            label: Text('${value.toStringAsFixed(2)}×'),
            backgroundColor: high
                ? const Color(0xFF0D3A2F)
                : const Color(0xFF4B1D20),
            labelStyle: TextStyle(
              color: high ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.w700,
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemCount: _history.length,
      ),
    );
  }

  Widget _buildBetControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _betController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Bet Amount',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF121826),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      _betAmount = parsed;
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Row(
                children: [
                  Switch(
                    value: _autoCashout,
                    onChanged: (v) {
                      setState(() {
                        _autoCashout = v;
                      });
                    },
                  ),
                  const Text(
                    'Auto',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _autoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Auto Cashout At (x)',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF121826),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed != null && parsed >= 1.01) {
                _autoCashoutAt = parsed;
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Crash3DPainter extends CustomPainter {
  _Crash3DPainter({
    required this.graphPoints,
    required this.multiplier,
    required this.state,
    required this.cameraPulse,
    required this.explosionProgress,
    required this.stars,
  });

  final List<Vector3> graphPoints;
  final double multiplier;
  final CrashState state;
  final double cameraPulse;
  final double explosionProgress;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF0D1117),
          const Color(0xFF0A0A0F),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final Vector3 cam = Vector3(
      sin(cameraPulse * pi * 2) * 0.28,
      1.0 + sin(cameraPulse * pi * 2) * 0.04,
      -7.7 + cos(cameraPulse * pi * 2) * 0.16,
    );

    _drawStars(canvas, size, cam);
    _drawGrid(canvas, size, cam);
    _drawTrack(canvas, size, cam);
    if (state == CrashState.crashed) {
      _drawExplosion(canvas, size, cam);
    }
  }

  void _drawStars(Canvas canvas, Size size, Vector3 cam) {
    final Paint p = Paint();
    for (final s in stars) {
      final projected = _project(Vector3(s.x * 11, s.y * 5 - 2.8, s.z), size, cam);
      if (projected == null) continue;
      final depth = ((30 - s.z) / 30).clamp(0.1, 1.0);
      p.color = Colors.white.withOpacity((s.alpha * depth).clamp(0.08, 0.8));
      canvas.drawCircle(projected, s.size * depth * 1.2, p);
    }
  }

  void _drawGrid(Canvas canvas, Size size, Vector3 cam) {
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = -8; i <= 8; i++) {
      final p1 = _project(Vector3(i.toDouble(), 0.8, 20), size, cam);
      final p2 = _project(Vector3(i.toDouble(), 0.8, 3), size, cam);
      if (p1 == null || p2 == null) continue;
      final opacity = (1 - (i.abs() / 10)).clamp(0.08, 0.35);
      grid.color = const Color(0xFF1A1F2E).withOpacity(opacity);
      canvas.drawLine(p1, p2, grid);
    }

    for (int z = 4; z <= 20; z += 2) {
      final left = _project(const Vector3(-8, 0.8, 0), size, cam + Vector3(0, 0, z.toDouble()));
      final right = _project(const Vector3(8, 0.8, 0), size, cam + Vector3(0, 0, z.toDouble()));
      if (left == null || right == null) continue;
      final opacity = ((22 - z) / 24).clamp(0.06, 0.3);
      grid.color = const Color(0xFF1A1F2E).withOpacity(opacity);
      canvas.drawLine(left, right, grid);
    }
  }

  void _drawTrack(Canvas canvas, Size size, Vector3 cam) {
    if (graphPoints.length < 2) return;

    final Path path = Path();
    Offset? first;
    for (final point in graphPoints) {
      final projected = _project(point + const Vector3(0, 0.7, 0), size, cam);
      if (projected == null) continue;
      if (first == null) {
        path.moveTo(projected.dx, projected.dy);
        first = projected;
      } else {
        path.lineTo(projected.dx, projected.dy);
      }
    }

    final Rect bounds = Rect.fromLTWH(0, size.height * 0.35, size.width, size.height * 0.6);
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: state == CrashState.crashed
            ? [
                Colors.red.withOpacity(0.6),
                Colors.redAccent,
                Colors.red,
              ]
            : [
                Colors.greenAccent,
                Colors.yellowAccent,
                Colors.redAccent,
              ],
      ).createShader(bounds);

    canvas.drawPath(path, track);
  }

  void _drawExplosion(Canvas canvas, Size size, Vector3 cam) {
    final Offset? center = _project(const Vector3(0, 0.7, 4), size, cam);
    if (center == null) return;

    final double t = Curves.easeOut.transform(explosionProgress);
    final double radius = 12 + t * 70;
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.redAccent.withOpacity((1 - t) * 0.8);
    canvas.drawCircle(center, radius, glow);

    final Paint ray = Paint()
      ..strokeWidth = 2
      ..color = Colors.orangeAccent.withOpacity((1 - t) * 0.7);

    for (int i = 0; i < 18; i++) {
      final double a = (2 * pi / 18) * i;
      final double len = radius + 20 * t;
      final Offset end = Offset(
        center.dx + cos(a) * len,
        center.dy + sin(a) * len,
      );
      canvas.drawLine(center, end, ray);
    }
  }

  Offset? _project(Vector3 point, Size size, Vector3 cam) {
    final Vector3 p = point - cam;
    final double z = p.z <= 0.15 ? 0.15 : p.z;
    final double fov = 280;
    final double sx = size.width / 2 + (p.x / z) * fov;
    final double sy = size.height / 2 + (p.y / z) * fov;
    if (sx.isNaN || sy.isNaN) return null;
    return Offset(sx, sy);
  }

  @override
  bool shouldRepaint(covariant _Crash3DPainter oldDelegate) {
    return true;
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.onTap,
    required this.text,
    required this.gradient,
  });

  final VoidCallback? onTap;
  final String text;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: disabled
              ? const LinearGradient(
                  colors: [Color(0xFF374151), Color(0xFF4B5563)],
                )
              : gradient,
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.z,
    required this.size,
    required this.alpha,
  });

  final double x;
  final double y;
  final double z;
  final double size;
  final double alpha;
}

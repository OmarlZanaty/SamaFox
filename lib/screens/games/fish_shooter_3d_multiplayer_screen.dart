import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class FishShooter3dMultiplayerScreen extends StatefulWidget {
  const FishShooter3dMultiplayerScreen({super.key});

  @override
  State<FishShooter3dMultiplayerScreen> createState() =>
      _FishShooter3dMultiplayerScreenState();
}

class Player {
  final int id;
  double cannonAzimuth;
  double cannonElevation;
  int score;
  int coins;
  Color color;
  List<Bullet> bullets;
  Player({
    required this.id,
    required this.color,
  })  : cannonAzimuth = 0.0,
        cannonElevation = 0.0,
        score = 0,
        coins = 0,
        bullets = [];
}

class Fish {
  Fish({
    required this.x,
    required this.y,
    required this.z,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.radius,
    required this.maxHealth,
    required this.reward,
    required this.color,
    required this.isBoss,
  }) : health = maxHealth;

  double x;
  double y;
  double z;
  double vx;
  double vy;
  double vz;
  double radius;
  int maxHealth;
  int health;
  int reward;
  bool isBoss;
  Color color;
  double flap = 0;
  double life = 0;
}

class Bullet {
  Bullet({
    required this.x,
    required this.y,
    required this.z,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.color,
    required this.damage,
  });

  double x;
  double y;
  double z;
  double vx;
  double vy;
  double vz;
  int damage;
  double life = 0;
  Color color;
  final List<Offset> trail = [];
}

class HitEffect {
  HitEffect({
    required this.x,
    required this.y,
    required this.z,
    required this.color,
    required this.text,
    required this.big,
  });

  double x;
  double y;
  double z;
  Color color;
  String text;
  bool big;
  double t = 0;
}

class CameraState {
  CameraState({
    required this.x,
    required this.y,
    required this.z,
    required this.yaw,
    required this.pitch,
  });

  double x;
  double y;
  double z;
  double yaw;
  double pitch;
}

class _FishShooter3dMultiplayerScreenState
    extends State<FishShooter3dMultiplayerScreen>
    with SingleTickerProviderStateMixin {
  int _timeLeft = 60;
  bool _gameOver = false;
  late Ticker _ticker;
  Timer? _spawnTimer;
  Timer? _gameTimer;

  final List<Fish> _fishes = [];
  final List<HitEffect> _effects = [];
  List<Player> _players = [];

  CameraState _camera = CameraState(
    x: 0.5,
    y: 0.8,
    z: 1.2,
    yaw: 0.0,
    pitch: -0.3,
  );

  final math.Random _rng = math.Random();
  final Map<int, int> _pointerOwner = {};
  final Set<int> _pressedPlayers = {};
  final Map<int, double> _muzzleFlash = {};
  final Map<int, double> _recoil = {};
  final Map<int, double> _scorePulse = {};

  double _controlBarHeight = 92;
  Duration _lastTick = Duration.zero;
  double _clock = 0;
  double _screenShake = 0;
  int _playerCount = 2;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askPlayerCount();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _spawnTimer?.cancel();
    _gameTimer?.cancel();
    super.dispose();
  }

  Future<void> _askPlayerCount() async {
    final int? picked = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.blueGrey.shade900,
          title: const Text('عدد اللاعبين', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              final p = index + 2;
              return ListTile(
                title: Text(
                  '$p لاعبين',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, p),
              );
            }),
          ),
        );
      },
    );
    _startNewRound(picked ?? 2, keepCoins: true);
  }

  void _startNewRound(int players, {bool keepCoins = false}) {
    _playerCount = players.clamp(2, 4);
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple];
    final existingCoins = <int, int>{
      for (final p in _players) p.id: p.coins,
    };
    _players = List.generate(
      _playerCount,
      (i) => Player(id: i + 1, color: colors[i])..coins = keepCoins ? (existingCoins[i + 1] ?? 0) : 0,
    );
    _fishes.clear();
    _effects.clear();
    _pointerOwner.clear();
    _pressedPlayers.clear();
    _muzzleFlash.clear();
    _recoil.clear();
    _scorePulse.clear();

    _timeLeft = 60;
    _clock = 0;
    _gameOver = false;

    _spawnTimer?.cancel();
    _gameTimer?.cancel();

    _spawnTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!_gameOver) _spawnFish();
    });

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_gameOver) return;
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          _endRound();
        }
      });
    });

    for (int i = 0; i < 7; i++) {
      _spawnFish();
    }
    setState(() {});
  }

  void _endRound() {
    _gameOver = true;
    for (final p in _players) {
      p.coins += p.score;
    }
    _spawnTimer?.cancel();
    _gameTimer?.cancel();
    setState(() {});
  }

  void _spawnFish() {
    final boss = _rng.nextDouble() < 0.12;
    final depth = 0.4 + _rng.nextDouble() * 2.6;
    final fromLeft = _rng.nextBool();
    final speed = (boss ? 0.06 : 0.11) + _rng.nextDouble() * (boss ? 0.04 : 0.08);
    final fish = Fish(
      x: fromLeft ? -1.2 : 2.2,
      y: 0.2 + _rng.nextDouble() * 0.7,
      z: depth,
      vx: fromLeft ? speed : -speed,
      vy: (_rng.nextDouble() - 0.5) * 0.04,
      vz: (_rng.nextDouble() - 0.5) * 0.08,
      radius: boss ? 0.14 : 0.09,
      maxHealth: boss ? 6 : (_rng.nextDouble() < 0.2 ? 3 : 2),
      reward: boss ? 30 : (4 + _rng.nextInt(9)),
      color: boss ? Colors.redAccent : Colors.cyanAccent,
      isBoss: boss,
    );
    _fishes.add(fish);
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    _clock += dt;

    if (_gameOver) {
      if (mounted) setState(() {});
      return;
    }

    _screenShake = (_screenShake - dt * 2.2).clamp(0.0, 1.0);
    _camera.y = 0.78 + math.sin(_clock * 0.9) * 0.02;
    _camera.yaw = math.sin(_clock * 0.5) * 0.05;

    for (final player in _players) {
      _muzzleFlash[player.id] = (_muzzleFlash[player.id] ?? 0) - dt * 6;
      _recoil[player.id] = (_recoil[player.id] ?? 0) - dt * 7;
      _scorePulse[player.id] = (_scorePulse[player.id] ?? 0) - dt * 2;

      player.bullets.removeWhere((b) {
        b.life += dt;
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        b.z += b.vz * dt;
        b.trail.add(Offset(b.x, b.y));
        if (b.trail.length > 7) b.trail.removeAt(0);
        return b.life > 2.8 || b.x < -1.5 || b.x > 2.5 || b.y < -0.2 || b.y > 1.8 || b.z < 0.2 || b.z > 3.5;
      });
    }

    for (final f in _fishes) {
      f.life += dt;
      f.flap += dt * (f.isBoss ? 5 : 9);
      f.x += f.vx * dt;
      f.y += (f.vy + math.sin(f.life * 2.7) * 0.02) * dt;
      f.z += (f.vz + math.cos(f.life * 1.8) * 0.03) * dt;
      f.y = f.y.clamp(0.1, 0.95);
      f.z = f.z.clamp(0.35, 3.0);
    }

    for (final player in _players) {
      for (int i = player.bullets.length - 1; i >= 0; i--) {
        final b = player.bullets[i];
        bool removed = false;
        for (int j = _fishes.length - 1; j >= 0; j--) {
          final f = _fishes[j];
          final dx = b.x - f.x;
          final dy = b.y - f.y;
          final dz = b.z - f.z;
          if (dx * dx + dy * dy + dz * dz < f.radius * f.radius * 1.5) {
            f.health -= b.damage;
            _effects.add(HitEffect(
              x: f.x,
              y: f.y,
              z: f.z,
              color: player.color,
              text: '+${f.health <= 0 ? f.reward : 1}',
              big: f.health <= 0,
            ));
            if (f.health <= 0) {
              player.score += f.reward;
              _scorePulse[player.id] = 1.0;
              _screenShake = 0.9;
              _fishes.removeAt(j);
            }
            player.bullets.removeAt(i);
            removed = true;
            break;
          }
        }
        if (removed) continue;
      }
    }

    _fishes.removeWhere((f) => f.x < -1.6 || f.x > 2.6);

    _effects.removeWhere((e) {
      e.t += dt;
      e.y -= dt * 0.08;
      return e.t > 1.0;
    });

    if (mounted) setState(() {});
  }

  void _shootForPlayer(int playerIndex, Offset localPos, Size size) {
    if (_gameOver || playerIndex < 0 || playerIndex >= _players.length) return;
    final p = _players[playerIndex];
    final nx = localPos.dx / size.width;
    final ny = localPos.dy / (size.height - _controlBarHeight);
    final cannonX = (playerIndex + 0.5) / _players.length;
    final dx = nx - cannonX;
    final dy = (0.95 - ny);

    p.cannonAzimuth = (dx * 2.1).clamp(-1.0, 1.0);
    p.cannonElevation = (dy * 1.4).clamp(0.1, 1.2);

    final dirX = math.sin(p.cannonAzimuth) * math.cos(p.cannonElevation);
    final dirY = math.sin(p.cannonElevation);
    final dirZ = math.cos(p.cannonAzimuth) * math.cos(p.cannonElevation);

    p.bullets.add(Bullet(
      x: cannonX,
      y: 0.96,
      z: 0.3,
      vx: dirX * 2.0,
      vy: dirY * 1.8,
      vz: dirZ * 2.6,
      color: p.color,
      damage: 1,
    ));

    _muzzleFlash[p.id] = 1.0;
    _recoil[p.id] = 1.0;
  }

  int _segmentIndexForDx(double dx, double width) {
    final segment = width / _players.length;
    return (dx / segment).floor().clamp(0, _players.length - 1);
  }

  void _onPointerDown(PointerDownEvent e, Size size) {
    final bool inControls = e.localPosition.dy >= size.height - _controlBarHeight;
    final pIndex = _segmentIndexForDx(e.localPosition.dx, size.width);
    _pointerOwner[e.pointer] = pIndex;
    if (inControls) {
      _pressedPlayers.add(pIndex);
      _shootForPlayer(pIndex, Offset(size.width * ((pIndex + 0.5) / _players.length), size.height * 0.45), size);
    } else {
      _shootForPlayer(pIndex, e.localPosition, size);
    }
  }

  void _onPointerMove(PointerMoveEvent e, Size size) {
    final owner = _pointerOwner[e.pointer];
    if (owner == null) return;
    final p = _players[owner];
    final nx = e.localPosition.dx / size.width;
    final ny = e.localPosition.dy / (size.height - _controlBarHeight);
    final cannonX = (owner + 0.5) / _players.length;
    p.cannonAzimuth = ((nx - cannonX) * 2.1).clamp(-1.0, 1.0);
    p.cannonElevation = ((0.95 - ny) * 1.4).clamp(0.1, 1.2);
  }

  void _onPointerUp(PointerEvent e) {
    final owner = _pointerOwner.remove(e.pointer);
    if (owner != null) {
      _pressedPlayers.remove(owner);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐠 ثلاثي الأبعاد متعدد اللاعبين'),
        actions: [
          for (final p in _players)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Icon(Icons.monetization_on, color: p.color, size: 18),
                  Text('${p.coins}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            onPointerDown: (e) => _onPointerDown(e, size),
            onPointerMove: (e) => _onPointerMove(e, size),
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: Stack(
              children: [
                CustomPaint(
                  size: size,
                  painter: _FishGamePainter(
                    time: _clock,
                    fishes: _fishes,
                    effects: _effects,
                    players: _players,
                    camera: _camera,
                    controlBarHeight: _controlBarHeight,
                    muzzleFlash: _muzzleFlash,
                    recoil: _recoil,
                    scorePulse: _scorePulse,
                    screenShake: _screenShake,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text('الوقت: $_timeLeft', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: _controlBarHeight,
                    color: Colors.black.withOpacity(0.32),
                    child: Row(
                      children: List.generate(_players.length, (i) {
                        final p = _players[i];
                        final pressed = _pressedPlayers.contains(i);
                        final scale = pressed ? 1.08 : 1.0;
                        return Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('P${p.id} • ${p.score} • ${p.bullets.length}', style: TextStyle(color: p.color, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: pressed ? p.color.withOpacity(0.8) : p.color,
                                    border: Border.all(color: Colors.white70, width: 2),
                                    boxShadow: [BoxShadow(color: p.color.withOpacity(0.7), blurRadius: 14)],
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text('FIRE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                if (_gameOver) _buildResultsOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsOverlay() {
    final ranked = [..._players]..sort((a, b) => b.score.compareTo(a.score));
    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade900,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('انتهت الجولة', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...ranked.map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 9, backgroundColor: p.color),
                        const SizedBox(width: 8),
                        Text('اللاعب ${p.id}', style: const TextStyle(color: Colors.white)),
                        const Spacer(),
                        Text('+${p.score} | الإجمالي ${p.coins}', style: TextStyle(color: p.color, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => _startNewRound(_playerCount, keepCoins: true),
                child: const Text('العب مجدداً'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FishGamePainter extends CustomPainter {
  _FishGamePainter({
    required this.time,
    required this.fishes,
    required this.effects,
    required this.players,
    required this.camera,
    required this.controlBarHeight,
    required this.muzzleFlash,
    required this.recoil,
    required this.scorePulse,
    required this.screenShake,
  });

  final double time;
  final List<Fish> fishes;
  final List<HitEffect> effects;
  final List<Player> players;
  final CameraState camera;
  final double controlBarHeight;
  final Map<int, double> muzzleFlash;
  final Map<int, double> recoil;
  final Map<int, double> scorePulse;
  final double screenShake;

  @override
  void paint(Canvas canvas, Size size) {
    final gameRect = Rect.fromLTWH(0, 0, size.width, size.height - controlBarHeight);
    _paintBackground(canvas, gameRect);

    final shakeX = math.sin(time * 50) * 7 * screenShake;
    final shakeY = math.cos(time * 41) * 6 * screenShake;
    canvas.save();
    canvas.translate(shakeX, shakeY);

    _paintGrid(canvas, gameRect);
    _paintLightShafts(canvas, gameRect);

    final fishSorted = [...fishes]..sort((a, b) => b.z.compareTo(a.z));
    for (final f in fishSorted) {
      _paintFish(canvas, gameRect, f);
    }

    for (final p in players) {
      for (final b in p.bullets) {
        _paintBullet(canvas, gameRect, b);
      }
    }

    for (final e in effects) {
      _paintEffect(canvas, gameRect, e);
    }

    _paintCannons(canvas, gameRect);
    canvas.restore();

    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withOpacity(0.35)],
      ).createShader(gameRect);
    canvas.drawRect(gameRect, vignette);
  }

  void _paintBackground(Canvas canvas, Rect rect) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.lightBlue.shade200, Colors.blue.shade800, Colors.indigo.shade900],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final bubble = Paint()..color = Colors.white.withOpacity(0.15);
    for (int i = 0; i < 40; i++) {
      final x = (i * 89 % 997) / 997 * rect.width;
      final y = rect.bottom - ((time * 45 + i * 37) % rect.height);
      final r = 1.0 + (i % 4) * 1.2;
      canvas.drawCircle(Offset(x, y), r, bubble);
    }
  }

  void _paintGrid(Canvas canvas, Rect rect) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    for (int i = 0; i <= 12; i++) {
      final y = rect.top + rect.height * (0.4 + i / 20);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), p);
    }
    for (int i = 0; i <= 18; i++) {
      final x = rect.left + rect.width * i / 18;
      canvas.drawLine(Offset(x, rect.top + rect.height * 0.45), Offset(x, rect.bottom), p);
    }
  }

  void _paintLightShafts(Canvas canvas, Rect rect) {
    for (int i = 0; i < 5; i++) {
      final x = rect.width * (i / 4);
      final dx = math.sin(time + i) * 25;
      final path = Path()
        ..moveTo(x + dx, rect.top)
        ..lineTo(x + dx + 40, rect.top)
        ..lineTo(x + dx + 150, rect.bottom)
        ..lineTo(x + dx + 110, rect.bottom)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.06));
    }
  }

  Offset _project(Rect rect, double x, double y, double z) {
    final dz = (z - camera.z + 2.8).clamp(0.35, 6.0);
    final scale = 1.2 / dz;
    final sx = (x - camera.x + camera.yaw) * rect.width * scale + rect.width * 0.5;
    final sy = (y - camera.y + camera.pitch) * rect.height * scale + rect.height * 0.56;
    return Offset(sx, sy);
  }

  void _paintFish(Canvas canvas, Rect rect, Fish f) {
    final c = _project(rect, f.x, f.y, f.z);
    final scale = (1.5 / (f.z + 0.3)).clamp(0.4, 2.0);
    final bodyW = 34 * scale * (f.isBoss ? 1.6 : 1.0);
    final bodyH = 18 * scale * (f.isBoss ? 1.5 : 1.0) * (1 + math.sin(f.flap) * 0.08);

    final bodyRect = Rect.fromCenter(center: c, width: bodyW, height: bodyH);
    final fishPaint = Paint()
      ..shader = LinearGradient(colors: [f.color.withOpacity(0.95), Colors.white.withOpacity(0.5)]).createShader(bodyRect);
    canvas.drawOval(bodyRect, fishPaint);

    final tailPath = Path()
      ..moveTo(c.dx - bodyW / 2, c.dy)
      ..lineTo(c.dx - bodyW / 2 - bodyW * 0.25, c.dy - bodyH * 0.28)
      ..lineTo(c.dx - bodyW / 2 - bodyW * 0.25, c.dy + bodyH * 0.28)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = f.color.withOpacity(0.9));

    if (f.maxHealth > 1) {
      final hpW = bodyW;
      final hp = Rect.fromLTWH(c.dx - hpW / 2, c.dy - bodyH / 2 - 8, hpW * f.health / f.maxHealth, 4);
      canvas.drawRRect(RRect.fromRectAndRadius(hp, const Radius.circular(2)), Paint()..color = Colors.limeAccent);
    }
  }

  void _paintBullet(Canvas canvas, Rect rect, Bullet b) {
    final c = _project(rect, b.x, b.y, b.z);
    final r = (7 / (b.z + 0.8)).clamp(2.0, 7.0);

    for (int i = 0; i < b.trail.length; i++) {
      final t = b.trail[i];
      final tc = _project(rect, t.dx, t.dy, b.z - (b.trail.length - i) * 0.06);
      canvas.drawCircle(
        tc,
        r * (i / b.trail.length) * 0.7,
        Paint()..color = b.color.withOpacity((i / b.trail.length) * 0.35),
      );
    }

    canvas.drawCircle(c, r + 3, Paint()..color = b.color.withOpacity(0.22));
    canvas.drawCircle(c, r, Paint()..color = b.color);
  }

  void _paintEffect(Canvas canvas, Rect rect, HitEffect e) {
    final c = _project(rect, e.x, e.y - e.t * 0.1, e.z);
    final alpha = (1 - e.t).clamp(0.0, 1.0);
    final tp = TextPainter(
      text: TextSpan(
        text: e.text,
        style: TextStyle(
          color: e.color.withOpacity(alpha),
          fontWeight: FontWeight.bold,
          fontSize: e.big ? 18 : 13,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    canvas.drawCircle(c, (12 + e.t * 24) * (e.big ? 1.4 : 1), Paint()..color = e.color.withOpacity(0.14 * alpha));
  }

  void _paintCannons(Canvas canvas, Rect rect) {
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      final x = rect.width * ((i + 0.5) / players.length);
      final y = rect.bottom - 32;
      final rc = (recoil[p.id] ?? 0).clamp(0.0, 1.0);
      final muzzle = (muzzleFlash[p.id] ?? 0).clamp(0.0, 1.0);
      final pulse = (scorePulse[p.id] ?? 0).clamp(0.0, 1.0);

      canvas.drawCircle(Offset(x, y), 26, Paint()..color = Colors.black.withOpacity(0.4));
      canvas.drawCircle(Offset(x, y), 22, Paint()..color = p.color.withOpacity(0.45 + pulse * 0.3));

      final angle = p.cannonAzimuth;
      final barrelLen = 45 - rc * 8;
      final tip = Offset(x + math.sin(angle) * barrelLen, y - 18 - math.cos(angle.abs()) * p.cannonElevation * 16);
      canvas.drawLine(
        Offset(x, y - 8),
        tip,
        Paint()
          ..color = Colors.grey.shade200
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(x, y - 8),
        tip,
        Paint()
          ..color = p.color.withOpacity(0.7)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );

      if (muzzle > 0) {
        canvas.drawCircle(tip, 10 + muzzle * 15, Paint()..color = p.color.withOpacity(0.4 * muzzle));
        canvas.drawCircle(tip, 4 + muzzle * 8, Paint()..color = Colors.white.withOpacity(0.8 * muzzle));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FishGamePainter oldDelegate) => true;
}

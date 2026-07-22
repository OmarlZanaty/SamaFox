import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../repositories/fish_game_repository.dart';

/// Underwater fish-shooting arcade game.
///
/// A faithful recreation of the classic bet-to-value fish shooter:
///  - Tap anywhere to fire a projectile from the active cannon; bullets bounce
///    off the screen edges until they hit a fish or leave the screen.
///  - Adjustable bet (1K / 5K / 10K / 50K). Higher bets unlock higher-value
///    fish: fish whose `minBet` is above the current bet render transparent and
///    cannot be targeted (the bet-to-value visibility rule).
///  - Big fish take several hits; capturing awards their coin value with a
///    coin-burst + floating number.
///  - "Frozen" freezes all fish for a few seconds; "Auto" auto-fires at the
///    nearest valid target.
///  - Periodic "BOSS is coming" events spawn a high-value boss.
///  - A blue "Recharge Balance" popup (Arabic) appears when the balance can't
///    cover the current bet.
///
/// The balance is the user's real coin balance — every shot debits the exact
/// bet tier and every capture credits the exact species value via
/// `games/fish/shoot` / `games/fish/capture` (see FishGameRepository and
/// backend/src/controllers/game.controller.ts). Cost and reward are fixed
/// and shown to the player up front; there is no randomness in the payout
/// amount, only in which fish appears — deliberately, so this isn't a game
/// of chance on the stake. The screen updates `_balance` optimistically for
/// snappy taps, then reconciles it against the server response.
class FishShooterScreen extends ConsumerStatefulWidget {
  const FishShooterScreen({super.key});

  @override
  ConsumerState<FishShooterScreen> createState() => _FishShooterScreenState();
}

class _FishShooterScreenState extends ConsumerState<FishShooterScreen>
    with SingleTickerProviderStateMixin {
  final Random _rng = Random();
  final FishGameRepository _repo = FishGameRepository();

  late final AnimationController _loop;
  Duration _last = Duration.zero;

  Size _size = Size.zero;

  // --- Economy ---
  int _balance = 10000;
  static const List<int> _betTiers = [1000, 5000, 10000, 50000];
  int _betIndex = 0;
  int get _bet => _betTiers[_betIndex];

  // --- Entities ---
  final List<_Fish> _fish = [];
  final List<_Bullet> _bullets = [];
  final List<_Bubble> _bubbles = [];
  final List<_FloatText> _floats = [];
  final List<_Particle> _particles = [];

  // --- Timers / state ---
  double _spawnTimer = 0;
  double _bossTimer = 18; // seconds until first boss check
  double _bossBannerTimer = 0; // >0 => banner showing
  double _pendingBossSpawn = 0; // >0 => boss spawns when it hits 0

  double _frozenTimer = 0; // >0 => fish frozen
  double _frozenCooldown = 0;
  bool _auto = false;
  double _autoCooldown = 0;

  double _recoil = 0; // cannon recoil 0..1
  bool _rechargeShowing = false;

  int _nextId = 1;

  @override
  void initState() {
    super.initState();
    final coins = ref.read(authStateProvider).user?.coinsBalance;
    if (coins != null && coins > 0) _balance = coins;

    _loop = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_tick)
      ..forward();

    // Seed some bubbles so the scene isn't empty on first frame.
    for (int i = 0; i < 16; i++) {
      _bubbles.add(_Bubble(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        r: 2 + _rng.nextDouble() * 6,
        speed: 0.04 + _rng.nextDouble() * 0.08,
      ));
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Game loop
  // ---------------------------------------------------------------------------
  void _tick() {
    final now = _loop.lastElapsedDuration ?? Duration.zero;
    double dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.1) dt = 0.016;
    if (_size == Size.zero) return;
    _update(dt);
    if (mounted) setState(() {});
  }

  void _update(double dt) {
    final w = _size.width;
    final h = _size.height;

    // Bubbles rise continuously.
    for (final b in _bubbles) {
      b.y -= b.speed * dt;
      if (b.y < -0.05) {
        b.y = 1.05;
        b.x = _rng.nextDouble();
      }
    }

    // Recoil decay.
    if (_recoil > 0) _recoil = (_recoil - dt * 4).clamp(0, 1);

    // Frozen timers.
    if (_frozenTimer > 0) _frozenTimer -= dt;
    if (_frozenCooldown > 0) _frozenCooldown -= dt;

    final frozen = _frozenTimer > 0;

    // Fish movement.
    for (final f in _fish) {
      f.wag += dt * f.wagSpeed;
      if (!frozen) {
        f.x += f.vx * dt;
        f.phase += dt * f.bobSpeed;
        f.y = f.baseY + sin(f.phase) * f.bobAmp;
      }
      if (f.hitFlash > 0) f.hitFlash -= dt;
    }
    // Remove fish that swam off screen.
    _fish.removeWhere((f) =>
        (f.vx > 0 && f.x > w + f.radius + 40) ||
        (f.vx < 0 && f.x < -f.radius - 40));

    // Spawning.
    _spawnTimer -= dt;
    const maxFish = 9;
    if (_spawnTimer <= 0 && _fish.length < maxFish) {
      _spawnTimer = 1.1 + _rng.nextDouble() * 1.2;
      _spawnFish();
    }

    // Boss lifecycle.
    if (_bossBannerTimer > 0) {
      _bossBannerTimer -= dt;
    }
    if (_pendingBossSpawn > 0) {
      _pendingBossSpawn -= dt;
      if (_pendingBossSpawn <= 0) _spawnBoss();
    }
    _bossTimer -= dt;
    if (_bossTimer <= 0 && _bossBannerTimer <= 0 && _pendingBossSpawn <= 0) {
      _bossTimer = 35 + _rng.nextDouble() * 20;
      _bossBannerTimer = 3.2;
      _pendingBossSpawn = 2.6;
      HapticFeedback.heavyImpact();
    }

    // Auto fire.
    if (_autoCooldown > 0) _autoCooldown -= dt;
    if (_auto && _autoCooldown <= 0) {
      final target = _nearestTargetable();
      if (target != null) {
        _fireAt(Offset(target.x, target.y));
        _autoCooldown = 0.32;
      }
    }

    // Bullets.
    final cannon = Offset(w / 2, h);
    for (final b in _bullets) {
      b.trail.add(b.pos);
      if (b.trail.length > 6) b.trail.removeAt(0);
      b.pos += b.vel * dt;
      b.life -= dt;
      // Bounce off edges.
      if (b.pos.dx < b.r) {
        b.pos = Offset(b.r, b.pos.dy);
        b.vel = Offset(-b.vel.dx, b.vel.dy);
        b.bounces++;
      } else if (b.pos.dx > w - b.r) {
        b.pos = Offset(w - b.r, b.pos.dy);
        b.vel = Offset(-b.vel.dx, b.vel.dy);
        b.bounces++;
      }
      if (b.pos.dy < b.r) {
        b.pos = Offset(b.pos.dx, b.r);
        b.vel = Offset(b.vel.dx, -b.vel.dy);
        b.bounces++;
      }
    }
    _bullets.removeWhere((b) =>
        b.life <= 0 || b.bounces > 5 || b.pos.dy > h + 30);

    // Collisions.
    _handleCollisions();

    // Floating text.
    for (final t in _floats) {
      t.y -= dt * 60;
      t.life -= dt;
    }
    _floats.removeWhere((t) => t.life <= 0);

    // Particles (coin burst).
    for (final p in _particles) {
      p.pos += p.vel * dt;
      p.vel = Offset(p.vel.dx * 0.96, p.vel.dy + 140 * dt); // gravity
      p.life -= dt;
    }
    _particles.removeWhere((p) => p.life <= 0);

    // Ignore cannon var lint by referencing (kept for clarity of muzzle).
    assert(cannon != Offset.zero || true);
  }

  void _handleCollisions() {
    for (final b in List<_Bullet>.from(_bullets)) {
      for (final f in _fish) {
        if (!f.targetable(_bet)) continue;
        final d = (Offset(f.x, f.y) - b.pos).distance;
        if (d <= f.radius + b.r) {
          _bullets.remove(b);
          f.hp -= 1;
          f.hitFlash = 0.18;
          HapticFeedback.selectionClick();
          if (f.hp <= 0) {
            _capture(f);
          }
          break;
        }
      }
    }
  }

  void _capture(_Fish f) {
    _fish.remove(f);
    final reward = f.value;
    _balance += reward; // optimistic; reconciled by _syncCapture against the real balance
    HapticFeedback.mediumImpact();
    _floats.add(_FloatText(x: f.x, y: f.y, text: '+${_fmt(reward)}', color: f.glow));
    // Coin burst.
    final n = f.isBoss ? 26 : 12;
    for (int i = 0; i < n; i++) {
      final a = _rng.nextDouble() * pi * 2;
      final sp = 60 + _rng.nextDouble() * 160;
      _particles.add(_Particle(
        pos: Offset(f.x, f.y),
        vel: Offset(cos(a) * sp, sin(a) * sp - 60),
        life: 0.6 + _rng.nextDouble() * 0.5,
        color: const Color(0xFFFFD54A),
      ));
    }
    _syncCapture(f.spec.key, reward);
  }

  Future<void> _syncCapture(String speciesKey, int expectedReward) async {
    try {
      final result = await _repo.capture(speciesKey);
      if (!mounted) return;
      setState(() => _balance = result.balance);
      ref.read(authStateProvider.notifier).updateCoinsBalance(result.balance);
    } on FishGameException catch (e) {
      if (!mounted) return;
      setState(() => _balance -= expectedReward); // rollback the optimistic credit
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ---------------------------------------------------------------------------
  // Spawning
  // ---------------------------------------------------------------------------
  void _spawnFish() {
    final w = _size.width;
    final h = _size.height;
    final species = _pickSpecies();
    final fromLeft = _rng.nextBool();
    final baseY = 60 + _rng.nextDouble() * (h * 0.62);
    final speed = species.speed * (0.8 + _rng.nextDouble() * 0.5);
    _fish.add(_Fish(
      id: _nextId++,
      spec: species,
      x: fromLeft ? -species.radius : w + species.radius,
      baseY: baseY,
      vx: fromLeft ? speed : -speed,
      bobAmp: 6 + _rng.nextDouble() * 18,
      bobSpeed: 0.6 + _rng.nextDouble() * 1.2,
      phase: _rng.nextDouble() * pi * 2,
      wagSpeed: 6 + _rng.nextDouble() * 4,
      hp: species.hp,
    ));
  }

  void _spawnBoss() {
    final w = _size.width;
    final h = _size.height;
    final fromLeft = _rng.nextBool();
    const boss = _Species(
      shape: _FishShape.dragon,
      name: 'التنين',
      key: 'dragon',
      value: 1000000,
      minBet: 5000,
      hp: 22,
      radius: 92,
      speed: 20,
      glow: Color(0xFF7CFF6B),
      body: Color(0xFF2E7D32),
      isBoss: true,
    );
    _fish.add(_Fish(
      id: _nextId++,
      spec: boss,
      x: fromLeft ? -boss.radius : w + boss.radius,
      baseY: h * 0.28,
      vx: fromLeft ? boss.speed : -boss.speed,
      bobAmp: 26,
      bobSpeed: 0.8,
      phase: 0,
      wagSpeed: 5,
      hp: boss.hp,
    ));
  }

  _Species _pickSpecies() {
    // Weighted by rarity: cheap fish common, ultra-rare fish scarce.
    final roll = _rng.nextInt(1000);
    if (roll < 300) return _species[0]; // tropical
    if (roll < 520) return _species[1]; // puffer
    if (roll < 680) return _species[2]; // squid
    if (roll < 790) return _species[3]; // octopus
    if (roll < 860) return _species[4]; // turtle
    if (roll < 910) return _species[5]; // dolphin
    if (roll < 945) return _species[6]; // shark
    if (roll < 970) return _species[7]; // lobster
    if (roll < 987) return _species[8]; // golden
    if (roll < 996) return _species[9]; // whale
    return _species[10]; // mega shark
  }

  _Fish? _nearestTargetable() {
    final origin = Offset(_size.width / 2, _size.height);
    _Fish? best;
    double bestD = double.infinity;
    for (final f in _fish) {
      if (!f.targetable(_bet)) continue;
      final d = (Offset(f.x, f.y) - origin).distance;
      if (d < bestD) {
        bestD = d;
        best = f;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Firing
  // ---------------------------------------------------------------------------
  void _onTap(Offset local) {
    // Tapping a locked high-value fish gives feedback instead of a silent miss.
    for (final f in _fish) {
      if (!f.targetable(_bet) &&
          (Offset(f.x, f.y) - local).distance < f.radius * 0.85) {
        _showLockedHint(f);
        return;
      }
    }
    _fireAt(local);
  }

  void _showLockedHint(_Fish f) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
        backgroundColor: const Color(0xFF0D47A1),
        content: Text(
          'ارفع الرهان إلى ${_fmt(f.spec.minBet)} لاستهداف ${f.spec.name}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ));
  }

  void _fireAt(Offset target) {
    if (_balance < _bet) {
      _showRecharge();
      _auto = false;
      return;
    }
    final betCharged = _bet;
    _balance -= betCharged; // optimistic; reconciled by _syncShot against the real balance
    _recoil = 1;
    SystemSound.play(SystemSoundType.click);

    final origin = Offset(_size.width / 2, _size.height - 6);
    var dir = target - origin;
    if (dir.distance < 1) dir = const Offset(0, -1);
    final v = dir / dir.distance * 520;
    _bullets.add(_Bullet(
      pos: origin,
      vel: v,
      r: 7 + _betIndex * 1.5,
      life: 3.0,
      color: _bulletColor(),
    ));

    _syncShot(betCharged);
  }

  Future<void> _syncShot(int bet) async {
    try {
      final balance = await _repo.shoot(bet);
      if (!mounted) return;
      setState(() => _balance = balance);
      ref.read(authStateProvider.notifier).updateCoinsBalance(balance);
    } on FishGameException catch (e) {
      if (!mounted) return;
      setState(() {
        _balance += bet; // rollback the optimistic charge
        _auto = false;
      });
      if (e.code == 'INSUFFICIENT_COINS') {
        _showRecharge();
      } else {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Color _bulletColor() {
    switch (_betIndex) {
      case 0:
        return const Color(0xFF6EC6FF);
      case 1:
        return const Color(0xFF69F0AE);
      case 2:
        return const Color(0xFFFFD54A);
      default:
        return const Color(0xFFFF6EC7);
    }
  }

  void _adjustBet(int delta) {
    setState(() {
      _betIndex = (_betIndex + delta).clamp(0, _betTiers.length - 1);
    });
  }

  void _toggleFrozen() {
    if (_frozenTimer > 0 || _frozenCooldown > 0) return;
    setState(() {
      _frozenTimer = 4.0;
      _frozenCooldown = 12.0;
    });
    HapticFeedback.mediumImpact();
  }

  void _toggleAuto() {
    setState(() => _auto = !_auto);
  }

  void _showRecharge() {
    if (_rechargeShowing) return;
    _rechargeShowing = true;
    showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _RechargeDialog(bet: _bet),
    ).then((res) {
      _rechargeShowing = false;
      if (res == 'recharge' && mounted) {
        Navigator.of(context).pushNamed('/charging-agent');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------
  static String _fmt(int v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
    }
    if (v >= 1000) {
      final k = v / 1000;
      return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
    }
    return '$v';
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF021B3A),
        body: LayoutBuilder(
          builder: (context, constraints) {
            _size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _onTap(d.localPosition),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildBackground(),
                  _buildLightRays(),
                  ..._buildDecor(),
                  ..._bubbles.map(_buildBubble),
                  ..._fish.map(_buildFish),
                  ..._fish.where((f) => f.targetable(_bet)).map(_buildFishLabel),
                  for (final b in _bullets) ..._buildBullet(b),
                  _buildMuzzleFlash(),
                  ..._particles.map(_buildParticle),
                  ..._floats.map(_buildFloat),
                  _buildVignette(),
                  _buildSidebar(),
                  _buildTopBar(),
                  _buildBottomBar(),
                  if (_bossBannerTimer > 0) _buildBossBanner(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF063E7A),
              Color(0xFF0A5A8C),
              Color(0xFF0E7C9B),
              Color(0xFF021B3A),
            ],
            stops: [0.0, 0.4, 0.75, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildLightRays() {
    // Diagonal god-rays fanning down from the surface for depth.
    return Positioned.fill(
      child: IgnorePointer(
        child: Transform.rotate(
          angle: 0.22,
          alignment: Alignment.topCenter,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              5,
              (i) => Container(
                width: 26 + (i.isEven ? 16 : 0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.10),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVignette() {
    // Subtle darkened edges to focus the scene — premium arcade look.
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.1,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.10),
                Colors.black.withOpacity(0.42),
              ],
              stops: const [0.55, 0.82, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMuzzleFlash() {
    if (_recoil < 0.35) return const SizedBox.shrink();
    final size = 26 + 34 * _recoil;
    return Positioned(
      left: _size.width / 2 - size / 2,
      top: _size.height - size / 2 - 4,
      child: IgnorePointer(
        child: Opacity(
          opacity: _recoil.clamp(0, 1),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Colors.white,
                _bulletColor().withOpacity(0.7),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDecor() {
    // Static decorative reef along the bottom.
    final h = _size.height;
    return [
      Positioned(
        left: 10,
        bottom: 6,
        child: Text('🪸', style: TextStyle(fontSize: 46, shadows: _softGlow(Colors.pinkAccent))),
      ),
      Positioned(
        left: 70,
        bottom: 0,
        child: Text('🌿', style: TextStyle(fontSize: 54, shadows: _softGlow(Colors.greenAccent))),
      ),
      Positioned(
        right: 24,
        bottom: 2,
        child: Text('🪸', style: TextStyle(fontSize: 40, shadows: _softGlow(Colors.deepOrangeAccent))),
      ),
      Positioned(
        right: 84,
        bottom: 0,
        child: Text('🌿', style: TextStyle(fontSize: 46, shadows: _softGlow(Colors.tealAccent))),
      ),
      Positioned(
        left: _size.width * 0.5 - 30,
        bottom: -6,
        child: Opacity(
          opacity: 0.5,
          child: Text('🚢', style: TextStyle(fontSize: 60, shadows: _softGlow(Colors.blueGrey))),
        ),
      ),
      Positioned(
        left: 4,
        top: h * 0.4,
        child: Opacity(opacity: 0.35, child: const Text('⚓', style: TextStyle(fontSize: 30))),
      ),
    ];
  }

  List<Shadow> _softGlow(Color c) =>
      [Shadow(color: c.withOpacity(0.6), blurRadius: 14)];

  Widget _buildBubble(_Bubble b) {
    return Positioned(
      left: b.x * _size.width,
      top: b.y * _size.height,
      child: Container(
        width: b.r,
        height: b.r,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.10),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
        ),
      ),
    );
  }

  Widget _buildFish(_Fish f) {
    final targetable = f.targetable(_bet);
    final w = f.radius * 2.7;
    final h = f.radius * 2.2;
    final flip = f.vx < 0; // painter faces right; flip when swimming left
    return Positioned(
      left: f.x - w / 2,
      top: f.y - h / 2,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Opacity(
          opacity: targetable ? 1.0 : 0.26,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(flip ? -1.0 : 1.0, 1.0),
            child: CustomPaint(
              painter: _FishPainter(
                shape: f.spec.shape,
                body: f.spec.body,
                glow: f.spec.glow,
                wag: sin(f.wag),
                golden: f.spec.golden || f.isBoss,
                flash: f.hitFlash > 0,
                special: targetable && (f.spec.minBet >= 10000 || f.isBoss),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFishLabel(_Fish f) {
    return Positioned(
      left: f.x - 45,
      top: f.y + f.radius * 0.55,
      width: 90,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: f.glow.withOpacity(0.9), width: 1),
            ),
            child: Text(
              _fmt(f.value),
              style: TextStyle(
                color: f.glow,
                fontSize: f.isBoss ? 14 : 11,
                fontWeight: FontWeight.w900,
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBullet(_Bullet b) {
    final widgets = <Widget>[];
    // Fading trail.
    for (int i = 0; i < b.trail.length; i++) {
      final p = b.trail[i];
      final f = (i + 1) / (b.trail.length + 1);
      final tr = b.r * (0.35 + 0.5 * f);
      widgets.add(Positioned(
        left: p.dx - tr,
        top: p.dy - tr,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.35 * f,
            child: Container(
              width: tr * 2,
              height: tr * 2,
              decoration: BoxDecoration(shape: BoxShape.circle, color: b.color),
            ),
          ),
        ),
      ));
    }
    // Bullet core.
    widgets.add(Positioned(
      left: b.pos.dx - b.r,
      top: b.pos.dy - b.r,
      child: IgnorePointer(
        child: Container(
          width: b.r * 2,
          height: b.r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Colors.white, b.color]),
            boxShadow: [BoxShadow(color: b.color.withOpacity(0.9), blurRadius: 14, spreadRadius: 1)],
          ),
        ),
      ),
    ));
    return widgets;
  }

  Widget _buildParticle(_Particle p) {
    return Positioned(
      left: p.pos.dx - 4,
      top: p.pos.dy - 4,
      child: IgnorePointer(
        child: Opacity(
          opacity: p.life.clamp(0, 1),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.color,
              boxShadow: [BoxShadow(color: p.color.withOpacity(0.8), blurRadius: 6)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloat(_FloatText t) {
    return Positioned(
      left: t.x - 40,
      top: t.y - 12,
      width: 80,
      child: IgnorePointer(
        child: Opacity(
          opacity: t.life.clamp(0, 1),
          child: Text(
            t.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }

  // --- HUD ---
  Widget _buildTopBar() {
    final user = ref.watch(authStateProvider).user;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              // Balance card (top-start).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.blueGrey.shade700,
                      backgroundImage: (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child: (user?.avatarUrl == null || user!.avatarUrl!.isEmpty)
                          ? const Icon(Icons.person, size: 16, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    const Text('🪙', style: TextStyle(fontSize: 15)),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(_balance),
                      style: const TextStyle(
                        color: Color(0xFFFFD54A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    // Vertical fish-value list; dims fish not targetable at the current bet.
    return Positioned(
      left: 6,
      top: 70,
      bottom: 110,
      child: SafeArea(
        child: Center(
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final s in _species.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Opacity(
                      opacity: _bet >= s.minBet ? 1.0 : 0.32,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 46,
                            height: 26,
                            child: CustomPaint(
                              painter: _FishPainter(
                                shape: s.shape,
                                body: s.body,
                                glow: s.glow,
                                wag: 0,
                                golden: s.golden,
                                flash: false,
                                special: false,
                              ),
                            ),
                          ),
                          Text(
                            _fmt(s.value),
                            style: TextStyle(
                              color: _bet >= s.minBet
                                  ? const Color(0xFFFFD54A)
                                  : Colors.white54,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final recoilDy = 10 * _recoil;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Frozen + Auto (bottom-end in RTL => visually left of cannons).
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _circleButton(
                    label: 'تلقائي',
                    emoji: '🎯',
                    active: _auto,
                    onTap: _toggleAuto,
                  ),
                  const SizedBox(height: 10),
                  _circleButton(
                    label: 'تجميد',
                    emoji: '❄️',
                    active: _frozenTimer > 0,
                    disabled: _frozenCooldown > 0,
                    onTap: _toggleFrozen,
                  ),
                ],
              ),
              const Spacer(),
              // Cannons + bet control.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Transform.translate(
                        offset: Offset(0, recoilDy),
                        child: const Text('🔫', style: TextStyle(fontSize: 40)),
                      ),
                      const SizedBox(width: 6),
                      _betControl(),
                      const SizedBox(width: 6),
                      Transform.translate(
                        offset: Offset(0, recoilDy),
                        child: Transform.flip(
                          flipX: true,
                          child: const Text('🔫', style: TextStyle(fontSize: 40)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              const SizedBox(width: 64), // balance the row against the buttons
            ],
          ),
        ),
      ),
    );
  }

  Widget _betControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54A), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _miniBtn(Icons.remove, () => _adjustBet(-1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              children: [
                const Text('الرهان', style: TextStyle(color: Colors.white54, fontSize: 8)),
                Text(
                  _fmt(_bet),
                  style: const TextStyle(
                    color: Color(0xFFFFD54A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          _miniBtn(Icons.add, () => _adjustBet(1)),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFFFD54A),
        ),
        child: Icon(icon, size: 16, color: Colors.black),
      ),
    );
  }

  Widget _circleButton({
    required String label,
    required String emoji,
    required VoidCallback onTap,
    bool active = false,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: active
                    ? [const Color(0xFF00E5FF), const Color(0xFF2979FF)]
                    : [Colors.white24, Colors.white10],
              ),
              border: Border.all(
                color: active ? Colors.white : Colors.white30,
                width: 2,
              ),
              boxShadow: active
                  ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.6), blurRadius: 12)]
                  : null,
            ),
            child: Opacity(
              opacity: disabled ? 0.4 : 1,
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildBossBanner() {
    final t = (_bossBannerTimer).clamp(0.0, 3.2);
    final pulse = 0.8 + 0.2 * sin(t * 10);
    return Positioned(
      top: _size.height * 0.34,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Transform.scale(
            scale: pulse,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB71C1C), Color(0xFFFF6D00)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.7), blurRadius: 24)],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('⚠️ هجوم الزعيم ⚠️',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      )),
                  SizedBox(height: 2),
                  Text('BOSS is coming — 1,000,000',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Species table (ascending value; sidebar shows it reversed).
  // ---------------------------------------------------------------------------
  static const List<_Species> _species = [
    _Species(shape: _FishShape.fish, name: 'سمكة استوائية', key: 'tropical', value: 2000, minBet: 1000, hp: 1, radius: 34, speed: 34, glow: Color(0xFFFFC107), body: Color(0xFFFF7043)),
    _Species(shape: _FishShape.puffer, name: 'سمكة منتفخة', key: 'puffer', value: 3000, minBet: 1000, hp: 1, radius: 38, speed: 30, glow: Color(0xFFFF80AB), body: Color(0xFFF06292)),
    _Species(shape: _FishShape.squid, name: 'حبار', key: 'squid', value: 4000, minBet: 1000, hp: 2, radius: 42, speed: 32, glow: Color(0xFFB388FF), body: Color(0xFF9575CD)),
    _Species(shape: _FishShape.octopus, name: 'أخطبوط', key: 'octopus', value: 6000, minBet: 1000, hp: 2, radius: 46, speed: 27, glow: Color(0xFFFF5252), body: Color(0xFFE53935)),
    _Species(shape: _FishShape.turtle, name: 'سلحفاة', key: 'turtle', value: 12000, minBet: 1000, hp: 3, radius: 50, speed: 24, glow: Color(0xFF69F0AE), body: Color(0xFF43A047)),
    _Species(shape: _FishShape.dolphin, name: 'دلفين', key: 'dolphin', value: 30000, minBet: 5000, hp: 4, radius: 54, speed: 40, glow: Color(0xFF40C4FF), body: Color(0xFF29B6F6)),
    _Species(shape: _FishShape.shark, name: 'قرش', key: 'shark', value: 50000, minBet: 5000, hp: 5, radius: 62, speed: 37, glow: Color(0xFFB0BEC5), body: Color(0xFF78909C)),
    _Species(shape: _FishShape.lobster, name: 'كركند', key: 'lobster', value: 100000, minBet: 5000, hp: 6, radius: 54, speed: 22, glow: Color(0xFFFF6E40), body: Color(0xFFE64A19)),
    _Species(shape: _FishShape.fish, name: 'السمكة الذهبية', key: 'golden', value: 500000, minBet: 10000, hp: 8, radius: 66, speed: 24, glow: Color(0xFFFFD54A), body: Color(0xFFFFB300), golden: true),
    _Species(shape: _FishShape.whale, name: 'الحوت النادر', key: 'whale', value: 5000000, minBet: 10000, hp: 14, radius: 86, speed: 17, glow: Color(0xFF18FFFF), body: Color(0xFF0097A7)),
    _Species(shape: _FishShape.shark, name: 'القرش الأسطوري', key: 'megashark', value: 10000000, minBet: 50000, hp: 18, radius: 78, speed: 26, glow: Color(0xFFE040FB), body: Color(0xFF8E24AA), golden: true),
  ];
}

// =============================================================================
// Data classes
// =============================================================================
enum _FishShape { fish, puffer, squid, octopus, turtle, dolphin, shark, lobster, whale, dragon }

class _Species {
  final _FishShape shape;
  final String name;
  final String key; // server-side lookup key — see FISH_SPECIES_VALUES in game.controller.ts
  final int value;
  final int minBet;
  final int hp;
  final double radius;
  final double speed;
  final Color glow;
  final Color body;
  final bool golden;
  final bool isBoss;

  const _Species({
    required this.shape,
    required this.name,
    required this.key,
    required this.value,
    required this.minBet,
    required this.hp,
    required this.radius,
    required this.speed,
    required this.glow,
    required this.body,
    this.golden = false,
    this.isBoss = false,
  });
}

class _Fish {
  final int id;
  final _Species spec;
  double x;
  double baseY;
  double y;
  final double vx;
  final double bobAmp;
  final double bobSpeed;
  double phase;
  double wag = 0;
  final double wagSpeed;
  int hp;
  double hitFlash = 0;

  _Fish({
    required this.id,
    required this.spec,
    required this.x,
    required this.baseY,
    required this.vx,
    required this.bobAmp,
    required this.bobSpeed,
    required this.phase,
    required this.wagSpeed,
    required this.hp,
  }) : y = baseY;

  double get radius => spec.radius;
  int get value => spec.value;
  Color get glow => spec.glow;
  bool get isBoss => spec.isBoss;

  bool targetable(int bet) => bet >= spec.minBet;
}

class _Bullet {
  Offset pos;
  Offset vel;
  final double r;
  double life;
  int bounces = 0;
  final Color color;
  final List<Offset> trail = [];

  _Bullet({
    required this.pos,
    required this.vel,
    required this.r,
    required this.life,
    required this.color,
  });
}

class _Bubble {
  double x;
  double y;
  final double r;
  final double speed;
  _Bubble({required this.x, required this.y, required this.r, required this.speed});
}

class _FloatText {
  final double x;
  double y;
  final String text;
  final Color color;
  double life = 1.2;
  _FloatText({required this.x, required this.y, required this.text, required this.color});
}

class _Particle {
  Offset pos;
  Offset vel;
  double life;
  final Color color;
  _Particle({required this.pos, required this.vel, required this.life, required this.color});
}

// =============================================================================
// Vector creature painter — draws real fish/sea-creatures (no emoji).
// All shapes face right (+x); the widget flips horizontally to swim left.
// Drawn in unit space: center at origin, 1.0 == half the canvas height.
// =============================================================================
class _FishPainter extends CustomPainter {
  final _FishShape shape;
  final Color body;
  final Color glow;
  final double wag; // -1..1
  final bool golden;
  final bool flash;
  final bool special;

  _FishPainter({
    required this.shape,
    required this.body,
    required this.glow,
    required this.wag,
    required this.golden,
    required this.flash,
    required this.special,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height / 2;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);

    final base = flash ? Colors.white : body;
    final belly = Color.lerp(base, Colors.white, 0.60)!;
    final dark = Color.lerp(base, Colors.black, 0.28)!;
    final fin = flash ? Colors.white : Color.lerp(body, glow, 0.5)!;

    if (special) {
      canvas.drawCircle(
        Offset.zero,
        1.15,
        Paint()
          ..color = glow.withOpacity(0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3),
      );
    }

    switch (shape) {
      case _FishShape.fish:
        _fish(canvas, base, belly, dark, fin);
        break;
      case _FishShape.puffer:
        _puffer(canvas, base, belly, dark, fin);
        break;
      case _FishShape.squid:
        _squid(canvas, base, belly, dark, fin);
        break;
      case _FishShape.octopus:
        _octopus(canvas, base, belly, dark, fin);
        break;
      case _FishShape.turtle:
        _turtle(canvas, base, belly, dark, fin);
        break;
      case _FishShape.dolphin:
        _dolphin(canvas, base, belly, dark, fin);
        break;
      case _FishShape.shark:
        _shark(canvas, base, belly, dark, fin);
        break;
      case _FishShape.lobster:
        _lobster(canvas, base, belly, dark, fin);
        break;
      case _FishShape.whale:
        _whale(canvas, base, belly, dark, fin);
        break;
      case _FishShape.dragon:
        _dragon(canvas, base, belly, dark, fin);
        break;
    }
    canvas.restore();
  }

  Paint _grad(Color top, Color bottom, {double h = 0.7}) => Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, -h),
      Offset(0, h),
      [top, bottom],
    );

  void _eye(Canvas c, double x, double y, [double r = 0.13]) {
    c.drawCircle(Offset(x, y), r, Paint()..color = Colors.white);
    c.drawCircle(Offset(x + r * 0.25, y), r * 0.55, Paint()..color = Colors.black87);
    c.drawCircle(Offset(x + r * 0.05, y - r * 0.25), r * 0.2, Paint()..color = Colors.white);
  }

  // ---- Classic fish ----
  void _fish(Canvas c, Color base, Color belly, Color dark, Color fin) {
    final finP = Paint()..color = fin;
    // Tail (wagging around joint ~ x=-0.5)
    c.save();
    c.translate(-0.5, 0);
    c.rotate(wag * 0.35);
    final tail = Path()
      ..moveTo(0, 0)
      ..lineTo(-0.7, -0.5)
      ..quadraticBezierTo(-0.45, 0, -0.7, 0.5)
      ..close();
    c.drawPath(tail, finP);
    c.restore();
    // Dorsal + pelvic fins
    c.drawPath(
        Path()
          ..moveTo(0.15, -0.45)
          ..quadraticBezierTo(-0.2, -0.85, -0.35, -0.4)
          ..close(),
        finP);
    c.drawPath(
        Path()
          ..moveTo(0.15, 0.4)
          ..quadraticBezierTo(-0.05, 0.75, -0.3, 0.42)
          ..close(),
        finP);
    // Body
    final bodyPath = Path()
      ..moveTo(0.95, 0)
      ..quadraticBezierTo(0.35, -0.68, -0.45, -0.32)
      ..quadraticBezierTo(-0.6, 0, -0.45, 0.32)
      ..quadraticBezierTo(0.35, 0.68, 0.95, 0)
      ..close();
    c.drawPath(bodyPath, _grad(base, belly));
    c.drawPath(bodyPath, Paint()..color = dark..style = PaintingStyle.stroke..strokeWidth = 0.03);
    // Pectoral fin
    c.drawPath(
        Path()
          ..moveTo(0.2, 0.05)
          ..quadraticBezierTo(-0.05, 0.45, 0.35, 0.35)
          ..close(),
        Paint()..color = fin.withOpacity(0.85));
    // Gill + eye
    c.drawLine(const Offset(0.45, -0.28), const Offset(0.4, 0.28),
        Paint()..color = dark..strokeWidth = 0.03);
    _eye(c, 0.6, -0.12);
  }

  // ---- Pufferfish ----
  void _puffer(Canvas c, Color base, Color belly, Color dark, Color fin) {
    final spikes = Paint()..color = fin;
    for (int i = 0; i < 16; i++) {
      final a = i * pi / 8;
      final p1 = Offset(cos(a) * 0.72, sin(a) * 0.72);
      final p2 = Offset(cos(a) * 0.98, sin(a) * 0.98);
      final n = Offset(-sin(a), cos(a)) * 0.09;
      c.drawPath(
          Path()
            ..moveTo(p1.dx + n.dx, p1.dy + n.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p1.dx - n.dx, p1.dy - n.dy)
            ..close(),
          spikes);
    }
    c.drawCircle(Offset.zero, 0.75, _grad(base, belly, h: 0.75));
    c.drawCircle(Offset.zero, 0.75,
        Paint()..color = dark..style = PaintingStyle.stroke..strokeWidth = 0.03);
    // small tail
    c.save();
    c.translate(-0.72, 0);
    c.rotate(wag * 0.3);
    c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(-0.35, -0.28)
          ..lineTo(-0.35, 0.28)
          ..close(),
        spikes);
    c.restore();
    _eye(c, 0.34, -0.14, 0.15);
    // little frown
    c.drawArc(Rect.fromCircle(center: const Offset(0.5, 0.18), radius: 0.14),
        pi, pi, false, Paint()..color = dark..style = PaintingStyle.stroke..strokeWidth = 0.035);
  }

  // ---- Squid ----
  void _squid(Canvas c, Color base, Color belly, Color dark, Color fin) {
    // Mantle points left, head/tentacles to the right.
    final mantle = Path()
      ..moveTo(-0.95, 0)
      ..quadraticBezierTo(-0.2, -0.5, 0.5, -0.32)
      ..quadraticBezierTo(0.7, 0, 0.5, 0.32)
      ..quadraticBezierTo(-0.2, 0.5, -0.95, 0)
      ..close();
    c.drawPath(mantle, _grad(base, belly));
    // Tail fins
    c.drawPath(
        Path()
          ..moveTo(-0.7, -0.2)
          ..lineTo(-1.05, -0.5)
          ..lineTo(-0.6, 0)
          ..close(),
        Paint()..color = fin);
    c.drawPath(
        Path()
          ..moveTo(-0.7, 0.2)
          ..lineTo(-1.05, 0.5)
          ..lineTo(-0.6, 0)
          ..close(),
        Paint()..color = fin);
    // Tentacles
    final tp = Paint()
      ..color = base
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.09
      ..strokeCap = StrokeCap.round;
    for (int i = -2; i <= 2; i++) {
      final y = i * 0.12;
      c.drawPath(
          Path()
            ..moveTo(0.55, y)
            ..quadraticBezierTo(0.85, y + wag * 0.1, 1.05, y + i * 0.05 + wag * 0.15),
          tp);
    }
    _eye(c, 0.2, -0.14, 0.14);
    _eye(c, 0.2, 0.14, 0.14);
  }

  // ---- Octopus ----
  void _octopus(Canvas c, Color base, Color belly, Color dark, Color fin) {
    // Tentacles first (below head)
    final tp = Paint()
      ..color = base
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.13
      ..strokeCap = StrokeCap.round;
    for (int i = -3; i <= 3; i++) {
      final x = i * 0.18;
      c.drawPath(
          Path()
            ..moveTo(x * 0.6, 0.2)
            ..quadraticBezierTo(x, 0.7, x * 1.15 + wag * 0.12 * (i.isEven ? 1 : -1), 0.98),
          tp);
    }
    // Head/mantle
    final head = Path()
      ..addOval(Rect.fromCenter(center: const Offset(0, -0.15), width: 1.5, height: 1.5));
    c.drawPath(head, _grad(base, belly, h: 0.8));
    _eye(c, -0.28, -0.25, 0.17);
    _eye(c, 0.28, -0.25, 0.17);
  }

  // ---- Turtle ----
  void _turtle(Canvas c, Color base, Color belly, Color dark, Color fin) {
    final flip = Paint()..color = fin;
    // Flippers
    c.save();
    c.translate(0.35, -0.35);
    c.rotate(wag * 0.2);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.5, height: 0.24), flip);
    c.restore();
    c.drawOval(const Rect.fromLTWH(-0.7, 0.25, 0.5, 0.24), flip);
    c.drawOval(const Rect.fromLTWH(0.2, 0.3, 0.5, 0.22), flip);
    // Head
    c.drawCircle(const Offset(0.72, 0), 0.2, _grad(base, belly, h: 0.3));
    _eye(c, 0.8, -0.05, 0.07);
    // Shell
    final shell = Rect.fromCenter(center: const Offset(-0.05, 0), width: 1.35, height: 1.1);
    c.drawOval(shell, _grad(dark, base));
    c.drawOval(shell,
        Paint()..color = Colors.black26..style = PaintingStyle.stroke..strokeWidth = 0.04);
    // Shell hex pattern
    final seg = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03;
    c.drawCircle(const Offset(-0.05, 0), 0.24, seg);
    for (int i = 0; i < 6; i++) {
      final a = i * pi / 3;
      c.drawLine(Offset(cos(a) * 0.24 - 0.05, sin(a) * 0.24),
          Offset(cos(a) * 0.62 - 0.05, sin(a) * 0.52), seg);
    }
  }

  // ---- Dolphin ----
  void _dolphin(Canvas c, Color base, Color belly, Color dark, Color fin) {
    // Tail fluke
    c.save();
    c.translate(-0.55, 0);
    c.rotate(wag * 0.3);
    c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-0.45, -0.15, -0.75, -0.45)
          ..quadraticBezierTo(-0.4, 0, -0.75, 0.45)
          ..quadraticBezierTo(-0.45, 0.15, 0, 0)
          ..close(),
        Paint()..color = fin);
    c.restore();
    // Body
    final b = Path()
      ..moveTo(0.98, -0.02)
      ..quadraticBezierTo(0.5, -0.5, -0.5, -0.28)
      ..quadraticBezierTo(-0.6, 0, -0.5, 0.26)
      ..quadraticBezierTo(0.2, 0.5, 0.72, 0.28)
      ..quadraticBezierTo(0.9, 0.2, 0.98, -0.02)
      ..close();
    c.drawPath(b, _grad(base, belly));
    // Beak
    c.drawPath(
        Path()
          ..moveTo(0.85, 0.05)
          ..lineTo(1.12, 0.12)
          ..lineTo(0.85, 0.2)
          ..close(),
        Paint()..color = base);
    // Dorsal fin
    c.drawPath(
        Path()
          ..moveTo(0.15, -0.4)
          ..quadraticBezierTo(-0.1, -0.85, -0.3, -0.38)
          ..close(),
        Paint()..color = fin);
    // Pectoral
    c.drawPath(
        Path()
          ..moveTo(0.35, 0.2)
          ..quadraticBezierTo(0.1, 0.6, 0.5, 0.42)
          ..close(),
        Paint()..color = Color.lerp(fin, Colors.black, 0.15)!);
    _eye(c, 0.7, -0.05, 0.09);
  }

  // ---- Shark ----
  void _shark(Canvas c, Color base, Color belly, Color dark, Color fin) {
    // Tail
    c.save();
    c.translate(-0.6, 0);
    c.rotate(wag * 0.28);
    c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(-0.55, -0.65)
          ..lineTo(-0.35, 0)
          ..lineTo(-0.5, 0.4)
          ..close(),
        Paint()..color = fin);
    c.restore();
    // Body (sleek)
    final b = Path()
      ..moveTo(1.05, 0.02)
      ..quadraticBezierTo(0.4, -0.52, -0.5, -0.26)
      ..quadraticBezierTo(-0.62, 0, -0.5, 0.24)
      ..quadraticBezierTo(0.4, 0.5, 1.05, 0.02)
      ..close();
    c.drawPath(b, _grad(base, belly));
    c.drawPath(b, Paint()..color = dark..style = PaintingStyle.stroke..strokeWidth = 0.03);
    // Big dorsal fin
    c.drawPath(
        Path()
          ..moveTo(0.2, -0.4)
          ..lineTo(-0.15, -0.95)
          ..lineTo(-0.32, -0.36)
          ..close(),
        Paint()..color = fin);
    // Pectoral
    c.drawPath(
        Path()
          ..moveTo(0.35, 0.18)
          ..lineTo(0.1, 0.7)
          ..lineTo(0.55, 0.36)
          ..close(),
        Paint()..color = fin);
    // Gills
    final g = Paint()..color = dark..strokeWidth = 0.025;
    for (int i = 0; i < 3; i++) {
      c.drawLine(Offset(0.5 - i * 0.09, -0.22), Offset(0.5 - i * 0.09, 0.2), g);
    }
    // Mouth
    c.drawLine(const Offset(1.02, 0.18), const Offset(0.7, 0.28),
        Paint()..color = dark..strokeWidth = 0.03);
    _eye(c, 0.75, -0.1, 0.1);
  }

  // ---- Lobster ----
  void _lobster(Canvas c, Color base, Color belly, Color dark, Color fin) {
    final p = Paint()..color = base;
    final legP = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06
      ..strokeCap = StrokeCap.round;
    // Legs
    for (int i = 0; i < 3; i++) {
      final x = -0.1 + i * 0.22;
      c.drawLine(Offset(x, 0.2), Offset(x - 0.12, 0.55), legP);
      c.drawLine(Offset(x, -0.2), Offset(x - 0.12, -0.55), legP);
    }
    // Tail fan (left)
    c.save();
    c.translate(-0.55, 0);
    c.rotate(wag * 0.18);
    for (int i = -2; i <= 2; i++) {
      c.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(-0.4, i * 0.14)
            ..lineTo(-0.3, i * 0.14 + 0.08)
            ..close(),
          p);
    }
    c.restore();
    // Segmented body
    for (int i = 0; i < 4; i++) {
      final x = -0.5 + i * 0.28;
      c.drawOval(Rect.fromCenter(center: Offset(x, 0), width: 0.4, height: 0.6 - i * 0.02),
          _grad(base, Color.lerp(base, dark, 0.3)!, h: 0.3));
    }
    // Head
    c.drawOval(Rect.fromCenter(center: const Offset(0.62, 0), width: 0.5, height: 0.55), p);
    // Antennae
    c.drawLine(const Offset(0.8, -0.1), Offset(1.15, -0.35 + wag * 0.1), legP);
    c.drawLine(const Offset(0.8, 0.1), Offset(1.15, 0.35 + wag * 0.1), legP);
    // Claws
    final claw = _grad(base, belly, h: 0.3);
    c.drawOval(Rect.fromCenter(center: const Offset(1.05, -0.28), width: 0.42, height: 0.3), claw);
    c.drawOval(Rect.fromCenter(center: const Offset(1.05, 0.28), width: 0.42, height: 0.3), claw);
    _eye(c, 0.78, -0.12, 0.08);
    _eye(c, 0.78, 0.12, 0.08);
  }

  // ---- Whale ----
  void _whale(Canvas c, Color base, Color belly, Color dark, Color fin) {
    // Spout
    final spout = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(0.2, -0.72), const Offset(0.12, -1.0), spout);
    c.drawLine(const Offset(0.2, -0.72), const Offset(0.3, -1.0), spout);
    // Tail fluke
    c.save();
    c.translate(-0.7, 0);
    c.rotate(wag * 0.25);
    c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-0.4, -0.1, -0.7, -0.5)
          ..quadraticBezierTo(-0.35, 0, -0.7, 0.5)
          ..quadraticBezierTo(-0.4, 0.1, 0, 0)
          ..close(),
        Paint()..color = fin);
    c.restore();
    // Body
    final b = Path()
      ..moveTo(0.98, -0.05)
      ..quadraticBezierTo(0.5, -0.72, -0.55, -0.4)
      ..quadraticBezierTo(-0.7, 0, -0.55, 0.4)
      ..quadraticBezierTo(0.4, 0.72, 0.98, -0.05)
      ..close();
    c.drawPath(b, _grad(base, dark));
    // White belly
    c.drawPath(
        Path()
          ..moveTo(0.85, 0.2)
          ..quadraticBezierTo(0.2, 0.7, -0.5, 0.35)
          ..quadraticBezierTo(0.2, 0.5, 0.85, 0.2)
          ..close(),
        Paint()..color = belly);
    // Pectoral fin
    c.drawPath(
        Path()
          ..moveTo(0.3, 0.3)
          ..quadraticBezierTo(0.1, 0.7, 0.5, 0.5)
          ..close(),
        Paint()..color = fin);
    // Mouth line
    c.drawPath(
        Path()
          ..moveTo(0.98, 0.05)
          ..quadraticBezierTo(0.7, 0.32, 0.4, 0.28),
        Paint()..color = dark..style = PaintingStyle.stroke..strokeWidth = 0.03);
    _eye(c, 0.62, 0.02, 0.09);
  }

  // ---- Dragon (boss) ----
  void _dragon(Canvas c, Color base, Color belly, Color dark, Color fin) {
    final spineP = Paint()..color = glow;
    // Serpent body segments along a wave
    for (int i = 0; i < 6; i++) {
      final t = i / 5.0;
      final x = 0.7 - t * 1.6;
      final y = sin(t * pi * 1.5 + wag) * 0.28;
      final r = 0.42 - t * 0.22;
      // dorsal spine
      c.drawPath(
          Path()
            ..moveTo(x, y - r)
            ..lineTo(x - 0.1, y - r - 0.25)
            ..lineTo(x - 0.2, y - r)
            ..close(),
          spineP);
      c.drawCircle(Offset(x, y), r, _grad(base, belly, h: r));
    }
    // Head
    final hx = 0.72, hy = sin(wag) * 0.28 * 0 + 0.0;
    c.drawCircle(Offset(hx, hy), 0.42, _grad(Color.lerp(base, glow, 0.3)!, base, h: 0.4));
    // Snout
    c.drawPath(
        Path()
          ..moveTo(hx + 0.3, hy - 0.1)
          ..lineTo(hx + 0.7, hy + 0.02)
          ..lineTo(hx + 0.3, hy + 0.18)
          ..close(),
        Paint()..color = base);
    // Horns
    final horn = Paint()..color = Colors.amber.shade200;
    c.drawPath(
        Path()
          ..moveTo(hx - 0.1, hy - 0.35)
          ..lineTo(hx - 0.25, hy - 0.7)
          ..lineTo(hx + 0.05, hy - 0.42)
          ..close(),
        horn);
    // Whiskers
    final wh = Paint()
      ..color = glow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04
      ..strokeCap = StrokeCap.round;
    c.drawPath(
        Path()
          ..moveTo(hx + 0.6, hy + 0.05)
          ..quadraticBezierTo(hx + 0.9, hy - 0.2, hx + 1.05, hy + 0.15 + wag * 0.1),
        wh);
    _eye(c, hx + 0.15, hy - 0.08, 0.11);
  }

  @override
  bool shouldRepaint(covariant _FishPainter old) =>
      old.wag != wag || old.flash != flash || old.special != special;
}

// =============================================================================
// Recharge popup
// =============================================================================
class _RechargeDialog extends StatelessWidget {
  final int bet;
  const _RechargeDialog({required this.bet});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF64B5F6), width: 2),
            boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 24)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💎', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              const Text(
                'شحن الرصيد',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'رصيدك غير كافٍ لهذا الرهان (${_FishShooterScreenState._fmt(bet)}).\nقم بشحن رصيدك للاستمرار في الصيد.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('لاحقاً', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD54A),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context, 'recharge'),
                      child: const Text('شحن الآن', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

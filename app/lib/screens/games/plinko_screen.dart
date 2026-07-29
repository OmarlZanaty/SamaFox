import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/plinko_repository.dart';
import 'plinko_board.dart';
import 'plinko_physics.dart';
import 'plinko_sfx.dart';
import 'plinko_sim.dart';

/// Artwork for the board. Every field is nullable and the painter falls back to
/// drawn shapes for anything missing, so a dropped asset degrades one sprite
/// instead of breaking the game.
class _PlinkoArt {
  const _PlinkoArt({
    this.peg,
    this.pegHit,
    this.ballLow,
    this.ballMedium,
    this.ballHigh,
    this.flash,
    this.slots = const [],
  });

  final ui.Image? peg, pegHit, ballLow, ballMedium, ballHigh, flash;
  final List<ui.Image?> slots;

  ui.Image? ballFor(String risk) => switch (risk) {
        'low' => ballLow,
        'high' => ballHigh,
        _ => ballMedium,
      };

  ui.Image? slotFor(double multiplier) {
    if (slots.length < 7) return null;
    final tier = switch (multiplier) {
      >= 100 => 6,
      >= 25 => 5,
      >= 9 => 4,
      >= 3 => 3,
      >= 1.1 => 2,
      >= 1 => 1,
      _ => 0,
    };
    return slots[tier];
  }

  static Future<ui.Image?> _load(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static Future<_PlinkoArt> load() async {
    const dir = 'assets/images/plinko';
    final results = await Future.wait([
      _load('$dir/peg.png'),
      _load('$dir/peg_hit.png'),
      _load('$dir/ball_low.png'),
      _load('$dir/ball_medium.png'),
      _load('$dir/ball_high.png'),
      _load('$dir/slot_flash.png'),
      for (var i = 1; i <= 7; i++) _load('$dir/slot_$i.png'),
    ]);

    return _PlinkoArt(
      peg: results[0],
      pegHit: results[1],
      ballLow: results[2],
      ballMedium: results[3],
      ballHigh: results[4],
      flash: results[5],
      slots: results.sublist(6),
    );
  }
}

/// بلينكو — Plinko.
///
/// The server settles every drop before the ball moves: it returns the peg-by-peg
/// path, the landing slot and the payout, and this screen replays that path. The
/// animation is therefore decorative — it can never change where a ball lands.
///
/// Rendering is deliberately split: the frame loop mutates [PlinkoBoardModel]
/// and the painter subscribes to the ticker, so animating a ball never rebuilds
/// the widget tree. `setState` fires only when something a widget shows actually
/// changes — balance, history, the banner.
class PlinkoScreen extends StatefulWidget {
  const PlinkoScreen({super.key});

  @override
  State<PlinkoScreen> createState() => _PlinkoScreenState();
}

class _PlinkoScreenState extends State<PlinkoScreen>
    with SingleTickerProviderStateMixin {
  final _repo = PlinkoRepository();
  final _sfx = PlinkoSfx();
  final _random = math.Random();
  final _model = PlinkoBoardModel();

  late final AnimationController _ticker;

  PlinkoLayout? _layout;
  int _balance = 0;
  List<PlinkoDrop> _history = const [];

  String _risk = 'medium';
  int _rows = 16;
  int _bet = 100;

  bool _loading = true;
  String? _error;
  bool _muted = false;

  Duration? _shakeStartedAt;
  double _shakePower = 0;

  _WinBanner? _banner;
  _PlinkoArt _art = const _PlinkoArt();
  PlinkoGlow? _glow;

  /// Balance is animated toward the server value rather than snapped.
  int _shownBalance = 0;

  bool _autoBetting = false;
  int _autoRemaining = 0;

  @override
  void initState() {
    super.initState();
    _PlinkoArt.load().then((art) {
      if (mounted) setState(() => _art = art);
    });
    PlinkoGlow.create().then((glow) {
      if (mounted) setState(() => _glow = glow);
    });
    _ticker =
        AnimationController(vsync: this, duration: const Duration(days: 1))
          ..repeat();
    _ticker.addListener(_onTick);
    _load();
  }

  @override
  void dispose() {
    _ticker.removeListener(_onTick);
    _ticker.dispose();
    _sfx.dispose();
    super.dispose();
  }

  Duration get _now => _ticker.lastElapsedDuration ?? Duration.zero;

  // ── Frame loop ─────────────────────────────────────────────────────────────

  void _onTick() {
    final now = _now;
    _model.now = now;
    _model.quality.sample(now);

    final geometry = _model.geometry;
    var needsWidgetRebuild = false;

    // Advance every ball: solve its frame once here, so the painter only draws.
    if (geometry != null && _model.balls.isNotEmpty) {
      for (final ball in List<PlinkoBall>.from(_model.balls)) {
        // Solve the path the first time geometry is available for this ball.
        if (ball.trajectory == null) {
          ball.solve(PlinkoTrajectory.build(
            drop: ball.drop,
            geometry: geometry,
            random: _random,
          ));
        }

        final seconds = (now - ball.startedAt).inMicroseconds / 1e6;
        final progress =
            (seconds / (ball.duration.inMicroseconds / 1e6)).clamp(0.0, 1.0);

        final frame = ball.simulatedFrame(seconds) ??
            ball.frameAt(
              progress,
              geometry.peg,
              geometry.slot,
              geometry.spacing,
            );
        ball.observe(frame, now);

        // A fresh arc that launches from a peg is a contact: tick and flare.
        if (frame.pegRow > ball.lastPegRow && frame.pegRow >= 0) {
          var index = 0;
          for (var i = 0;
              i < frame.pegRow && i < ball.drop.directions.length;
              i++) {
            index += ball.drop.directions[i];
          }
          ball.lastPegRow = frame.pegRow;
          final flat = PlinkoBoardModel.pegIndex(frame.pegRow, index);
          if (flat < _model.pegStruck.length) {
            _model.pegStruck[flat] = now.inMilliseconds.toDouble();
          }
          _sfx.peg(frame.pegRow, ball.drop.rows);
        }

        if (progress >= 1.0) {
          _land(ball, now, geometry);
          needsWidgetRebuild = true;
        }
      }
    }

    _updateAnticipation();

    _model.particles.removeWhere((p) => p.ageAt(now) >= 1.0);
    _model.shake = _shakeOffset(now);

    if (_shakeStartedAt != null &&
        now - _shakeStartedAt! > const Duration(milliseconds: 450)) {
      _shakeStartedAt = null;
      _shakePower = 0;
    }

    if (_banner != null &&
        now - _banner!.bornAt > const Duration(milliseconds: 1700)) {
      _banner = null;
      needsWidgetRebuild = true;
    }

    // Ease the displayed balance toward the real one.
    if (_shownBalance != _balance) {
      final delta = _balance - _shownBalance;
      final step = delta.abs() < 3 ? delta : (delta / 6).round();
      _shownBalance += step == 0 ? delta.sign : step;
      needsWidgetRebuild = true;
    }

    // The board repaints off the ticker on its own; only rebuild widgets when
    // widget-visible state actually changed.
    if (needsWidgetRebuild && mounted) setState(() {});
  }

  /// Pulse the slots a ball can still reach once it is near the bottom.
  void _updateAnticipation() {
    _model.anticipated.clear();
    for (final ball in _model.balls) {
      final frame = ball.frame;
      if (frame == null) continue;
      final remaining = ball.drop.rows - frame.pegRow;
      // Only in the closing rows, or every drop would light the whole row.
      if (remaining > 4 || remaining < 0) continue;
      final (lo, hi) = ball.reachableSlots(frame.pegRow);
      for (var s = lo; s <= hi; s++) {
        _model.anticipated.add(s);
      }
    }
  }

  void _land(PlinkoBall ball, Duration now, PlinkoLayoutGeometry geometry) {
    _model.balls.remove(ball);

    final drop = ball.drop;
    if (drop.slot < _model.slotFlashed.length) {
      _model.slotFlashed[drop.slot] = now.inMilliseconds.toDouble();
    }
    _sfx.landed(drop.multiplier);

    _model.particles.addAll(PlinkoParticle.burst(
      at: geometry.slot(drop.slot),
      now: now,
      color: _slotColor(drop.multiplier),
      multiplier: drop.multiplier,
      random: _random,
      scale: _model.quality.particleScale,
    ));

    if (drop.multiplier >= 10) {
      HapticFeedback.heavyImpact();
      _shakeStartedAt = now;
      _shakePower = drop.multiplier >= 100 ? 9 : 5;
    } else if (drop.multiplier >= 1) {
      HapticFeedback.selectionClick();
    }

    if (drop.payout > 0) {
      _banner = _WinBanner(
        bornAt: now,
        payout: drop.payout,
        multiplier: drop.multiplier,
      );
    }

    _history = [drop, ..._history].take(30).toList();
  }

  Offset _shakeOffset(Duration now) {
    final started = _shakeStartedAt;
    if (started == null) return Offset.zero;
    final t = (now - started).inMilliseconds / 450.0;
    if (t >= 1) return Offset.zero;
    final decay = (1 - t) * _shakePower;
    return Offset(
      math.sin(t * math.pi * 14) * decay,
      math.cos(t * math.pi * 11) * decay * 0.6,
    );
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _layout = state.layout;
        _balance = state.balance;
        _shownBalance = state.balance;
        _history = state.history;
        _rows = _rows.clamp(state.layout.minRows, state.layout.maxRows);
        _bet = _bet.clamp(state.layout.minBet, state.layout.maxBet);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _drop() async {
    if (_layout == null) return;

    if (_bet > _balance) {
      _toast('رصيدك لا يكفي');
      _stopAuto();
      return;
    }

    _sfx.drop();
    HapticFeedback.selectionClick();
    try {
      final result = await _repo.drop(risk: _risk, rows: _rows, amount: _bet);
      if (!mounted) return;
      _model.balls.add(PlinkoBall(
        drop: result.drop,
        startedAt: _now,
        risk: _risk,
      ));
      setState(() => _balance = result.balance);
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString());
      _stopAuto();
    }
  }

  Future<void> _runAuto(int count) async {
    setState(() {
      _autoBetting = true;
      _autoRemaining = count;
    });

    while (mounted && _autoBetting && _autoRemaining > 0) {
      await _drop();
      if (!mounted || !_autoBetting) break;
      setState(() => _autoRemaining--);
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }

    if (mounted) _stopAuto();
  }

  void _stopAuto() {
    if (!mounted) return;
    setState(() {
      _autoBetting = false;
      _autoRemaining = 0;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: const Color(0xFF3A0A16),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07030F),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text('بلينكو',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              onPressed: () => setState(() {
                _muted = !_muted;
                _sfx.enabled = !_muted;
              }),
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white70, size: 20),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(children: [
                Text('$_shownBalance',
                    style: const TextStyle(
                        color: Color(0xFFFFC107),
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(width: 4),
                const Text('🪙', style: TextStyle(fontSize: 16)),
              ]),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC107)))
            : _error != null
                ? _errorView()
                : _body(),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ]),
      );

  Widget _body() {
    final layout = _layout!;
    final multipliers = layout.multipliers(_risk, _rows);

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [Color(0xFF1B0B3A), Color(0xFF07030F)],
        ),
        image: DecorationImage(
          image: AssetImage('assets/images/plinko/bg_board.png'),
          fit: BoxFit.cover,
          opacity: 0.55,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(children: [
          _historyBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Stack(children: [
                // RepaintBoundary keeps the board's per-frame repaint from
                // dirtying the panel and history bar above it.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _PlinkoPainter(
                        repaint: _ticker,
                        model: _model,
                        rows: _rows,
                        multipliers: multipliers,
                        art: _art,
                        glow: _glow,
                      ),
                      isComplex: true,
                      willChange: true,
                    ),
                  ),
                ),
                if (_banner != null) _bannerView(_banner!),
              ]),
            ),
          ),
          _bettingPanel(layout),
        ]),
      ),
    );
  }

  Widget _bannerView(_WinBanner banner) {
    final t = ((_now - banner.bornAt).inMilliseconds / 1700.0).clamp(0.0, 1.0);
    final scale = t < 0.16 ? 0.6 + 0.4 * (t / 0.16) : 1.0;
    final opacity = t > 0.72 ? (1 - (t - 0.72) / 0.28) : 1.0;
    final rise = t > 0.5 ? (t - 0.5) * 46 : 0.0;
    final color = _slotColor(banner.multiplier);

    return Positioned(
      top: 40 - rise,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Column(children: [
              Text(
                '${_fmt(banner.multiplier)}x',
                style: TextStyle(
                  color: color,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: color.withValues(alpha: 0.8), blurRadius: 22),
                    const Shadow(color: Colors.black, blurRadius: 6),
                  ],
                ),
              ),
              Text(
                '+${banner.payout} 🪙',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _historyBar() {
    if (_history.isEmpty) return const SizedBox(height: 34);
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final drop = _history[i];
          final color = _slotColor(drop.multiplier);
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Text('${_fmt(drop.multiplier)}x',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          );
        },
      ),
    );
  }

  Widget _bettingPanel(PlinkoLayout layout) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF120A26).withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _stepper('½', () => _setBet((_bet / 2).round(), layout)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text('$_bet 🪙',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
          _stepper('2×', () => _setBet(_bet * 2, layout)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _riskPicker()),
          const SizedBox(width: 10),
          Expanded(child: _rowsPicker(layout)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: _artButton(
              asset: 'assets/images/plinko/btn_drop.png',
              label: 'أسقط الكرة',
              fallback: const Color(0xFF00E676),
              enabled: !_autoBetting,
              onTap: _drop,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _artButton(
              asset: 'assets/images/plinko/btn_auto.png',
              label: _autoBetting ? 'إيقاف ($_autoRemaining)' : 'تلقائي',
              fallback: const Color(0xFF6B21A8),
              enabled: true,
              onTap: () {
                _sfx.click();
                _autoBetting ? _stopAuto() : _openAutoSheet();
              },
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _artButton({
    required String asset,
    required String label,
    required Color fallback,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 52,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: Image.asset(
                asset,
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: fallback,
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                shadows: [
                  Shadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 1)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stepper(String label, VoidCallback onTap) => SizedBox(
        width: 52,
        height: 42,
        child: OutlinedButton(
          onPressed: () {
            _sfx.click();
            onTap();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            side: const BorderSide(color: Colors.white24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );

  void _setBet(int value, PlinkoLayout layout) {
    setState(() => _bet = value.clamp(layout.minBet, layout.maxBet));
  }

  Widget _riskPicker() {
    const options = [
      ('low', '🛡️', Color(0xFF00E676)),
      ('medium', '⚖️', Color(0xFFFFC107)),
      ('high', '🔥', Color(0xFFFF5252)),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: options.map((o) {
          final selected = _risk == o.$1;
          return Expanded(
            child: GestureDetector(
              onTap: _autoBetting
                  ? null
                  : () {
                      _sfx.click();
                      setState(() => _risk = o.$1);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? o.$3.withValues(alpha: 0.25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: selected ? o.$3 : Colors.transparent, width: 1),
                ),
                child: Image.asset(
                  'assets/images/plinko/risk_${o.$1}.png',
                  height: 26,
                  opacity: AlwaysStoppedAnimation(selected ? 1.0 : 0.4),
                  errorBuilder: (_, __, ___) =>
                      Text(o.$2, style: const TextStyle(fontSize: 15)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _rowsPicker(PlinkoLayout layout) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          Text('$_rows صف',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFFFFC107),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFFFC107),
              ),
              child: Slider(
                value: _rows.toDouble(),
                min: layout.minRows.toDouble(),
                max: layout.maxRows.toDouble(),
                divisions: layout.maxRows - layout.minRows,
                onChanged: _autoBetting || _model.balls.isNotEmpty
                    ? null
                    : (v) => setState(() => _rows = v.round()),
              ),
            ),
          ),
        ]),
      );

  void _openAutoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF120A26),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('عدد الكرات',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [5, 10, 25, 50, 100].map((n) {
                return SizedBox(
                  width: 74,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _runAuto(n);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B21A8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('$n'),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }
}

class _WinBanner {
  const _WinBanner({
    required this.bornAt,
    required this.payout,
    required this.multiplier,
  });

  final Duration bornAt;
  final int payout;
  final double multiplier;
}

// ─────────────────────────────────────────────────────────────────────────────
// Rendering
// ─────────────────────────────────────────────────────────────────────────────

Color _slotColor(double multiplier) {
  if (multiplier >= 100) return const Color(0xFFB71C1C);
  if (multiplier >= 25) return const Color(0xFFE53935);
  if (multiplier >= 9) return const Color(0xFFFF7043);
  if (multiplier >= 3) return const Color(0xFFFFA726);
  if (multiplier >= 1.1) return const Color(0xFFFFD54F);
  if (multiplier >= 1) return const Color(0xFFDCE775);
  return const Color(0xFF8BC34A);
}

String _fmt(double m) => m >= 10
    ? m.toStringAsFixed(0)
    : m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1);

class _PlinkoPainter extends CustomPainter {
  _PlinkoPainter({
    required Listenable repaint,
    required this.model,
    required this.rows,
    required this.multipliers,
    required this.art,
    required this.glow,
  }) : super(repaint: repaint);

  final PlinkoBoardModel model;
  final int rows;
  final List<double> multipliers;
  final _PlinkoArt art;
  final PlinkoGlow? glow;

  static const _slotFlashMs = 550.0;
  static const _pegFlashMs = 300.0;

  // Reused across frames — allocating these per paint is pure garbage.
  static final _pegAtlas = AtlasBuffer();
  static final _shadowAtlas = AtlasBuffer();
  static final _particleAtlas = AtlasBuffer();

  /// The board's furniture — vignette, rails, the peg field — does not change
  /// between drops. Recording it once and replaying the picture turns several
  /// hundred draw calls per frame into one.
  static ui.Picture? _staticLayer;
  static String? _staticKey;
  static final _spritePaint = Paint()..filterQuality = FilterQuality.low;
  static final _additive = Paint()
    ..filterQuality = FilterQuality.low
    ..blendMode = BlendMode.plus;

  @override
  void paint(Canvas canvas, Size size) {
    final slotHeight = math.min(34.0, size.height * 0.09);
    final boardHeight = size.height - slotHeight - 10;
    final spacing = math.min(size.width / (rows + 2), boardHeight / (rows + 1));
    final centerX = size.width / 2;
    final slotCount = multipliers.length;

    final geometry = PlinkoLayoutGeometry(
      rows: rows,
      slotCount: slotCount,
      spacing: spacing,
      centerX: centerX,
      topY: (boardHeight - spacing * rows) / 2 + spacing * 0.5,
      slotY: size.height - slotHeight,
      slotHeight: slotHeight,
      size: size,
    );
    model.geometry = geometry;
    model.ensureCapacity(rows, slotCount);

    final shake = model.shake;
    canvas.save();
    if (shake != Offset.zero) canvas.translate(shake.dx, shake.dy);

    canvas.drawPicture(_staticFor(size, geometry));
    // Balls sit behind the peg field: it reads as the ball travelling *through*
    // the board rather than skating across a flat picture of it.
    _paintBalls(canvas, geometry);
    _paintPegFlashes(canvas, geometry);
    _paintSlots(canvas, geometry);
    _paintParticles(canvas);

    canvas.restore();
  }

  /// Darkened surround so the peg field reads as recessed.
  void _paintVignette(Canvas canvas, Size size, PlinkoLayoutGeometry g) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 1.0,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.55),
          ],
          stops: const [0.45, 1.0],
        ).createShader(rect),
    );
  }

  /// Angled side rails and a base plate, framing the triangle.
  void _paintRails(Canvas canvas, Size size, PlinkoLayoutGeometry g) {
    final apex = g.peg(0, 0);
    final leftFoot = g.peg(rows - 1, 0);
    final rightFoot = g.peg(rows - 1, rows - 1);
    final pad = g.spacing * 0.95;

    for (final (from, to) in [
      (
        Offset(apex.dx - pad * 0.5, apex.dy - pad),
        Offset(leftFoot.dx - pad, leftFoot.dy + pad)
      ),
      (
        Offset(apex.dx + pad * 0.5, apex.dy - pad),
        Offset(rightFoot.dx + pad, rightFoot.dy + pad)
      ),
    ]) {
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = math.max(2.0, g.spacing * 0.16)
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(from, to, const [
            Color(0xFF00E5FF),
            Color(0xFF7C4DFF),
            Color(0xFFFF4081),
          ]),
      );
    }
  }

  /// Records (or reuses) the static furniture for this geometry.
  ui.Picture _staticFor(Size size, PlinkoLayoutGeometry g) {
    final key = '${size.width}x${size.height}:$rows:'
        '${art.peg.hashCode}:${model.quality.shadowsEnabled}';
    final cached = _staticLayer;
    if (cached != null && _staticKey == key) return cached;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintVignette(canvas, size, g);
    _paintRails(canvas, size, g);
    _paintPegs(canvas, g);
    final picture = recorder.endRecording();

    _staticLayer = picture;
    _staticKey = key;
    return picture;
  }

  void _paintPegs(Canvas canvas, PlinkoLayoutGeometry g) {
    final sprite = art.peg;
    final radius = math.max(2.0, g.spacing * 0.085);

    if (sprite == null) {
      final plain = Paint()..color = Colors.white.withValues(alpha: 0.92);
      for (var r = 0; r < rows; r++) {
        for (var i = 0; i <= r; i++) {
          canvas.drawCircle(g.peg(r, i), radius, plain);
        }
      }
      return;
    }

    final count = rows * (rows + 1) ~/ 2;
    _pegAtlas.reset(count);
    _shadowAtlas.reset(count);

    final target = radius * 5.2;
    final scale = target / sprite.width;
    final drop = math.max(1.0, g.spacing * 0.07);
    final shadows = model.quality.shadowsEnabled;

    for (var r = 0; r < rows; r++) {
      for (var i = 0; i <= r; i++) {
        final p = g.peg(r, i);
        if (shadows) {
          _shadowAtlas.add(sprite, p.translate(drop * 0.5, drop), scale,
              color: const Color(0x66000000));
        }
        _pegAtlas.add(sprite, p, scale);
      }
    }

    _shadowAtlas.flush(canvas, sprite, _spritePaint);
    _pegAtlas.flush(canvas, sprite, _spritePaint);
  }

  /// Struck pegs only — the rest live in the cached static layer.
  void _paintPegFlashes(Canvas canvas, PlinkoLayoutGeometry g) {
    final radius = math.max(2.0, g.spacing * 0.085);
    final target = radius * 5.2;
    final nowMs = model.now.inMilliseconds.toDouble();
    final hit = art.pegHit;
    for (var r = 0; r < rows; r++) {
      for (var i = 0; i <= r; i++) {
        final flat = PlinkoBoardModel.pegIndex(r, i);
        if (flat >= model.pegStruck.length) continue;
        final t = (nowMs - model.pegStruck[flat]) / _pegFlashMs;
        if (t < 0 || t > 1) continue;

        final p = g.peg(r, i);
        final fade = 1 - t;
        if (hit != null) {
          final s = (target * (1 + t * 0.9)) / hit.width;
          canvas.drawImageRect(
            hit,
            Rect.fromLTWH(0, 0, hit.width.toDouble(), hit.height.toDouble()),
            Rect.fromCenter(
              center: p,
              width: hit.width * s,
              height: hit.height * s,
            ),
            _additive..color = Colors.white.withValues(alpha: fade),
          );
        }
        canvas.drawCircle(
          p,
          radius * (1.4 + t * 3.4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.7, radius * 0.34 * fade)
            ..color = Colors.white.withValues(alpha: 0.5 * fade),
        );
      }
    }
  }

  void _paintSlots(Canvas canvas, PlinkoLayoutGeometry g) {
    final count = multipliers.length;
    final width = math.min(g.spacing * 0.94, g.size.width / count - 2);
    final nowMs = model.now.inMilliseconds.toDouble();
    // One shared pulse so anticipating slots blink in unison.
    final pulse = 0.5 + 0.5 * math.sin(nowMs / 90.0);

    for (var i = 0; i < count; i++) {
      final multiplier = multipliers[i];
      final color = _slotColor(multiplier);

      var flash = 0.0;
      if (i < model.slotFlashed.length) {
        final t = (nowMs - model.slotFlashed[i]) / _slotFlashMs;
        if (t >= 0 && t <= 1) flash = 1 - t;
      }

      final punch =
          flash > 0 ? math.sin(flash * math.pi) * g.slotHeight * 0.22 : 0.0;
      final centre = g.slot(i).translate(0, punch);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: width, height: g.slotHeight),
        const Radius.circular(6),
      );

      // Anticipation: the slots still in play glow before the ball arrives.
      if (model.anticipated.contains(i) && flash == 0) {
        canvas.drawRRect(
          rect.inflate(3 + 2 * pulse),
          Paint()..color = color.withValues(alpha: 0.18 + 0.22 * pulse),
        );
      }

      if (flash > 0) {
        final burst = art.flash;
        if (burst != null) {
          final s = (width * 3.0) / burst.width;
          canvas.drawImageRect(
            burst,
            Rect.fromLTWH(
                0, 0, burst.width.toDouble(), burst.height.toDouble()),
            Rect.fromCenter(
                center: centre,
                width: burst.width * s,
                height: burst.height * s),
            _additive..color = Colors.white.withValues(alpha: flash),
          );
        }
        canvas.drawRRect(
          rect.inflate(4 * flash),
          Paint()..color = color.withValues(alpha: 0.45 * flash),
        );
      }

      final tile = art.slotFor(multiplier);
      if (tile != null) {
        canvas.drawImageRect(
          tile,
          Rect.fromLTWH(0, 0, tile.width.toDouble(), tile.height.toDouble()),
          rect.outerRect,
          _spritePaint
            ..blendMode = BlendMode.srcOver
            ..color = Colors.white.withValues(alpha: 0.92 + 0.08 * flash),
        );
      } else {
        canvas.drawRRect(rect,
            Paint()..color = color.withValues(alpha: 0.85 + 0.15 * flash));
      }

      final label = TextPainter(
        text: TextSpan(
          text: '${_fmt(multiplier)}x',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontSize: math.max(7.0, width * 0.32),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      label.paint(canvas, centre - Offset(label.width / 2, label.height / 2));
    }
  }

  void _paintBalls(Canvas canvas, PlinkoLayoutGeometry g) {
    final radius = math.max(3.0, g.spacing * 0.3);
    final halo = glow?.halo;
    final total = model.balls.length;

    for (var b = 0; b < total; b++) {
      final ball = model.balls[b];
      final frame = ball.frame;
      if (frame == null) continue;

      // With many balls in flight the newest stays brightest so the eye can
      // follow one ball instead of a swarm.
      final freshness = total <= 1 ? 1.0 : 0.55 + 0.45 * (b / (total - 1));

      // Additive halo — cheap bloom without a full-screen shader pass.
      if (halo != null && model.quality.halosEnabled) {
        final s = (radius * 7.0) / halo.width;
        canvas.drawImageRect(
          halo,
          Rect.fromLTWH(0, 0, halo.width.toDouble(), halo.height.toDouble()),
          Rect.fromCenter(
              center: frame.position,
              width: halo.width * s,
              height: halo.height * s),
          _additive..color = ball.color.withValues(alpha: 0.34 * freshness),
        );
      }

      final trailLength =
          model.quality.trailsEnabled ? ball.trail.length - 1 : 0;
      for (var i = 0; i < trailLength; i++) {
        final k = i / ball.trail.length;
        canvas.drawCircle(
          ball.trail[i],
          radius * (0.3 + k * 0.55),
          Paint()
            ..color =
                ball.color.withValues(alpha: (0.07 + k * 0.15) * freshness),
        );
      }

      // Motion blur: stretch along the velocity vector. Capped so a fast ball
      // smears rather than turning into a streak across the board.
      final speed =
          frame.position == Offset.zero ? 0.0 : ball.velocity.distance;
      final stretch = (1 + speed / 2600).clamp(1.0, 1.85);
      final angle = ball.velocity.distance < 1
          ? 0.0
          : math.atan2(ball.velocity.dy, ball.velocity.dx) - math.pi / 2;

      canvas.save();
      canvas.translate(frame.position.dx, frame.position.dy);
      canvas.rotate(angle);
      canvas.scale(1 / math.sqrt(stretch), stretch);
      canvas.rotate(frame.rotation - angle);
      canvas.scale(frame.aspect * frame.verticalScale, frame.verticalScale);

      final sprite = art.ballFor(ball.risk);
      if (sprite != null) {
        final s = (radius * 3.6) / sprite.width;
        canvas.drawImageRect(
          sprite,
          Rect.fromLTWH(
              0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
          Rect.fromCenter(
              center: Offset.zero,
              width: sprite.width * s,
              height: sprite.height * s),
          _spritePaint
            ..blendMode = BlendMode.srcOver
            ..color = Colors.white.withValues(alpha: freshness),
        );
      } else {
        canvas.drawCircle(Offset.zero, radius, Paint()..color = ball.color);
      }
      canvas.restore();
    }
  }

  void _paintParticles(Canvas canvas) {
    final sprite = glow?.dot;
    final particles = model.particles;
    if (particles.isEmpty) return;

    if (sprite == null) {
      for (final p in particles) {
        final fade = 1 - p.ageAt(model.now);
        canvas.drawCircle(p.positionAt(model.now), p.size,
            Paint()..color = p.color.withValues(alpha: fade));
      }
      return;
    }

    // Every spark in a single batched, additively-blended call.
    _particleAtlas.reset(particles.length);
    for (final p in particles) {
      final age = p.ageAt(model.now);
      if (age >= 1) continue;
      final fade = 1 - age;
      _particleAtlas.add(
        sprite,
        p.positionAt(model.now),
        (p.size * (1.6 + fade * 2.2)) / sprite.width,
        color: p.color.withValues(alpha: fade),
      );
    }
    _particleAtlas.flush(canvas, sprite, _additive, blend: BlendMode.modulate);
  }

  @override
  bool shouldRepaint(_PlinkoPainter old) =>
      old.rows != rows ||
      old.art != art ||
      old.glow != glow ||
      !identical(old.multipliers, multipliers);
}

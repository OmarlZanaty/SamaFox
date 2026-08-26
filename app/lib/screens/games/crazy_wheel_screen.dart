import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/crazy_wheel_repository.dart';
import '../../services/socket_service.dart';
import 'crazy_wheel_bonus.dart';

/// عجلة الحظ — Crazy Wheel.
///
/// A 54-segment live wheel in the Crazy Time format: you place chips on any of
/// the eight spots (1, 2, 5, 10 and the four bonus games) during the betting
/// window, a Top Slot rolls a spot + multiplier alongside the spin, and landing
/// on a bonus segment opens that bonus round.
///
/// Everything that decides an outcome or moves coins is server-side
/// (backend/src/services/crazyWheel.service.ts). This screen places bets over
/// REST, listens to `crazy_state` for the shared round, and animates the result
/// the server already rolled — it never decides where the wheel stops.
class CrazyWheelScreen extends ConsumerStatefulWidget {
  const CrazyWheelScreen({super.key});

  @override
  ConsumerState<CrazyWheelScreen> createState() => _CrazyWheelScreenState();
}

class _CrazyWheelScreenState extends ConsumerState<CrazyWheelScreen>
    with TickerProviderStateMixin {
  static const _bgTop = Color(0xFF2A0A3E);
  static const _bgBottom = Color(0xFF0D0620);
  static const _gold = Color(0xFFFFD54F);

  /// Must match SPINNING_MS in the service, so the wheel comes to rest exactly
  /// as the server flips the phase.
  static const _spinDuration = Duration(milliseconds: 9000);

  static const Map<String, Color> _segmentColors = {
    '1': Color(0xFF1E88E5),
    '2': Color(0xFFFDD835),
    '5': Color(0xFFEC407A),
    '10': Color(0xFF8E24AA),
    'coinflip': Color(0xFFE53935),
    'cashhunt': Color(0xFF2E7D32),
    'pachinko': Color(0xFFD81B60),
    'crazytime': Color(0xFFC62828),
  };

  static const Map<String, String> _segmentLabels = {
    '1': '1',
    '2': '2',
    '5': '5',
    '10': '10',
    'coinflip': 'CF',
    'cashhunt': 'CH',
    'pachinko': 'PK',
    'crazytime': 'CT',
  };

  static const Map<String, String> _spotNames = {
    '1': '١',
    '2': '٢',
    '5': '٥',
    '10': '١٠',
    'coinflip': 'قلب العملة',
    'cashhunt': 'صيد النقود',
    'pachinko': 'باتشينكو',
    'crazytime': 'الوقت المجنون',
  };

  static const Map<String, String> _spotEmoji = {
    '1': '1️⃣',
    '2': '2️⃣',
    '5': '5️⃣',
    '10': '🔟',
    'coinflip': '🪙',
    'cashhunt': '🎯',
    'pachinko': '📍',
    'crazytime': '🌀',
  };

  /// Commissioned bonus icons. Coin Flip has no artwork yet, so it keeps the
  /// emoji — every lookup here falls back to `_spotEmoji`.
  static const Map<String, String> _spotArt = {
    'cashhunt': 'assets/images/crazy/icon_cashhunt.png',
    'pachinko': 'assets/images/crazy/icon_pachinko.png',
    'crazytime': 'assets/images/crazy/icon_crazytime.png',
  };

  /// Sliced out of the supplied chips sheet, one file per tier.
  static const Map<int, String> _chipArt = {
    1000: 'assets/images/crazy/chip_1k.png',
    5000: 'assets/images/crazy/chip_5k.png',
    10000: 'assets/images/crazy/chip_10k.png',
    50000: 'assets/images/crazy/chip_50k.png',
    100000: 'assets/images/crazy/chip_100k.png',
  };

  static const _wheelArtPath = 'assets/images/crazy/wheel.png';
  static const _flapperArtPath = 'assets/images/crazy/flapper.png';
  static const _studioArtPath = 'assets/images/crazy/bg_studio.png';
  static const _topSlotArtPath = 'assets/images/crazy/topslot_frame.png';

  /// Where the artwork's own parts sit, as a fraction of the drawn disc radius.
  /// Measured off wheel.png: the gold rim and pins live outside `_artBandOuter`
  /// and the hub inside `_artBandInner`, so the 54 live segments are painted
  /// into the band between them. The artwork's own segments (about 30 of them)
  /// are covered — using them directly would land the flapper on a colour that
  /// disagrees with the result the server rolled.
  static const _artBandInner = 0.50;
  static const _artBandOuter = 0.93;

  final CrazyWheelRepository _repo = CrazyWheelRepository();
  final SocketService _socket = SocketService();

  late final AnimationController _spin =
      AnimationController(vsync: this, duration: _spinDuration);
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  /// The wheel chrome, decoded once. Null until it loads (and stays null if the
  /// asset is missing), in which case the painter falls back to its own rim.
  ui.Image? _wheelArt;

  CrazyState? _state;
  CrazyLayout? _layout;
  int _balance = 0;
  int _chip = 1000;
  String? _notice;
  bool _busy = false;

  /// Wheel rotation in turns; animated from here to `_spinTarget`.
  double _spinFrom = 0;
  double _spinTarget = 0;
  int _animatedRound = 0;

  Timer? _countdown;
  int _msLeft = 0;

  @override
  void initState() {
    super.initState();
    _spin.addListener(() => setState(() {}));
    _socket.on('crazy_state', _onState);
    _socket.on('crazy_result', _onResult);
    _socket.emit('crazy_join_table', {});
    _loadWheelArt();
    _load();
    _countdown = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _msLeft = max(0, _msLeft - 200));
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _socket.off('crazy_state');
    _socket.off('crazy_result');
    _socket.emit('crazy_leave_table', {});
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// The painter needs a raw `ui.Image` (it composites the chrome under the
  /// live segments), so this cannot go through `Image.asset`.
  Future<void> _loadWheelArt() async {
    try {
      final data = await rootBundle.load(_wheelArtPath);
      final frame =
          await (await ui.instantiateImageCodec(data.buffer.asUint8List()))
              .getNextFrame();
      if (!mounted) return;
      setState(() => _wheelArt = frame.image);
    } catch (_) {
      // Missing or unreadable artwork just means the painted fallback rim.
    }
  }

  Future<void> _load() async {
    try {
      final res = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _layout = res.layout ?? _layout;
        _balance = res.balance;
        if (res.state != null) _apply(res.state!);
      });
    } on CrazyWheelException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  void _onState(dynamic raw) {
    if (!mounted || raw is! Map) return;
    setState(() => _apply(CrazyState.fromJson(Map<String, dynamic>.from(raw))
        .withMineFrom(_state)));
  }

  void _onResult(dynamic raw) {
    // The payout arrives with the result broadcast; re-pull the balance rather
    // than trying to reconstruct it locally.
    _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    try {
      final res = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _balance = res.balance;
        if (res.state != null) _apply(res.state!);
      });
    } catch (_) {
      // A failed refresh is cosmetic — the next state tick will correct it.
    }
  }

  void _apply(CrazyState state) {
    _state = state;
    _msLeft = state.msLeft;

    // Start the spin exactly once per round, the moment the server publishes
    // the winning index.
    if (state.isSpinning &&
        state.resultIndex != null &&
        _animatedRound != state.roundId) {
      _animatedRound = state.roundId;
      _startSpin(state.resultIndex!);
    }
  }

  void _startSpin(int resultIndex) {
    final wheel = _layout?.wheel ?? const [];
    if (wheel.isEmpty) return;

    // Bring the winning segment's centre under the flapper at 12 o'clock, plus
    // several full turns for the run-up.
    final slice = 1 / wheel.length;
    final landing = -((resultIndex + 0.5) * slice);
    _spinFrom = _spinTarget % 1;
    _spinTarget = _spinFrom.floorToDouble() + 6 + landing;
    _spin.forward(from: 0);
  }

  double get _rotation {
    final t = Curves.easeOutQuart.transform(_spin.value);
    return _spinFrom + (_spinTarget - _spinFrom) * t;
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _bet(String segment) async {
    if (_busy || _state?.isBetting != true) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final res = await _repo.placeBet(segment: segment, amount: _chip);
      if (!mounted) return;
      setState(() {
        _balance = res.balance;
        _state = _stateWithBets(res.bets);
      });
    } on CrazyWheelException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async => _betAction(() => _repo.clearBets());
  Future<void> _repeat() async => _betAction(() => _repo.repeatBets());

  Future<void> _betAction(Future<CrazyBetResult> Function() action) async {
    if (_busy || _state?.isBetting != true) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final res = await action();
      if (!mounted) return;
      setState(() {
        _balance = res.balance;
        _state = _stateWithBets(res.bets);
      });
    } on CrazyWheelException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(Object pick) async {
    try {
      await _repo.submitPick(pick);
      if (!mounted) return;
      setState(() => _state = _stateWithPick(pick));
    } on CrazyWheelException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  CrazyState? _stateWithBets(Map<String, int> bets) {
    final s = _state;
    if (s == null) return null;
    return _copy(s, bets: bets);
  }

  CrazyState? _stateWithPick(Object pick) {
    final s = _state;
    if (s == null) return null;
    return _copy(s, pick: pick);
  }

  CrazyState _copy(CrazyState s, {Map<String, int>? bets, Object? pick}) =>
      CrazyState(
        phase: s.phase,
        roundId: s.roundId,
        msLeft: s.msLeft,
        resultIndex: s.resultIndex,
        resultSegment: s.resultSegment,
        topSlot: s.topSlot,
        bonusKind: s.bonusKind,
        bonus: s.bonus,
        totals: s.totals,
        myBets: bets ?? s.myBets,
        myPick: pick ?? s.myPick,
        myPayout: s.myPayout,
        myMultiplier: s.myMultiplier,
        playerCount: s.playerCount,
        history: s.history,
        chipTiers: s.chipTiers,
      );

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = _state;
    final chips =
        _layout?.chipTiers ?? const [1000, 5000, 10000, 50000, 100000];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgBottom,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('عجلة الحظ',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('🪙 ${_format(_balance)}',
                    style: const TextStyle(
                        color: _gold, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Studio backdrop, dimmed hard so the wheel and the bet chips stay
            // the brightest things on screen.
            Image.asset(
              _studioArtPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // The studio render is already dark, so this only needs to be
                  // heavy enough to keep the betting grid legible at the bottom.
                  colors: [
                    _bgTop.withOpacity(0.35),
                    _bgBottom.withOpacity(0.80)
                  ],
                ),
              ),
            ),
            SafeArea(
              child: state == null
                  ? const Center(child: CircularProgressIndicator(color: _gold))
                  // The betting grid and the chip rack are the parts a player
                  // has to reach, so they get fixed height at the bottom and
                  // the wheel takes whatever is left. On a short phone the
                  // wheel shrinks; it never pushes the controls off-screen.
                  : Column(
                      children: [
                        _historyBar(state),
                        const SizedBox(height: 4),
                        _topSlot(state),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _wheelStage(state),
                          ),
                        ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(_notice!,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12)),
                          ),
                        // The wheel is cropped right behind this panel, so the
                        // panel needs its own ground to sit on or the two read
                        // as one muddled mass.
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                _bgBottom.withOpacity(0.92)
                              ],
                              stops: const [0, 0.35],
                            ),
                          ),
                          // Betting is closed during a bonus round, so the grid
                          // and the chip rack collapse to a one-line summary and
                          // the bonus game gets the whole stage.
                          child: state.inBonus
                              ? _bonusStakeStrip(state)
                              : Column(
                                  children: [
                                    _bettingGrid(state),
                                    const SizedBox(height: 8),
                                    _chipRow(chips, state),
                                  ],
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

  // History strip of the last rounds.
  Widget _historyBar(CrazyState state) {
    final entries = state.history.reversed.toList();
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final e = entries[i];
          final color = _segmentColors[e.segment] ?? Colors.grey;
          final isBonus = !RegExp(r'^\d+$').hasMatch(e.segment);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
              border: isBonus ? Border.all(color: _gold, width: 1.5) : null,
            ),
            child: Text(
              isBonus && e.multiplier != null
                  ? '${_segmentLabels[e.segment]} x${e.multiplier}'
                  : _segmentLabels[e.segment] ?? '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }

  Widget _topSlot(CrazyState state) {
    final top = state.topSlot;
    final matched = top != null && top.spot == state.resultSegment;

    return SizedBox(
      width: 252,
      // The frame artwork is trimmed to its housing (1448x573); keeping that
      // ratio is what lets the reel text be positioned by fraction and still
      // land inside the glass.
      child: AspectRatio(
        aspectRatio: 1448 / 573,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                // A top-slot hit is the moment worth lighting up.
                boxShadow: matched
                    ? [
                        const BoxShadow(
                            color: _gold, blurRadius: 28, spreadRadius: -8)
                      ]
                    : null,
              ),
            ),
            Image.asset(
              _topSlotArtPath,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            // Left window: the bet spot. Right window: the multiplier.
            _reelWindow(0.073, 0.502,
                top == null ? '؟' : (_segmentLabels[top.spot] ?? ''),
                ltr: top != null),
            _reelWindow(0.507, 0.919, top == null ? '؟' : '×${top.multiplier}',
                ltr: true),
          ],
        ),
      ),
    );
  }

  /// Places text inside one of the frame's two glass windows. `left`/`right`
  /// are fractions of the artwork's width; both windows share the same vertical
  /// extent, so that is baked in here.
  Widget _reelWindow(double left, double right, String text,
      {bool ltr = false}) {
    const top = 0.183;
    const bottom = 0.811;
    final width = right - left;
    const height = bottom - top;
    // FractionallySizedBox places a fractionally-sized child within the leftover
    // space, so the alignment has to be scaled by that leftover.
    final ax = ((left + right) - 1) / (1 - width);
    const ay = ((top + bottom) - 1) / (1 - height);

    return FractionallySizedBox(
      alignment: Alignment(ax, ay),
      widthFactor: width,
      heightFactor: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            child: Text(
              text,
              maxLines: 1,
              textDirection: ltr ? TextDirection.ltr : null,
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.bold,
                fontSize: 30,
                shadows: [Shadow(color: Color(0xFFFF8F00), blurRadius: 14)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sizes the wheel for the space it has been given.
  ///
  /// A phone never has room for a full disc AND the betting grid, and shrinking
  /// the wheel to fit makes the 54 segments unreadable. So the wheel is drawn
  /// large and deliberately cropped: the flapper and the hub — the two things
  /// that matter — stay in view, and the bottom arc tucks behind the panel the
  /// way it does on a real studio floor.
  Widget _wheelStage(CrazyState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        // A bonus round is self-contained, so it gets the space uncropped.
        if (state.inBonus && state.bonus != null) {
          return Center(
            child: SizedBox(
              width: min(constraints.maxWidth, available),
              height: min(constraints.maxWidth, available),
              child: _bonusGame(state),
            ),
          );
        }

        // Full-bleed: the wheel is always as wide as the screen allows, and
        // whatever will not fit vertically is cropped off the bottom. Sizing it
        // to the available height instead would leave a small wheel with dead
        // space either side — the opposite of what this screen is for.
        final diameter = constraints.maxWidth;

        // Park the hub a little below the middle of the visible window: that
        // keeps the countdown whole and the flapper in frame, and spends the
        // crop on the bottom arc, which carries no information.
        double alignY = 0;
        if (diameter > available) {
          final windowStart = (diameter / 2 - available * 0.56)
              .clamp(0.0, diameter - available);
          alignY =
              (-1 + 2 * windowStart / (diameter - available)).clamp(-1.0, 1.0);
        }

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment(0, alignY),
            maxHeight: diameter,
            maxWidth: diameter,
            child: SizedBox(
                width: diameter, height: diameter, child: _wheel(state)),
          ),
        );
      },
    );
  }

  Widget _wheel(CrazyState state) {
    // Always square: `_wheelStage` owns the sizing and the cropping.
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _WheelPainter(
              wheel: _layout?.wheel ?? const [],
              colors: _segmentColors,
              labels: _segmentLabels,
              rotationTurns: _rotation,
              highlightIndex: state.isResult ? state.resultIndex : null,
              glow: _pulse.value,
              art: _wheelArt,
              bandInner: _artBandInner,
              bandOuter: _artBandOuter,
            ),
          ),
          // The hub is dead space on the artwork, and it is dead centre — so
          // the phase and the countdown live there instead of in a separate
          // strip that would steal height from the wheel.
          FractionallySizedBox(
            widthFactor: _artBandInner * 0.84,
            heightFactor: _artBandInner * 0.84,
            child: _hub(state),
          ),
          // The flapper sits fixed at 12 o'clock; the wheel turns beneath it.
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: 0.30,
              child: DecoratedBox(
                // The pointer is the one part that must never get lost against
                // a bright segment, so it carries its own drop shadow.
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.7),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  _flapperArtPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.arrow_drop_down, color: _gold, size: 54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bonusGame(CrazyState state) {
    final data = state.bonus!;
    final picking = state.isBonusPick;
    switch (state.bonusKind) {
      case 'coinflip':
        return CoinFlipBonus(data: data);
      case 'cashhunt':
        return CashHuntBonus(
          data: data,
          picking: picking,
          myPick: state.myPick is int ? state.myPick as int : null,
          onPick: (tile) => _pick(tile),
        );
      case 'pachinko':
        return PachinkoBonus(data: data);
      case 'crazytime':
        return CrazyTimeBonus(
          data: data,
          picking: picking,
          myPick: state.myPick is String ? state.myPick as String : null,
          onPick: (colour) => _pick(colour),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// The wheel's hub: phase, countdown ring, and the round's headline number.
  /// This is the screen's focal point, so it carries the one thing the player
  /// needs at a glance in every phase.
  Widget _hub(CrazyState state) {
    final seconds = (_msLeft / 1000).ceil();
    final (label, accent) = switch (state.phase) {
      'betting' => ('ضع رهانك', _gold),
      'spinning' => ('العجلة تدور', Colors.white),
      'bonus_pick' => ('اختر الآن', const Color(0xFF66BB6A)),
      'bonus_reveal' => ('مكافأة', const Color(0xFF66BB6A)),
      _ => ('النتيجة', Colors.white70),
    };
    // Only the timed phases get a countdown ring; a spin has nothing to wait on.
    final total =
        state.isBetting ? 20000.0 : (state.isBonusPick ? 10000.0 : 0.0);
    final progress = total == 0 ? 0.0 : (_msLeft / total).clamp(0.0, 1.0);

    if (state.isResult) return _resultHub(state);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (progress > 0)
              SizedBox(
                width: size * 0.78,
                height: size * 0.78,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: size * 0.04,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontSize: size * 0.115,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(color: accent.withOpacity(0.6), blurRadius: 14)
                    ],
                  ),
                ),
                if (total > 0) ...[
                  SizedBox(height: size * 0.02),
                  Text(
                    '$seconds',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.34,
                      height: 1,
                      fontWeight: FontWeight.bold,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 10)
                      ],
                    ),
                  ),
                ] else if (state.isSpinning)
                  Padding(
                    padding: EdgeInsets.only(top: size * 0.06),
                    child: SizedBox(
                      width: size * 0.22,
                      height: size * 0.22,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(_gold),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// The result takes over the hub rather than floating a panel on top of it:
  /// one focal point, and the segment that just won is the largest thing on
  /// screen for the seven seconds it is up.
  Widget _resultHub(CrazyState state) {
    final won = state.myPayout > 0;
    final played = state.myBets.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (won)
              // A slow gold breathe behind a win — a celebration without
              // needing another animation controller.
              Container(
                width: size * (0.86 + _pulse.value * 0.12),
                height: size * (0.86 + _pulse.value * 0.12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _gold.withOpacity(0.38), blurRadius: 34),
                  ],
                ),
              ),
            // Dark backing so the payout keeps its contrast inside the glow.
            Container(
              width: size * 0.84,
              height: size * 0.84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.62),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    child: Text(
                      _spotNames[state.resultSegment] ?? '',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.20,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 12)
                        ],
                      ),
                    ),
                  ),
                  if (state.myMultiplier > 0)
                    Text(
                      '×${state.myMultiplier}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: size * 0.11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  SizedBox(height: size * 0.04),
                  if (won)
                    FittedBox(
                      child: Text(
                        '+${_format(state.myPayout)}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: _gold,
                          fontSize: size * 0.19,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 10)
                          ],
                        ),
                      ),
                    )
                  else if (played)
                    Text('حظ أوفر',
                        style: TextStyle(
                            color: Colors.white54, fontSize: size * 0.10)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// What you have riding on the bonus that is currently playing out.
  Widget _bonusStakeStrip(CrazyState state) {
    final stake = state.myBets[state.resultSegment] ?? 0;
    final color = _segmentColors[state.resultSegment] ?? _gold;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.7), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SizedBox(
                  height: 22, child: _spotIcon(state.resultSegment ?? '1')),
              const SizedBox(width: 8),
              Text(
                _spotNames[state.resultSegment] ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          Text(
            stake > 0 ? 'رهانك ${_format(stake)}' : 'لم تراهن',
            style: TextStyle(
              color: stake > 0 ? _gold : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bettingGrid(CrazyState state) {
    final spots = _layout?.betSpots ??
        const [
          '1',
          '2',
          '5',
          '10',
          'coinflip',
          'cashhunt',
          'pachinko',
          'crazytime'
        ];
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1.02,
          children: spots.map((spot) => _betTile(spot, state)).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _actionButton('مسح', Icons.delete_outline,
                  state.isBetting && state.myBets.isNotEmpty ? _clear : null),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionButton(
                  'تكرار', Icons.replay, state.isBetting ? _repeat : null),
            ),
          ],
        ),
      ],
    );
  }

  Widget _betTile(String spot, CrazyState state) {
    final color = _segmentColors[spot] ?? Colors.grey;
    final mine = state.myBets[spot] ?? 0;
    final total = state.totals[spot] ?? 0;
    final payout = _layout?.payouts[spot];
    final isWinner = state.resultSegment == spot && !state.isBetting;
    final enabled = state.isBetting && !_busy;
    final isNumber = payout != null && payout > 0;

    return GestureDetector(
      onTap: enabled ? () => _bet(spot) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(enabled ? 0.92 : 0.45),
              Color.lerp(color, Colors.black, 0.55)!
                  .withOpacity(enabled ? 0.95 : 0.5),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isWinner ? _gold : (mine > 0 ? Colors.white : Colors.white24),
            width: isWinner ? 3 : (mine > 0 ? 2 : 1),
          ),
          boxShadow: [
            if (isWinner)
              const BoxShadow(color: _gold, blurRadius: 20, spreadRadius: -4),
            if (!isWinner && enabled)
              BoxShadow(
                  color: color.withOpacity(0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
          ],
        ),
        child: Stack(
          children: [
            // A soft top highlight is what stops the tiles reading as flat
            // rectangles next to the lacquered wheel.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withOpacity(0.20),
                      Colors.transparent
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Numbers read as the payout itself; bonus games read as art.
                  Expanded(
                    child: Center(
                      child: isNumber
                          ? FittedBox(
                              child: Text(
                                spot,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  height: 1,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black.withOpacity(0.6),
                                        blurRadius: 6),
                                  ],
                                ),
                              ),
                            )
                          : _spotIcon(spot),
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      isNumber ? '$payout:1' : (_spotNames[spot] ?? spot),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Your stake outranks the table total: gold pill when you are
                  // in, muted count when you are not.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mine > 0 ? _gold : Colors.black.withOpacity(0.38),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: FittedBox(
                      child: Text(
                        mine > 0 ? _format(mine) : _format(total),
                        style: TextStyle(
                          color: mine > 0 ? Colors.black : Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
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

  /// Commissioned artwork when we have it, the emoji otherwise.
  Widget _spotIcon(String spot) {
    final art = _spotArt[spot];
    final emoji =
        Text(_spotEmoji[spot] ?? '', style: const TextStyle(fontSize: 22));
    if (art == null) return emoji;
    return Image.asset(art,
        fit: BoxFit.contain, errorBuilder: (_, __, ___) => emoji);
  }

  Widget _actionButton(String label, IconData icon, VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(onTap == null ? 0.04 : 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: onTap == null ? Colors.white12 : _gold.withOpacity(0.55),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: onTap == null ? Colors.white24 : _gold),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: onTap == null ? Colors.white24 : _gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _chipRow(List<int> chips, CrazyState state) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((value) {
            final selected = _chip == value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: GestureDetector(
                onTap: () => setState(() => _chip = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: selected ? 58 : 48,
                  height: selected ? 58 : 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // The chip render carries its own denomination, so the only
                    // thing left to show is which one is armed.
                    boxShadow: selected
                        ? [
                            BoxShadow(
                                color: _gold.withOpacity(0.75), blurRadius: 18)
                          ]
                        : null,
                  ),
                  child: _chipFace(value, selected),
                ),
              ),
            );
          }).toList(),
        ),
      );

  /// Chip artwork, with the painted disc as the fallback.
  Widget _chipFace(int value, bool selected) {
    final art = _chipArt[value];
    final painted = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: _chipColors(value)),
        border: Border.all(
            color: selected ? _gold : Colors.white24, width: selected ? 3 : 2),
      ),
      child: Text(_format(value),
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    );
    if (art == null) return painted;
    return Opacity(
      opacity: selected ? 1 : 0.72,
      child: Image.asset(art,
          fit: BoxFit.contain, errorBuilder: (_, __, ___) => painted),
    );
  }

  List<Color> _chipColors(int value) => switch (value) {
        1000 => [const Color(0xFF64B5F6), const Color(0xFF1565C0)],
        5000 => [const Color(0xFFE57373), const Color(0xFFC62828)],
        10000 => [const Color(0xFF81C784), const Color(0xFF2E7D32)],
        50000 => [const Color(0xFFBA68C8), const Color(0xFF6A1B9A)],
        _ => [const Color(0xFFFFD54F), const Color(0xFFF57F17)],
      };

  String _format(int value) {
    if (value >= 1000000)
      return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
    if (value >= 1000)
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    return '$value';
  }
}

/// Paints the 54-segment ring, its pins and its hub.
class _WheelPainter extends CustomPainter {
  final List<String> wheel;
  final Map<String, Color> colors;
  final Map<String, String> labels;
  final double rotationTurns;
  final int? highlightIndex;
  final double glow;

  /// Commissioned wheel chrome (gold rim, pins, hub). Null falls back to the
  /// painted rim.
  final ui.Image? art;

  /// Radii of the segment band, as fractions of the disc radius.
  final double bandInner;
  final double bandOuter;

  /// The artwork's disc fills this fraction of its own half-width — measured
  /// off wheel.png, and what the scale is derived from.
  static const _artDiscFraction = 0.883;

  _WheelPainter({
    required this.wheel,
    required this.colors,
    required this.labels,
    required this.rotationTurns,
    required this.highlightIndex,
    required this.glow,
    required this.art,
    required this.bandInner,
    required this.bandOuter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (wheel.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = min(size.width, size.height) / 2 - 8;
    final slice = 2 * pi / wheel.length;
    // -pi/2 puts segment 0 under the flapper at 12 o'clock.
    final base = -pi / 2 + rotationTurns * 2 * pi;

    // Seats the wheel on the studio floor instead of floating it: a soft dark
    // pool underneath, and a warm halo off the gold rim.
    canvas.drawCircle(
      center + const Offset(0, 10),
      radius * 0.99,
      Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.06
        ..color = const Color(0xFFFFC107).withOpacity(0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    if (art != null) {
      // The chrome turns with the wheel, so its pins tick past the flapper.
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotationTurns * 2 * pi);
      final side = (radius / _artDiscFraction) * 2;
      canvas.drawImageRect(
        art!,
        Rect.fromLTWH(0, 0, art!.width.toDouble(), art!.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: side, height: side),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    } else {
      // Painted fallback rim when the artwork is unavailable.
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0xFFFFE082),
            Color(0xFF8D6E63)
          ]).createShader(Rect.fromCircle(center: center, radius: radius + 6)),
      );
    }

    // With the chrome in place, the live segments are painted into the band
    // between the artwork's hub and its rim.
    final inner = art != null ? radius * bandInner : 0.0;
    final outer = art != null ? radius * bandOuter : radius;
    if (art != null) {
      canvas.save();
      canvas.clipPath(
        Path()
          ..addOval(Rect.fromCircle(center: center, radius: outer))
          ..addOval(Rect.fromCircle(center: center, radius: inner))
          ..fillType = PathFillType.evenOdd,
      );
    }

    for (var i = 0; i < wheel.length; i++) {
      final key = wheel[i];
      final start = base + i * slice;
      final color = colors[key] ?? Colors.grey;
      final isWinner = highlightIndex == i;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        slice,
        true,
        Paint()
          ..color = isWinner
              ? Color.lerp(color, Colors.white, 0.35 + glow * 0.3)!
              : color,
      );
      // A hairline between segments: dark on the inside edge, bright on the
      // outside, which is what makes 54 thin wedges read as separate slats.
      final edge = Offset(cos(start), sin(start));
      canvas.drawLine(
        center + edge * inner,
        center + edge * outer,
        Paint()
          ..strokeWidth = 1.2
          ..color = Colors.black.withOpacity(0.45),
      );

      _drawLabel(canvas, center, radius, start + slice / 2, labels[key] ?? '',
          isWinner);
    }

    // Mark the winning wedge explicitly. A lightened fill alone is easy to miss
    // among 54 slats, so it also gets a gold outline and a beam to the rim.
    if (highlightIndex != null) {
      final start = base + highlightIndex! * slice;
      final wedge = Path()
        ..moveTo(center.dx + cos(start) * inner, center.dy + sin(start) * inner)
        ..lineTo(center.dx + cos(start) * outer, center.dy + sin(start) * outer)
        ..arcTo(
            Rect.fromCircle(center: center, radius: outer), start, slice, false)
        ..lineTo(center.dx + cos(start + slice) * inner,
            center.dy + sin(start + slice) * inner)
        ..arcTo(Rect.fromCircle(center: center, radius: inner), start + slice,
            -slice, false)
        ..close();

      canvas.drawPath(
        wedge,
        Paint()
          ..color = const Color(0xFFFFD54F).withOpacity(0.35 + glow * 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawPath(
        wedge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFFFF8E1),
      );
    }

    if (art != null) {
      // Give the flat segments back the lacquered look the artwork has: a soft
      // highlight down the upper half and a darker edge towards the rim.
      canvas.drawCircle(
        center,
        outer,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(center.dx, center.dy - outer),
            Offset(center.dx, center.dy + outer),
            [
              Colors.white.withOpacity(0.22),
              Colors.transparent,
              Colors.black.withOpacity(0.28)
            ],
            [0.0, 0.45, 1.0],
          ),
      );
      canvas.restore();
      return; // the artwork already carries the pins and the hub
    }

    // Painted fallback: pins the flapper ticks against, plus the hub.
    final pin = Paint()..color = const Color(0xFFE0E0E0);
    for (var i = 0; i < wheel.length; i++) {
      final angle = base + i * slice;
      canvas.drawCircle(
        center + Offset(cos(angle), sin(angle)) * (radius + 1),
        2.2,
        pin,
      );
    }

    canvas.drawCircle(
        center, radius * 0.24, Paint()..color = const Color(0xFF1B0B2E));
    canvas.drawCircle(
      center,
      radius * 0.24,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFD54F),
    );
  }

  /// Labels sit near the outer edge, where 54 wedges have the most room. Any
  /// further in and the two-letter bonus codes collide with their neighbours.
  void _drawLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    String text,
    bool isWinner,
  ) {
    if (text.isEmpty) return;
    final fontSize = (radius * 0.058).clamp(7.0, 15.0);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isWinner ? Colors.black : Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1,
          shadows: isWinner
              ? null
              : [Shadow(color: Colors.black.withOpacity(0.75), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final position = center + Offset(cos(angle), sin(angle)) * (radius * 0.845);
    canvas.save();
    canvas.translate(position.dx, position.dy);
    // Rotate so the text reads outward along its own wedge.
    canvas.rotate(angle - pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.rotationTurns != rotationTurns ||
      old.highlightIndex != highlightIndex ||
      old.glow != glow ||
      old.wheel != wheel ||
      old.art != art;
}

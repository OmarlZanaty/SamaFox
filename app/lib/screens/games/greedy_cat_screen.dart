import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/greedy_cat_repository.dart';
import '../../services/socket_service.dart';
import 'greedy_cat_art.dart';
import 'greedy_cat_rules.dart';
import 'greedy_cat_sfx.dart';

/// القط الجشع — Greedy Cat Jackpot.
///
/// Eight food cards ring a wooden hub with a cat mascot at its centre. During
/// the 30s selection window a player stacks coins on any card, or on a whole
/// category via the سلطة / بيتزا buttons; the wheel then turns and stops with
/// the winning card under the fixed 12 o'clock pointer.
///
/// Everything that decides an outcome or moves coins is server-side
/// (backend/src/services/greedyCat.service.ts). This screen places bets over
/// REST, listens to `greedy_state` for the shared round, and animates the
/// symbol the server already rolled — it never decides where the wheel stops.
///
/// The wheel spins by orbiting the cards around the hub rather than rotating a
/// canvas: the Arabic multiplier labels and the food icons stay upright through
/// the whole turn, which a rotated-then-counter-rotated widget tree cannot
/// guarantee at speed.
class GreedyCatScreen extends ConsumerStatefulWidget {
  const GreedyCatScreen({super.key});

  @override
  ConsumerState<GreedyCatScreen> createState() => _GreedyCatScreenState();
}

class _GreedyCatScreenState extends ConsumerState<GreedyCatScreen>
    with TickerProviderStateMixin {
  /// Must match SPINNING_MS in the service, so the wheel comes to rest exactly
  /// as the server flips the phase to `result`.
  static const _spinDuration = Duration(milliseconds: 6000);

  static const _prefsMusic = 'greedy_music';
  static const _prefsSfx = 'greedy_sfx';
  static const _prefsMotion = 'greedy_reduced_motion';
  static const _prefsDenomination = 'greedy_denomination';
  static const _prefsRankScope = 'greedy_rank_scope';

  final GreedyCatRepository _repo = GreedyCatRepository();
  final SocketService _socket = SocketService();
  final GreedyCatSfx _sfx = GreedyCatSfx();

  late final AnimationController _spin =
      AnimationController(vsync: this, duration: _spinDuration);
  late final AnimationController _ambient = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();
  late final AnimationController _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 160));
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  GreedyState? _state;
  GreedyLayout? _layout;
  int _balance = 0;
  int _denomination = 100;
  String? _notice;
  bool _busy = false;

  List<GreedyRankRow> _ranking = const [];
  String _rankScope = 'global';
  bool _rankLoading = false;

  bool _musicEnabled = true;
  bool _sfxEnabled = true;
  bool _reducedMotion = false;

  /// Wheel rotation in turns; animated from here to `_spinTarget`.
  double _spinFrom = 0;
  double _spinTarget = 0;
  int _animatedRound = 0;

  /// The round whose result card is on screen. Cleared when the player closes
  /// it or the next round opens, so a modal can never trap anyone.
  int? _resultRound;
  int _dismissedResult = 0;

  Timer? _countdown;
  Timer? _blinkTimer;
  int _msLeft = 0;
  int _lastTickSecond = -1;
  int _lastSegment = 0;

  @override
  void initState() {
    super.initState();
    _spin.addListener(_onSpinTick);
    _ambient.addListener(() {
      if (mounted) setState(() {});
    });
    _blink.addListener(() {
      if (mounted) setState(() {});
    });
    _confetti.addListener(() {
      if (mounted) setState(() {});
    });
    _shake.addListener(() {
      if (mounted) setState(() {});
    });

    _socket.on('greedy_state', _onState);
    _socket.on('greedy_result', _onResult);
    _socket.on('greedy_milestone', _onMilestone);
    _socket.emit('greedy_join_table', {});

    _restoreSettings();
    _load();
    _loadRanking();

    _countdown = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _msLeft = max(0, _msLeft - 200));
      _maybeCountdownSound();
    });

    // Blinking on a timer rather than inside the ambient loop, so it lands at
    // irregular intervals the way a real blink does.
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!mounted || _reducedMotion) return;
      _blink.forward(from: 0).then((_) {
        if (mounted) _blink.reverse();
      });
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _blinkTimer?.cancel();
    _socket.off('greedy_state');
    _socket.off('greedy_result');
    _socket.off('greedy_milestone');
    _socket.emit('greedy_leave_table', {});
    _sfx.stopMusic();
    _spin.dispose();
    _ambient.dispose();
    _blink.dispose();
    _confetti.dispose();
    _shake.dispose();
    _sfx.dispose();
    super.dispose();
  }

  // ── Settings ──────────────────────────────────────────────
  Future<void> _restoreSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _musicEnabled = prefs.getBool(_prefsMusic) ?? true;
        _sfxEnabled = prefs.getBool(_prefsSfx) ?? true;
        _reducedMotion = prefs.getBool(_prefsMotion) ?? false;
        _rankScope = prefs.getString(_prefsRankScope) ?? 'global';
        final saved = prefs.getInt(_prefsDenomination);
        if (saved != null) _denomination = saved;
        _sfx.musicEnabled = _musicEnabled;
        _sfx.sfxEnabled = _sfxEnabled;
      });
      // Started only after preferences load, so someone who turned music off
      // last session never hears a burst of it on open.
      if (_musicEnabled) _sfx.startMusic();
    } catch (_) {
      // Preferences are a convenience — defaults are all perfectly playable.
    }
  }

  Future<void> _persist(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) await prefs.setBool(key, value);
      if (value is int) await prefs.setInt(key, value);
      if (value is String) await prefs.setString(key, value);
    } catch (_) {}
  }

  // ── Server state ──────────────────────────────────────────
  Future<void> _load() async {
    try {
      final res = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _layout = res.layout ?? _layout;
        _balance = res.balance;
        // The first denomination is selected by default, but only if the player
        // has no saved preference that is still on the table.
        final denominations = _layout?.denominations ?? const <int>[];
        if (denominations.isNotEmpty && !denominations.contains(_denomination)) {
          _denomination = denominations.first;
        }
        if (res.state != null) _apply(res.state!);
      });
    } on GreedyCatException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _loadRanking() async {
    if (_rankLoading) return;
    setState(() => _rankLoading = true);
    try {
      final rows = await _repo.fetchRanking(_rankScope);
      if (!mounted) return;
      setState(() => _ranking = rows);
    } on GreedyCatException {
      // A stale board is better than an error banner over the game.
    } finally {
      if (mounted) setState(() => _rankLoading = false);
    }
  }

  void _onState(dynamic raw) {
    if (!mounted || raw is! Map) return;
    setState(() => _apply(
        GreedyState.fromJson(Map<String, dynamic>.from(raw)).withMineFrom(_state)));
  }

  void _onResult(dynamic raw) {
    // The payout arrives with the result broadcast; re-pull rather than trying
    // to reconstruct the balance locally.
    _refresh();
    _loadRanking();
  }

  void _onMilestone(dynamic raw) {
    if (!mounted) return;
    _sfx.milestone();
  }

  Future<void> _refresh() async {
    try {
      final res = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _balance = res.balance;
        if (res.state != null) _apply(res.state!);
      });
    } catch (_) {
      // A failed refresh is cosmetic — the next state tick corrects it.
    }
  }

  void _apply(GreedyState state) {
    final previous = _state;
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

    // Result card: raised once per round, and only for a round this player was
    // actually in a position to see resolve.
    if (state.isResult &&
        _resultRound != state.roundId &&
        _dismissedResult != state.roundId) {
      _resultRound = state.roundId;
      _onResultRevealed(state);
    }

    if (previous != null && previous.roundId != state.roundId) {
      // A new round opened — clear the old card and let the wheel idle again.
      _resultRound = null;
      _confetti.stop();
    }
  }

  void _onResultRevealed(GreedyState state) {
    _sfx.stopSpin();
    _sfx.stopped();
    // Pull the balance the moment the result lands, rather than waiting for the
    // `greedy_result` event to do it. That event is the only other trigger, so
    // if it is missed — a reconnect, a backgrounded app, a dropped frame on the
    // socket — the coin balance sat stale on screen while the server had
    // already moved it.
    _refresh();
    if (state.myStaked <= 0) return;
    if (state.myPayout > 0) {
      _sfx.win();
      _sfx.meow();
      if (!_reducedMotion) _confetti.forward(from: 0);
    } else {
      _sfx.lose();
    }
  }

  // ── Spin ──────────────────────────────────────────────────
  void _startSpin(int resultIndex) {
    final count = _layout?.symbols.length ?? 8;
    if (count == 0) return;

    final landing = WheelFramePainter.landingFor(resultIndex, count);
    _spinFrom = _spinTarget;
    // Several whole turns of run-up, then settle on the landing offset. Working
    // from the *current* rotation means the wheel never jumps before it moves.
    final turns = _reducedMotion ? 0.0 : 5.0;
    _spinTarget = (_spinFrom.floorToDouble()) + turns + landing;
    while (_spinTarget <= _spinFrom) {
      _spinTarget += 1;
    }

    _lastSegment = (_rotation * count).floor();
    if (_reducedMotion) {
      // No spin: settle straight onto the winner with a short fade instead.
      _spin.value = 1.0;
      setState(() {});
      return;
    }
    _sfx.spin();
    _spin.forward(from: 0);
  }

  void _onSpinTick() {
    if (!mounted) return;
    setState(() {});
    final count = _layout?.symbols.length ?? 8;
    final segment = (_rotation * count).floor();
    if (segment != _lastSegment) {
      _lastSegment = segment;
      _sfx.segment();
    }
  }

  double get _rotation {
    // Quartic ease-out gives the long, heavy settle the wheel needs; the small
    // overshoot near the end reads as the mechanism rocking back into place.
    final t = Curves.easeOutQuart.transform(_spin.value);
    final base = _spinFrom + (_spinTarget - _spinFrom) * t;
    if (_spin.value > 0.86 && _spin.value < 1.0) {
      final swing = sin((_spin.value - 0.86) / 0.14 * pi) * 0.0016;
      return base + swing;
    }
    return base;
  }

  void _maybeCountdownSound() {
    final state = _state;
    if (state == null || !state.isBetting) {
      _lastTickSecond = -1;
      return;
    }
    final seconds = (_msLeft / 1000).ceil();
    if (seconds <= 5 && seconds > 0 && seconds != _lastTickSecond) {
      _lastTickSecond = seconds;
      _sfx.countdown();
    }
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _bet(String target) async {
    final state = _state;
    if (_busy || state?.acceptsBets != true) return;

    // Fail fast and locally on an affordable-looking bet, so the shake happens
    // on the tap rather than after a round-trip.
    if (_balance < _denomination) {
      _rejectForBalance();
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final res = await _repo.placeBet(target: target, amount: _denomination);
      if (!mounted) return;
      _sfx.coin();
      setState(() {
        _balance = res.balance;
        _state = _state?.copyWith(
          bets: res.bets,
          categories: res.categories,
          staked: res.bets.values.fold<int>(0, (a, b) => a + b),
        );
      });
    } on GreedyCatException catch (e) {
      if (!mounted) return;
      if (e.code == 'INSUFFICIENT_COINS') {
        _rejectForBalance(e.message);
      } else {
        setState(() => _notice = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Long-press on a food card. Takes one denomination back off it — the brief
  /// asks for a way to undo a single bet, not just to clear the whole round.
  Future<void> _reduce(String symbolKey) async {
    final state = _state;
    if (_busy || state?.acceptsBets != true) return;
    if ((state?.myBets[symbolKey] ?? 0) <= 0) return;

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final res = await _repo.reduceBet(target: symbolKey, amount: _denomination);
      if (!mounted) return;
      _sfx.click();
      setState(() {
        _balance = res.balance;
        _state = _state?.copyWith(
          bets: res.bets,
          categories: res.categories,
          staked: res.bets.values.fold<int>(0, (a, b) => a + b),
        );
      });
    } on GreedyCatException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rejectForBalance([String? message]) {
    setState(() => _notice = message ?? 'رصيدك لا يكفي');
    _shake.forward(from: 0);
  }

  Future<void> _clear() async {
    final state = _state;
    if (_busy || state?.acceptsBets != true) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final res = await _repo.clearBets();
      if (!mounted) return;
      _sfx.click();
      setState(() {
        _balance = res.balance;
        _state = _state?.copyWith(
          bets: res.bets,
          categories: res.categories,
          staked: 0,
        );
      });
    } on GreedyCatException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repeat() async {
    final state = _state;
    if (_busy || state?.acceptsBets != true) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final res = await _repo.repeatBets();
      if (!mounted) return;
      _sfx.coin();
      setState(() {
        _balance = res.balance;
        _state = _state?.copyWith(
          bets: res.bets,
          categories: res.categories,
          staked: res.bets.values.fold<int>(0, (a, b) => a + b),
        );
      });
    } on GreedyCatException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectDenomination(int value) {
    _sfx.click();
    setState(() => _denomination = value);
    _persist(_prefsDenomination, value);
  }

  void _setRankScope(String scope) {
    if (_rankScope == scope) return;
    _sfx.click();
    setState(() => _rankScope = scope);
    _persist(_prefsRankScope, scope);
    _loadRanking();
  }

  void _openRules() {
    _sfx.modalOpen();
    showGreedyRules(
      context,
      layout: _layout,
      musicEnabled: _musicEnabled,
      sfxEnabled: _sfxEnabled,
      reducedMotion: _reducedMotion,
      onMusic: (v) {
        setState(() {
          _musicEnabled = v;
          _sfx.musicEnabled = v;
        });
        if (v) {
          _sfx.startMusic();
        } else {
          _sfx.stopSpin();
          _sfx.stopMusic();
        }
        _persist(_prefsMusic, v);
      },
      onSfx: (v) {
        setState(() {
          _sfxEnabled = v;
          _sfx.sfxEnabled = v;
        });
        _persist(_prefsSfx, v);
      },
      onReducedMotion: (v) {
        setState(() => _reducedMotion = v);
        _persist(_prefsMotion, v);
      },
    ).then((_) => _sfx.modalClose());
  }

  void _toggleMusic() {
    final next = !_musicEnabled;
    setState(() {
      _musicEnabled = next;
      _sfx.musicEnabled = next;
    });
    if (next) {
      _sfx.startMusic();
    } else {
      _sfx.stopSpin();
      _sfx.stopMusic();
    }
    _persist(_prefsMusic, next);
  }

  // ── Formatting ────────────────────────────────────────────
  static String _fmt(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${negative ? '-' : ''}$buffer';
  }

  /// Compact form for the places where numbers get very long.
  ///
  /// Works off the magnitude and re-applies the sign, so a losing day reads
  /// "-6.0K" rather than falling through the thresholds to a raw "-6000".
  static String _compact(int value) {
    final sign = value < 0 ? '-' : '';
    final n = value.abs();
    if (n >= 1000000) return '$sign${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '$sign${(n / 1000).toStringAsFixed(1)}K';
    return '$sign$n';
  }

  String get _phaseLabel {
    final state = _state;
    if (state == null) return 'جارٍ التحميل';
    if (state.isBetting) return 'وقت الاختيار';
    if (state.isClosing) return 'النتيجة قادمة';
    return 'وقت العرض';
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The system's own reduced-motion setting wins whenever it is on; the
    // in-game switch can only add to it.
    final reduced = _reducedMotion || media.disableAnimations;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: GreedyPalette.cyanBottom,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: BackgroundPatternPainter(
                  drift: reduced ? 0 : _ambient.value,
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _shortcutStrip(),
                  _header(),
                  _wheelZone(context, reduced),
                  Expanded(child: _dashboard(reduced)),
                ],
              ),
            ),
            if (_notice != null) _noticeBanner(),
            if (_resultRound != null) _resultCard(reduced),
            if (!reduced && _confetti.isAnimating)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: ConfettiPainter(
                      progress: _confetti.value,
                      seed: _resultRound ?? 0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Top strip ─────────────────────────────────────────────
  /// The purple game carousel. These are real shortcuts: every one of them
  /// returns to the games hub, which is where the other tables are opened from,
  /// so nothing here is decoration that does nothing when tapped.
  Widget _shortcutStrip() {
    const others = [
      ['assets/images/cards/card_plinko.png', Color(0xFF9C6BFF)],
      ['assets/images/cards/card_crazy.png', Color(0xFFFFC107)],
      ['assets/images/cards/card_crash.png', Color(0xFFFF9800)],
      ['assets/images/cards/card_aetherfall.png', Color(0xFF4DD8E6)],
      ['assets/images/cards/card_neon.png', Color(0xFFEA35D7)],
    ];

    return Container(
      height: 62,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [GreedyPalette.purpleStrip, GreedyPalette.purpleStripLight],
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          _selectedShortcut(),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _shortcut(
                others[i][0] as String,
                others[i][1] as Color,
              ),
            ),
          ),
          _backToHub(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _selectedShortcut() {
    final bob = sin(_ambient.value * 2 * pi) * 1.4;
    return Transform.translate(
      offset: Offset(0, _reducedMotion ? 0 : bob),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GreedyPalette.cyanTop,
          border: Border.all(color: GreedyPalette.gold, width: 2.6),
          boxShadow: [
            BoxShadow(
              color: GreedyPalette.gold.withOpacity(0.55),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: CustomPaint(
            painter: CatMascotPainter(mood: CatMood.idle, breath: 0.25, blink: 0),
          ),
        ),
      ),
    );
  }

  Widget _shortcut(String asset, Color accent) => GestureDetector(
        onTap: _goToHub,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withOpacity(0.25),
            border: Border.all(color: accent.withOpacity(0.9), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: accent.withOpacity(0.5)),
          ),
        ),
      );

  Widget _backToHub() => GestureDetector(
        onTap: _goToHub,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: GreedyPalette.gold,
            border: Border.all(color: GreedyPalette.woodOutline, width: 2),
          ),
          // RTL: "onward" points left, so the chevron follows the text direction
          // rather than staying pinned to a hard-coded right arrow.
          child: const Icon(Icons.chevron_left_rounded,
              color: GreedyPalette.woodOutline, size: 26),
        ),
      );

  void _goToHub() {
    _sfx.click();
    Navigator.of(context).maybePop();
  }

  // ── Header ────────────────────────────────────────────────
  Widget _header() {
    final state = _state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _musicButton(),
          const SizedBox(width: 8),
          _rulesButton(),
          // Expanded rather than a Spacer plus an intrinsically-sized Column:
          // the round label is a variable-length Arabic string next to a
          // variable-length number, and on a 320px screen the pair used to push
          // the row 124px past its bounds.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: GreedyPalette.deepRed,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: GreedyPalette.woodOutline, width: 1.6),
                  ),
                  child: Text(
                    'الجولة الحالية ${state?.roundId ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _luckyDrop(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _musicButton() => GestureDetector(
        onTap: _toggleMusic,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: GreedyPalette.woodOutline, width: 2),
          ),
          child: Icon(
            _musicEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
            size: 21,
            color: _musicEnabled ? GreedyPalette.darkText : GreedyPalette.mutedText,
          ),
        ),
      );

  Widget _rulesButton() => GestureDetector(
        onTap: _openRules,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: GreedyPalette.cream,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: GreedyPalette.woodOutline, width: 2),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('القواعد',
                  style: TextStyle(
                    color: GreedyPalette.darkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  )),
              SizedBox(width: 2),
              Icon(Icons.chevron_left_rounded,
                  size: 19, color: GreedyPalette.woodOutline),
            ],
          ),
        ),
      );

  /// The LuckyDrop teaser. It reports the live table activity meter, which is
  /// what the jackpot bar below tracks — deliberately not phrased as a prize.
  Widget _luckyDrop() {
    final jackpot = _state?.jackpot ?? GreedyJackpot.empty;
    final bob = _reducedMotion ? 0.0 : sin(_ambient.value * 2 * pi) * 2.0;
    return Transform.translate(
      offset: Offset(0, bob),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: GreedyPalette.cream.withOpacity(0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GreedyPalette.gold, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TreasureChest(size: 30),
            const SizedBox(width: 6),
            // Flexible + scale-down: the header only leaves this teaser about
            // 100px on a 320px screen, and its label is a full Arabic phrase.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('نشاط الطاولة',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: GreedyPalette.mutedText,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _compact(jackpot.pot),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: GreedyPalette.deepRed,
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

  // ── Wheel ─────────────────────────────────────────────────
  Widget _wheelZone(BuildContext context, bool reduced) {
    final media = MediaQuery.of(context);
    // The wheel is the focal point and must never be squeezed until the food
    // labels stop being readable, so it claims a share of the *screen* height
    // and the dashboard below scrolls instead.
    final side = min(
      media.size.width - 8,
      max(240.0, media.size.height * 0.42),
    );
    return SizedBox(
      width: double.infinity,
      height: side,
      child: Center(
        child: SizedBox(
          width: side,
          height: side,
          child: _wheel(side, reduced),
        ),
      ),
    );
  }

  Widget _wheel(double side, bool reduced) {
    final symbols = _layout?.symbols ?? const <GreedySymbol>[];
    final count = symbols.isEmpty ? 8 : symbols.length;
    // The ring has to leave room above the top card for the pointer, which is
    // drawn outside it: card top edge sits at side*0.0675, and the pointer
    // hangs from side*0.0125 so its tip overlaps the card it is indicating.
    final cardRadius = side * 0.33;
    final cardSize = side * 0.205;
    final hubRadius = side * 0.15;
    final pointerSize = side * 0.08;
    final state = _state;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: WheelFramePainter(
              count: count,
              cardRadius: cardRadius,
              hubRadius: hubRadius,
              rotation: _rotation,
              glow: reduced ? 0 : _ambient.value,
              winningIndex: state?.resultIndex,
              winnerPulse: state != null && (state.isSpinning || state.isResult)
                  ? Curves.easeOut.transform(_spin.value)
                  : 0,
            ),
          ),
        ),

        // Food cards, orbiting the hub. Never rotated themselves.
        for (var i = 0; i < symbols.length; i++)
          _positionedCard(i, symbols[i], count, cardRadius, cardSize, side),

        // The mascot sits in the hub, pushed down so the timer badge overlaps
        // only the top of its head. The chibi head is tall enough that a
        // centred mascot puts its eyes directly behind the countdown.
        Transform.translate(
          offset: Offset(0, hubRadius * 0.35),
          child: SizedBox(
            width: hubRadius * 1.55,
            height: hubRadius * 1.55,
            child: CustomPaint(
              painter: CatMascotPainter(
                mood: _catMood,
                breath: reduced ? 0.25 : _ambient.value,
                blink: _blink.value,
              ),
            ),
          ),
        ),

        // Timer badge, overlapping the top of the hub. It has to clear the
        // 12 o'clock card's stake badge, which hangs below that card — at the
        // old offset the ring cut straight through it.
        Positioned(
          top: side / 2 - hubRadius - side * 0.042,
          child: _timerBadge(side),
        ),

        // The fixed winner pointer at 12 o'clock.
        Positioned(
          top: side / 2 - cardRadius - cardSize / 2 - pointerSize * 0.68,
          child: SizedBox(
            width: pointerSize,
            height: pointerSize,
            child: CustomPaint(
              painter: PointerPainter(
                pulse: state?.isResult == true
                    ? (0.5 + 0.5 * sin(_ambient.value * 4 * pi)).clamp(0.0, 1.0)
                    : 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  CatMood get _catMood {
    final state = _state;
    if (state == null) return CatMood.idle;
    if (state.isResult && state.myStaked > 0) {
      return state.myPayout > 0 ? CatMood.win : CatMood.lose;
    }
    if (state.isClosing || state.isSpinning) return CatMood.alert;
    return CatMood.idle;
  }

  Widget _positionedCard(
    int i,
    GreedySymbol symbol,
    int count,
    double cardRadius,
    double cardSize,
    double side,
  ) {
    final angle = WheelFramePainter.angleFor(i, count, _rotation);
    final dx = cos(angle) * cardRadius;
    final dy = sin(angle) * cardRadius;
    return Positioned(
      left: side / 2 + dx - cardSize / 2,
      top: side / 2 + dy - cardSize / 2,
      width: cardSize,
      height: cardSize,
      child: _foodCard(symbol, cardSize, i),
    );
  }

  Widget _foodCard(GreedySymbol symbol, double size, int index) {
    final state = _state;
    final mine = state?.myBets[symbol.key] ?? 0;
    final tableTotal = state?.totals[symbol.key] ?? 0;
    final isHot = state?.hot == symbol.key;
    final isWinner = state?.resultSymbol == symbol.key &&
        (state?.isResult == true || state?.isSpinning == true);
    final enabled = state?.acceptsBets == true;

    final pulse = isWinner && !_reducedMotion
        ? 0.5 + 0.5 * sin(_ambient.value * 4 * pi)
        : 0.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: '${symbol.nameAr}، مضاعفة ${symbol.multiplier}'
          '${mine > 0 ? '، رهانك ${_fmt(mine)}، اضغط مطولاً للتقليل' : ''}',
      child: GestureDetector(
        onTap: enabled ? () => _bet(symbol.key) : null,
        onLongPress: enabled && mine > 0 ? () => _reduce(symbol.key) : null,
        child: AnimatedScale(
          scale: mine > 0 ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: Opacity(
            // Disabled cards are dimmed as well as inert, so state is never
            // carried by colour alone.
            opacity: enabled || isWinner ? 1 : 0.55,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The plaque and its shading are painted, not stacked out of
                // Containers — a flat cream circle behind a flat ring is what
                // made the wheel read as paper cut-outs.
                SizedBox.expand(
                  child: CustomPaint(
                    painter: PlaquePainter(winner: isWinner, pulse: pulse),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: size * 0.16),
                    // Fills the dish properly: at 0.46 the food sat in the
                    // middle of a large empty plaque and read as an afterthought.
                    child: FoodIcon(symbol.key, size: size * 0.62),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: size * 0.115,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: size * 0.075, vertical: size * 0.012),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, GreedyPalette.creamDeep],
                        ),
                        borderRadius: BorderRadius.circular(size),
                        border: Border.all(
                            color: GreedyPalette.woodOutline, width: size * 0.018),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: size * 0.03,
                            offset: Offset(0, size * 0.012),
                          ),
                        ],
                      ),
                      child: FittedBox(
                        child: Text(
                          'مضاعفة ${symbol.multiplier}',
                          style: TextStyle(
                            fontSize: size * 0.115,
                            fontWeight: FontWeight.w900,
                            color: GreedyPalette.darkText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (isHot) _hotBadge(size),
                if (mine > 0) _myBetBadge(mine, size),
                if (tableTotal > 0 && mine == 0) _tableTotalBadge(tableTotal, size),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hotBadge(double size) => Positioned(
        top: -size * 0.06,
        left: -size * 0.02,
        child: Transform.rotate(
          angle: _reducedMotion ? 0 : sin(_ambient.value * 2 * pi) * 0.06,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: size * 0.08, vertical: size * 0.028),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5722),
              borderRadius: BorderRadius.circular(size),
              border: Border.all(color: GreedyPalette.woodOutline, width: 1.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded,
                    size: size * 0.13, color: GreedyPalette.gold),
                Text(
                  'ساخن',
                  style: TextStyle(
                    fontSize: size * 0.105,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// The player's own stake. Gold on cream, distinct from the table total's
  /// cool grey so the two can never be read as the same figure.
  Widget _myBetBadge(int amount, double size) => Positioned(
        bottom: -size * 0.05,
        right: size * 0.06,
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: size * 0.07, vertical: size * 0.022),
          decoration: BoxDecoration(
            color: GreedyPalette.gold,
            borderRadius: BorderRadius.circular(size),
            border: Border.all(color: GreedyPalette.woodOutline, width: 1.6),
          ),
          child: Text(
            'أنت ${_compact(amount)}',
            style: TextStyle(
              fontSize: size * 0.11,
              fontWeight: FontWeight.w900,
              color: GreedyPalette.darkText,
            ),
          ),
        ),
      );

  Widget _tableTotalBadge(int amount, double size) => Positioned(
        bottom: -size * 0.04,
        right: size * 0.12,
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: size * 0.06, vertical: size * 0.018),
          decoration: BoxDecoration(
            color: const Color(0xFF2B4A63).withOpacity(0.85),
            borderRadius: BorderRadius.circular(size),
          ),
          child: Text(
            _compact(amount),
            style: TextStyle(
              fontSize: size * 0.095,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );

  Widget _timerBadge(double side) {
    final state = _state;
    final seconds = (_msLeft / 1000).ceil();
    final urgent = state?.isBetting == true && seconds <= 5;
    final diameter = side * 0.175;

    // The ring drains across whichever phase is running, so the arc always
    // means the same thing: time left in the phase named beneath it.
    final total = state == null
        ? 1.0
        : state.isBetting
            ? 30000.0
            : state.isClosing
                ? 5000.0
                : 6000.0;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: (_msLeft / total).clamp(0.0, 1.0),
              strokeWidth: diameter * 0.09,
              backgroundColor: GreedyPalette.woodOutline.withOpacity(0.35),
              valueColor: AlwaysStoppedAnimation(
                urgent ? GreedyPalette.jackpotRed : GreedyPalette.gold,
              ),
            ),
          ),
          Container(
            margin: EdgeInsets.all(diameter * 0.13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GreedyPalette.cream,
              border: Border.all(color: GreedyPalette.woodOutline, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: diameter * 0.08),
                    child: Text(
                      _phaseLabel,
                      style: TextStyle(
                        fontSize: diameter * 0.135,
                        fontWeight: FontWeight.w800,
                        color: GreedyPalette.mutedText,
                      ),
                    ),
                  ),
                ),
                AnimatedScale(
                  scale: urgent && !_reducedMotion ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    state == null ? '—' : '$seconds',
                    style: TextStyle(
                      fontSize: diameter * 0.3,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: urgent ? GreedyPalette.jackpotRed : GreedyPalette.darkText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Dashboard ─────────────────────────────────────────────
  Widget _dashboard(bool reduced) => ListView(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 22),
        children: [
          _categoryRow(),
          const SizedBox(height: 8),
          _wagerPanel(),
          const SizedBox(height: 8),
          _statsRow(),
          const SizedBox(height: 8),
          _jackpotBar(),
          const SizedBox(height: 8),
          _resultsStrip(),
          const SizedBox(height: 8),
          _rankingCard(),
        ],
      );

  Widget _categoryRow() {
    final state = _state;
    final enabled = state?.acceptsBets == true;
    return Row(
      children: [
        Expanded(
          child: _categoryButton(
            'pizza',
            'بيتزا',
            const [Color(0xFFFF8A3D), Color(0xFFE04B2A)],
            state?.myCategories['pizza'] ?? 0,
            enabled,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _categoryButton(
            'salad',
            'سلطة',
            const [Color(0xFF7BD46A), Color(0xFF2E9BE0)],
            state?.myCategories['salad'] ?? 0,
            enabled,
          ),
        ),
      ],
    );
  }

  Widget _categoryButton(
    String key,
    String label,
    List<Color> colors,
    int mine,
    bool enabled,
  ) {
    final members = _layout?.categories[key] ?? const <String>[];
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label، يوزّع الرهان على أربعة أطباق',
      child: GestureDetector(
        onTap: enabled ? () => _bet(key) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(31),
              border: Border.all(
                color: mine > 0 ? GreedyPalette.gold : GreedyPalette.woodOutline,
                width: mine > 0 ? 3.4 : 2.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // The four member foods, so the split is visible rather than
                // something the player has to read about in the rules.
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    children: [
                      for (var i = 0; i < members.length && i < 4; i++)
                        Positioned(
                          left: (i % 2) * 17.0,
                          top: (i ~/ 2) * 17.0,
                          child: FoodIcon(members[i], size: 22),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black38, blurRadius: 3)],
                        ),
                      ),
                      if (mine > 0)
                        Text(
                          'أنت ${_compact(mine)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: GreedyPalette.gold,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wagerPanel() {
    final denominations = _layout?.denominations ?? const <int>[];
    final enabled = _state?.acceptsBets == true;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [GreedyPalette.jackpotRed, GreedyPalette.deepRed],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GreedyPalette.woodOutline, width: 2),
      ),
      child: Column(
        children: [
          const Text(
            'اختر الرهان < اختر الطعام',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            // A horizontal scroller rather than a squeeze, so the tiles stay
            // readable down to a 320px-wide phone.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: denominations.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, i) => _denominationTile(denominations[i], enabled),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _smallButton('مسح', Icons.delete_sweep_rounded, _clear, enabled)),
              const SizedBox(width: 8),
              Expanded(child: _smallButton('تكرار', Icons.replay_rounded, _repeat, enabled)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _denominationTile(int value, bool enabled) {
    final selected = value == _denomination;
    return Semantics(
      button: true,
      selected: selected,
      label: 'رهان ${_fmt(value)}',
      child: GestureDetector(
        onTap: () => _selectDenomination(value),
        child: AnimatedScale(
          scale: selected ? 1.0 : 0.94,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutBack,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: selected ? GreedyPalette.warmPale : GreedyPalette.cream,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? GreedyPalette.gold : GreedyPalette.woodOutline,
                width: selected ? 3.4 : 1.8,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: GreedyPalette.gold.withOpacity(0.65),
                        blurRadius: 11,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoinEmblem(size: 20),
                const SizedBox(width: 5),
                Text(
                  _compact(value),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: enabled ? GreedyPalette.darkText : GreedyPalette.mutedText,
                  ),
                ),
                // Selection is marked by a tick as well as the gold ring, so it
                // never depends on colour alone.
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(Icons.check_circle_rounded,
                        size: 15, color: GreedyPalette.jackpotRed),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallButton(
      String label, IconData icon, VoidCallback onTap, bool enabled) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.55), width: 1.6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsRow() {
    final state = _state;
    final shake = sin(_shake.value * pi * 6) * (1 - _shake.value) * 7;
    return Row(
      children: [
        Expanded(child: _statPill('أرباح اليوم', state?.todayNet ?? 0, signed: true)),
        const SizedBox(width: 7),
        Expanded(child: _statPill('سجلي', state?.todayBest ?? 0)),
        const SizedBox(width: 7),
        Expanded(
          child: Transform.translate(
            offset: Offset(shake, 0),
            child: _statPill('رصيدي', _balance),
          ),
        ),
      ],
    );
  }

  Widget _statPill(String label, int value, {bool signed = false}) {
    final positive = value > 0;
    final negative = value < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: GreedyPalette.cream,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: GreedyPalette.woodOutline, width: 1.8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: GreedyPalette.mutedText,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CoinEmblem(size: 15),
              const SizedBox(width: 3),
              Flexible(
                child: FittedBox(
                  child: Text(
                    signed && positive ? '+${_compact(value)}' : _compact(value),
                    // A signed number inside an RTL paragraph gets its sign
                    // reordered to the far side — "+475.0K" renders as
                    // "475.0K+". Forcing the run LTR keeps the sign attached.
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: signed && positive
                          ? const Color(0xFF1B8A54)
                          : signed && negative
                              ? GreedyPalette.deepRed
                              : GreedyPalette.darkText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jackpotBar() {
    final jackpot = _state?.jackpot ?? GreedyJackpot.empty;
    final milestones = jackpot.milestones;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6E8A), GreedyPalette.jackpotRed],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GreedyPalette.woodOutline, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Flexible(
                child: Text(
                  'نشاط الطاولة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Expanded, so it still sits hard against the far edge the way a
              // Spacer used to put it — but shrinks instead of overflowing.
              Expanded(
                child: Text(
                  jackpot.nextMilestone == null
                      ? 'اكتملت كل المراحل'
                      : 'التالي ${_compact(jackpot.nextMilestone!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: GreedyPalette.warmPale,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              height: 15,
              child: Stack(
                children: [
                  Container(color: GreedyPalette.deepRed.withOpacity(0.65)),
                  FractionallySizedBox(
                    widthFactor: jackpot.progress,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [GreedyPalette.gold, Color(0xFFFFF0A8)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < milestones.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      TreasureChest(
                        size: 24,
                        opened: i < jackpot.reached,
                        locked: i >= jackpot.reached,
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _compact(milestones[i]),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: i < jackpot.reached
                                ? GreedyPalette.gold
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultsStrip() {
    final history = _state?.history.reversed.toList() ?? const <GreedyHistoryEntry>[];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF2586C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GreedyPalette.woodOutline, width: 2),
      ),
      child: Row(
        children: [
          const Text(
            'النتائج:',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 44,
              child: history.isEmpty
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'لا توجد نتائج بعد',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => _resultToken(history[i], i == 0),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultToken(GreedyHistoryEntry entry, bool newest) {
    return Semantics(
      label: 'جولة ${entry.roundId}، مضاعفة ${entry.multiplier}',
      child: SizedBox(
        width: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GreedyPalette.cream,
                border: Border.all(
                  color: newest ? GreedyPalette.gold : GreedyPalette.woodOutline,
                  width: newest ? 2.4 : 1.6,
                ),
              ),
              child: Center(child: FoodIcon(entry.symbol, size: 27)),
            ),
            if (newest)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: GreedyPalette.gold,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: GreedyPalette.woodOutline, width: 1),
                  ),
                  child: const Text(
                    'جديد',
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w900,
                      color: GreedyPalette.darkText,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rankingCard() {
    final top = _ranking.isEmpty ? null : _ranking.first;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7C9C), Color(0xFFE8536E)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GreedyPalette.woodOutline, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'ترتيب اليوم',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Container(
                width: 1.6,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.white38,
              ),
              if (top == null)
                const Expanded(
                  child: Text(
                    'لم يفز أحد بعد اليوم',
                    style: TextStyle(fontSize: 12.5, color: Colors.white70),
                  ),
                )
              else ...[
                _avatar(top.avatarUrl, top.name, 30),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    top.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const CoinEmblem(size: 17),
                const SizedBox(width: 3),
                Text(
                  _compact(top.score),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: GreedyPalette.gold,
                  ),
                ),
              ],
            ],
          ),
          if (_ranking.length > 1) ...[
            const SizedBox(height: 8),
            for (final row in _ranking.skip(1).take(2)) _rankRow(row),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _rankTab('ترتيب الإقليم', 'region', GreedyPalette.cream)),
              const SizedBox(width: 9),
              Expanded(
                  child: _rankTab('الترتيب العالمي', 'global', const Color(0xFFA8F0D0))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rankRow(GreedyRankRow row) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '${row.rank}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _avatar(row.avatarUrl, row.name, 22),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                row.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ),
            Text(
              _compact(row.score),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: GreedyPalette.warmPale,
              ),
            ),
          ],
        ),
      );

  Widget _avatar(String? url, String name, double size) {
    final initial = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GreedyPalette.warmPale,
        border: Border.all(color: GreedyPalette.woodOutline, width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null || url.isEmpty
          ? Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w900,
                  color: GreedyPalette.woodOutline,
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: size * 0.45,
                    fontWeight: FontWeight.w900,
                    color: GreedyPalette.woodOutline,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _rankTab(String label, String scope, Color colour) {
    final selected = _rankScope == scope;
    return GestureDetector(
      onTap: () => _setRankScope(scope),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        decoration: BoxDecoration(
          color: selected ? colour : colour.withOpacity(0.45),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: selected ? GreedyPalette.woodOutline : Colors.transparent,
            width: 2.4,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.check_rounded,
                      size: 15, color: GreedyPalette.woodOutline),
                ),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: GreedyPalette.darkText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Overlays ──────────────────────────────────────────────
  Widget _noticeBanner() => Positioned(
        left: 16,
        right: 16,
        bottom: 22,
        child: GestureDetector(
          onTap: () => setState(() => _notice = null),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: GreedyPalette.deepRed,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GreedyPalette.gold, width: 1.6),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notice!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _resultCard(bool reduced) {
    final state = _state;
    if (state == null || state.resultSymbol == null) return const SizedBox.shrink();

    final symbol = _layout?.symbols.firstWhere(
      (s) => s.key == state.resultSymbol,
      orElse: () => GreedySymbol(
        key: state.resultSymbol!,
        category: 'salad',
        multiplier: state.myMultiplier,
        weight: 0,
        nameAr: '',
      ),
    );
    final played = state.myStaked > 0;
    final won = state.myPayout > 0;

    return Positioned.fill(
      child: Stack(
        children: [
          // Backdrop is deliberately light: the wheel stays readable behind the
          // card so the result keeps its context.
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissResult,
              child: Container(color: Colors.black.withOpacity(0.45)),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduced ? 1 : 0, end: 1),
              duration: Duration(milliseconds: reduced ? 1 : 420),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Transform.translate(
                offset: Offset(0, (1 - t) * 60),
                child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 26),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: GreedyPalette.cream,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: won ? GreedyPalette.gold : GreedyPalette.woodOutline,
                    width: won ? 4 : 2.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'الجولة ${state.roundId}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: GreedyPalette.mutedText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: GreedyPalette.warmPale,
                        border: Border.all(
                            color: GreedyPalette.woodOutline, width: 3),
                      ),
                      child: Center(child: FoodIcon(state.resultSymbol!, size: 66)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${symbol?.nameAr ?? ''} — مضاعفة ${symbol?.multiplier ?? 0}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: GreedyPalette.darkText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!played)
                      const Text(
                        'لم تشارك في هذه الجولة',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: GreedyPalette.mutedText,
                        ),
                      )
                    else ...[
                      _resultLine('رهانك في هذه الجولة', state.myStaked, null),
                      _resultLine('فوز هذه الجولة', state.myPayout,
                          won ? const Color(0xFF1B8A54) : GreedyPalette.mutedText),
                      const Divider(color: GreedyPalette.warmPale, height: 16),
                      _resultLine(
                        'الصافي',
                        state.myNet,
                        state.myNet >= 0
                            ? const Color(0xFF1B8A54)
                            : GreedyPalette.deepRed,
                        signed: true,
                      ),
                    ],
                    if (!played) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'الجولة القادمة على وشك أن تبدأ',
                        style: TextStyle(
                          fontSize: 12,
                          color: GreedyPalette.mutedText,
                        ),
                      ),
                    ],
                    if (state.winners.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _winnersStrip(state.winners),
                    ],
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _dismissResult,
                      child: Container(
                        width: double.infinity,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [GreedyPalette.jackpotRed, GreedyPalette.deepRed],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: GreedyPalette.woodOutline, width: 2),
                        ),
                        child: const Center(
                          child: Text(
                            'متابعة',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
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
        ],
      ),
    );
  }

  Widget _resultLine(String label, int value, Color? colour, {bool signed = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: GreedyPalette.mutedText,
              ),
            ),
            const Spacer(),
            const CoinEmblem(size: 16),
            const SizedBox(width: 4),
            Text(
              signed && value > 0 ? '+${_fmt(value)}' : _fmt(value),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                color: colour ?? GreedyPalette.darkText,
              ),
            ),
          ],
        ),
      );

  /// «أكبر الفائزين» — the round's top three payouts, from the server. Real
  /// players, not fictional filler: the service ranks them at settlement.
  Widget _winnersStrip(List<GreedyWinner> winners) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: GreedyPalette.warmPale.withOpacity(0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GreedyPalette.creamDeep, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'أكبر الفائزين',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: GreedyPalette.mutedText,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < winners.length && i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    _rankBadge(i + 1),
                    const SizedBox(width: 6),
                    _avatar(winners[i].avatarUrl, winners[i].name, 22),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        winners[i].name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GreedyPalette.darkText,
                        ),
                      ),
                    ),
                    const CoinEmblem(size: 14),
                    const SizedBox(width: 3),
                    Text(
                      _compact(winners[i].payout),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1B8A54),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  /// 1 / 2 / 3 in gold, silver and bronze — rank by shape and colour, so it
  /// still reads for anyone who cannot separate the three hues.
  Widget _rankBadge(int rank) {
    const colours = [Color(0xFFFFD83D), Color(0xFFD7DDE4), Color(0xFFE2A96A)];
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colours[(rank - 1).clamp(0, 2)],
        border: Border.all(color: GreedyPalette.woodOutline, width: 1.4),
      ),
      child: Center(
        child: Text(
          '$rank',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            color: GreedyPalette.darkText,
          ),
        ),
      ),
    );
  }

  void _dismissResult() {
    final round = _resultRound;
    _sfx.modalClose();
    setState(() {
      _resultRound = null;
      if (round != null) _dismissedResult = round;
    });
  }
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/fruit_wheel_repository.dart';
import '../../services/device_tier.dart';
import '../wallet_screen.dart';
import 'fruit_wheel_art.dart';
import 'fruit_wheel_engine.dart';
import 'fruit_wheel_preferences.dart';
import 'fruit_wheel_sfx.dart';
import 'fruit_wheel_sheets.dart';
import 'fruit_wheel_strings.dart';

/// عجلة الفواكه (FRUIT WHEEL): stack chips on Watermelon ×2, 777 ×3 or
/// Plum ×2, spin, and the wheel stops on what the server already rolled.
class FruitWheelScreen extends ConsumerStatefulWidget {
  final FruitWheelRepository? repository;
  const FruitWheelScreen({super.key, this.repository});
  @override
  ConsumerState<FruitWheelScreen> createState() => FruitWheelScreenState();
}

enum FruitPhase { idle, spinning, revealing, bonus }

class FruitWheelScreenState extends ConsumerState<FruitWheelScreen> with TickerProviderStateMixin {
  late final FruitWheelRepository _repository = widget.repository ?? FruitWheelRepository();
  final _sfx = FruitWheelSfx();
  final _random = Random();
  late final AnimationController _spin = AnimationController(vsync: this);
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  Animation<double>? _spinAngle;
  FruitWheelPreferences? _preferences;
  Map<String, dynamic>? _layout;
  bool _loading = true, _arabic = true, _sound = true, _motion = true;
  String? _error, _notice;
  FruitPhase phase = FruitPhase.idle;
  double _angle = 0;
  int _lastTickSegment = 0;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  int? _highlight;
  int _chip = fruitChips.first;
  FruitBets bets = FruitBets();
  FruitBets? _lastBets;
  FruitRound? _result;
  int? _shownBalance;
  List<FruitRound> _history = [];
  List<String> _ticker = [];
  Map<String, int> _today = {for (final c in fruitCards) c: 0};
  int _rounds = 0;
  List<Map<String, dynamic>> _leaders = [];
  int? _myRank;
  int _myWon = 0;
  DateTime? _boardEnds;

  FruitWheelStrings get _s => FruitWheelStrings(_arabic);
  int get _balance => ref.read(authStateProvider).user?.coinsBalance ?? 0;
  int get _maxBet => (_layout?['maxBet'] as num?)?.toInt() ?? 300000;
  int get _minBet => (_layout?['minBet'] as num?)?.toInt() ?? 100;
  List<int> get _chips {
    final allowed = fruitChips.where((c) => c <= _maxBet).toList();
    return allowed.isEmpty ? [fruitChips.first] : allowed;
  }

  bool get _reduced => !_motion || MediaQuery.disableAnimationsOf(context);
  bool get _busy => phase != FruitPhase.idle;

  @override
  void initState() {
    super.initState();
    _spin.addListener(_onSpinFrame);
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient();
  }

  void _syncAmbient() {
    if (!_reduced && !DeviceTier.lite) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      _ambient.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _glow.dispose();
    _ambient.dispose();
    _sfx.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = ref.read(authStateProvider).user?.id.toString() ?? 'guest';
      final preferences = _preferences ??= FruitWheelPreferences(await SharedPreferences.getInstance(), account);
      if (!mounted) return;
      setState(() {
        _arabic = preferences.arabic;
        _sound = preferences.sound;
        _motion = preferences.motion;
        _sfx.enabled = _sound;
        _chip = preferences.chip;
        _lastBets = preferences.lastBets;
      });
      _syncAmbient();
      await _settlePending();
      final state = await _repository.fetchState();
      if (!mounted) return;
      final rounds = (state['history'] as List? ?? [])
          .map((r) => FruitRound.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      ref.read(authStateProvider.notifier).updateCoinsBalance((state['balance'] as num).toInt());
      setState(() {
        _layout = Map<String, dynamic>.from(state['layout'] as Map);
        if (!_chips.contains(_chip)) _chip = _chips.first;
        _history = preferences.visible(rounds);
        _ticker = rounds.take(fruitTickerLength).map((r) => r.outcome).toList();
        _rounds = (state['rounds'] as num?)?.toInt() ?? (rounds.isEmpty ? 0 : rounds.first.round);
        final today = (state['today'] as Map?)?['totals'];
        if (today is Map) {
          _today = {
            for (final c in fruitCards) c: (today[c] as num?)?.toInt() ?? 0,
          };
        }
        if (rounds.isNotEmpty) {
          _angle = fruitStopAngle(0, rounds.first.segment, rounds.first.offset, 0);
        }
        _loading = false;
      });
      unawaited(_loadLeaders());
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _s.text('error');
        });
      }
    }
  }

  /// A spin that went out before the app lost its connection or closed:
  /// replaying its key returns the committed round, or plays it exactly once.
  Future<void> _settlePending() async {
    final pending = _preferences?.pending;
    if (pending == null) return;
    try {
      await _repository.spin(pending.bets, requestId: pending.requestId);
      await _preferences!.savePending(null, null);
    } on FruitWheelException catch (e) {
      if (e.code != 'NETWORK') await _preferences!.savePending(null, null);
    }
  }

  Future<void> _loadLeaders() async {
    try {
      final board = await _repository.leaderboard();
      if (!mounted) return;
      setState(() {
        _leaders = (board['entries'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final me = board['me'] as Map?;
        _myRank = (me?['rank'] as num?)?.toInt();
        _myWon = (me?['won'] as num?)?.toInt() ?? 0;
        final ends = (board['endsIn'] as num?)?.toInt();
        _boardEnds = ends == null ? null : DateTime.now().add(Duration(milliseconds: ends));
      });
    } catch (_) {}
  }

  void _say(String? key) => setState(() => _notice = key == null ? null : _s.text(key));

  // ── Betting ───────────────────────────────────────────────────────────────
  void _pickChip(int chip) {
    if (_busy) return;
    _sfx.click();
    setState(() => _chip = chip);
    _preferences?.setChip(chip);
  }

  void placeChip(String card) {
    if (_busy || _layout == null) return;
    if (bets.total + _chip > _balance) return _say('INSUFFICIENT');
    if (!bets.add(card, _chip, _maxBet)) return _say('maxBet');
    _sfx.click();
    setState(() {
      _result = null;
      _highlight = null;
      _notice = null;
    });
  }

  void _clearBets() {
    if (_busy) return;
    _sfx.click();
    setState(() => bets.clear());
  }

  // ── A round ───────────────────────────────────────────────────────────────
  Future<void> spin() async {
    if (_busy || _layout == null) return;
    final stake = bets.isEmpty ? _lastBets?.copy() : bets.copy();
    if (stake == null) return _say('placeBets');
    if (stake.total < _minBet || stake.total > _maxBet) return _say('BAD_BET');
    if (stake.total > _balance) return _say('INSUFFICIENT');
    final requestId = const Uuid().v4();
    setState(() {
      phase = FruitPhase.spinning;
      bets = stake;
      _result = null;
      _highlight = null;
      _notice = null;
      _shownBalance = _balance - stake.total;
    });
    _glow.value = 0;
    _sfx.spin();
    FruitRound result;
    try {
      await _preferences?.savePending(requestId, stake);
      result = await _repository.spin(stake, requestId: requestId);
      await _preferences?.savePending(null, null);
    } on FruitWheelException catch (e) {
      if (e.code != 'NETWORK') await _preferences?.savePending(null, null);
      if (!mounted) return;
      setState(() {
        phase = FruitPhase.idle;
        _shownBalance = null;
        _notice = _s.text(e.code);
      });
      return;
    }
    if (!mounted) return;
    _lastBets = stake;
    unawaited(_preferences?.saveLastBets(stake));
    await _animateTo(result);
    if (!mounted) return;
    _reveal(result);
    if (result.isBonus && result.orbs != null && result.orbs!.length == 3) {
      setState(() => phase = FruitPhase.bonus);
      _sfx.bonus();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FruitBonusDialog(
          strings: _s,
          orbs: result.orbs!,
          prize: result.bonusPrize,
          sfx: _sfx,
        ),
      );
      if (!mounted) return;
    }
    _settle(result);
  }

  Future<void> _animateTo(FruitRound result) async {
    final plan = fruitSpinPlan(_random);
    final reduced = _reduced;
    final target = fruitStopAngle(
      _angle,
      result.segment,
      result.offset,
      reduced ? 0 : plan.turns,
    );
    _spinAngle = Tween<double>(begin: _angle, end: target).animate(
      CurvedAnimation(parent: _spin, curve: const Cubic(.12, .8, .18, 1)),
    );
    _lastTickSegment = fruitSegmentAt(_angle);
    _spin.duration = Duration(milliseconds: reduced ? 400 : plan.ms);
    // Completion, not the forward() future: skip() retargets the controller,
    // which cancels that future while the wheel is still turning.
    final done = Completer<void>();
    void finished(AnimationStatus status) {
      if (status == AnimationStatus.completed && !done.isCompleted) done.complete();
    }

    _spin.addStatusListener(finished);
    _spin.forward(from: 0);
    await done.future;
    _spin.removeStatusListener(finished);
  }

  void _onSpinFrame() {
    final anim = _spinAngle;
    if (anim == null) return;
    setState(() => _angle = anim.value);
    final segment = fruitSegmentAt(_angle);
    if (segment != _lastTickSegment) {
      _lastTickSegment = segment;
      final now = DateTime.now();
      if (now.difference(_lastTick).inMilliseconds > 45) {
        _lastTick = now;
        _sfx.tick();
      }
    }
  }

  /// Tapping the wheel only hurries the animation; the result is fixed.
  void skip() {
    if (phase != FruitPhase.spinning || !_spin.isAnimating) return;
    _spin.animateTo(1, duration: const Duration(milliseconds: 250));
  }

  void _reveal(FruitRound result) {
    _sfx.stop();
    setState(() {
      phase = FruitPhase.revealing;
      _highlight = result.segment;
      _result = result;
      _ticker = fruitPushTicker(_ticker, result.outcome);
      _history = [result, ..._history].take(50).toList();
      _rounds = max(_rounds + 1, result.round);
      for (final c in fruitCards) {
        _today[c] = (_today[c] ?? 0) + result.bets[c];
      }
    });
    if (_reduced) {
      _glow.value = 1;
    } else {
      _glow.forward(from: 0);
    }
  }

  void _settle(FruitRound result) {
    ref.read(authStateProvider.notifier).updateCoinsBalance(result.balance);
    if (result.totalPrize > 0) _sfx.win(result.totalPrize >= result.totalBet * 3);
    setState(() {
      phase = FruitPhase.idle;
      _shownBalance = null;
      bets = FruitBets();
      _notice = result.totalPrize > 0 ? '${_s.text('won')} ${result.totalPrize}' : _s.text('lost');
    });
    if (result.totalPrize > 0) unawaited(_loadLeaders());
  }

  // ── Settings ──────────────────────────────────────────────────────────────
  void _setArabic(bool v) {
    setState(() => _arabic = v);
    _preferences?.setSetting('arabic', v);
  }

  void _setSound(bool v) {
    setState(() => _sound = _sfx.enabled = v);
    _preferences?.setSetting('sound', v);
  }

  void _setMotion(bool v) {
    setState(() => _motion = v);
    _preferences?.setSetting('motion', v);
    _syncAmbient();
  }

  void _open(String key, Widget body) {
    if (_busy) return;
    _sfx.click();
    fruitSheet<void>(context, _s, _s.text(key), body);
  }

  void _openHelp() => _open(
        'help',
        FruitHelp(strings: _s, layout: _layout ?? const {}, repository: _repository),
      );
  void _openHistory() => _open('history', FruitHistory(strings: _s, rounds: _history));
  void _openLeaders() => _open(
        'leaders',
        FruitLeaders(
          strings: _s,
          entries: _leaders,
          myRank: _myRank,
          myWon: _myWon,
          resetsIn: _boardEnds?.difference(DateTime.now()),
        ),
      );
  void _openSettings() => _open(
        'settings',
        FruitSettings(
          strings: _s,
          sound: _sound,
          motion: _motion,
          onArabic: _setArabic,
          onSound: _setSound,
          onMotion: _setMotion,
          onClearHistory: () {
            _preferences?.clearHistory();
            setState(() => _history = []);
          },
        ),
      );

  // ── Layout ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final balance = _shownBalance ?? ref.watch(authStateProvider).user?.coinsBalance ?? 0;
    final userId = ref.watch(authStateProvider).user?.publicDisplayId;
    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: fwBlack,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _Backdrop(),
            SafeArea(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: fwGold),
                          const SizedBox(height: 12),
                          Text(_s.text('loading'), style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    )
                  : _error != null
                      ? _errorView()
                      : _game(balance, userId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: fwPink),
                onPressed: _boot,
                child: Text(_s.text('retry')),
              ),
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: Text(_s.text('back'), style: const TextStyle(color: fwMuted)),
              ),
            ],
          ),
        ),
      );

  /// One screen, no scrolling. The wheel spans the machine's full width
  /// (the button rails moved into the meta bar) unless the phone is short,
  /// in which case it takes the height that is left.
  Widget _game(int balance, int? userId) => LayoutBuilder(
        builder: (context, box) {
          final width = min(box.maxWidth, 560.0);
          // Fits one screen from 640 px tall; only tiny phones (iPhone SE 1st
          // gen) scroll, and then a 640-tall layout rather than a squashed one.
          return SingleChildScrollView(
            physics: box.maxHeight >= 640 ? const NeverScrollableScrollPhysics() : null,
            child: Center(
              child: SizedBox(
                width: width,
                height: max(box.maxHeight, 640),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    children: [
                      _header(balance),
                      _metaBar(userId),
                      const SizedBox(height: 6),
                      _socialStrip(),
                      const SizedBox(height: 8),
                      Expanded(child: _machine()),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _header(int balance) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            _RoundButton(
              icon: _arabic ? Icons.arrow_forward : Icons.arrow_back,
              label: _s.text('back'),
              onTap: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s.text('title'),
                    style: const TextStyle(
                      color: fwGold,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: fwPink, blurRadius: 8)],
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    label: '${_s.text('balance')}: $balance ${_s.text('coins')}',
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          const Icon(Icons.monetization_on, color: fwGold, size: 16),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '$balance',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _Pill(
              label: _s.text('recharge'),
              onTap: _busy
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      ),
            ),
          ],
        ),
      );

  Widget _metaBar(int? userId) {
    final soundIcon = _sound ? Icons.volume_up : Icons.volume_off;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 3, 4, 3),
      decoration: BoxDecoration(
        color: fwPurple.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: fwPurpleLight.withValues(alpha: .6)),
      ),
      child: Row(
        children: [
          Text(
            _s.round(_rounds + 1),
            style: const TextStyle(color: fwCream, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: '${_s.text('weekRank')}: ${_s.rank(_myRank)}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [fwCream, fwGold, fwGoldDark]),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events, color: fwPurpleDeep, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    _s.rank(_myRank),
                    style: const TextStyle(color: fwPurpleDeep, fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 6,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RoundButton(icon: Icons.people, label: _s.text('leaders'), onTap: _openLeaders, size: 34),
                  const SizedBox(width: 5),
                  _RoundButton(icon: Icons.question_mark, label: _s.text('help'), onTap: _openHelp, size: 34),
                  const SizedBox(width: 5),
                  _RoundButton(icon: Icons.receipt_long, label: _s.text('history'), onTap: _openHistory, size: 34),
                  const SizedBox(width: 5),
                  _RoundButton(
                    icon: soundIcon,
                    label: _s.text(_sound ? 'soundOff' : 'soundOn'),
                    onTap: () => _setSound(!_sound),
                    size: 34,
                  ),
                  const SizedBox(width: 5),
                  _RoundButton(icon: Icons.settings, label: _s.text('settings'), onTap: _openSettings, size: 34),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialStrip() => Semantics(
        button: true,
        label: _s.text('leaders'),
        child: GestureDetector(
          onTap: _openLeaders,
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [fwPurpleDeep.withValues(alpha: .9), fwPinkDark.withValues(alpha: .5)],
              ),
            ),
            child: _leaders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _s.text('emptyBoard'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: fwCream, fontSize: 14),
                      ),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    children: [
                      for (final e in _leaders.take(6))
                        SizedBox(
                          width: 64,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Tooltip(
                                message: e['name']?.toString() ?? '',
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(colors: [fwGold, fwPink]),
                                    boxShadow: [
                                      if (e == _leaders.first) const BoxShadow(color: fwGold, blurRadius: 8),
                                    ],
                                  ),
                                  child: fruitAvatar(
                                    e['avatar']?.toString(),
                                    e['name']?.toString() ?? '',
                                    34,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '🔥 ${fruitCompact((e['won'] as num?)?.toInt() ?? 0)}',
                                style: const TextStyle(color: fwGold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      );

  Widget _machine() => Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: fwGold, width: 2.5),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16072E), Color(0xFF5724A0)],
          ),
          boxShadow: [
            BoxShadow(color: fwBlueBright.withValues(alpha: .35), blurRadius: 18, spreadRadius: 1),
            const BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 10)),
          ],
        ),
        child: Column(
          children: [
            // The wheel takes every pixel the cards and chips leave.
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, square) {
                      final wheel = square.maxWidth;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(child: _wheel()),
                          // The round's outcome as a plaque over the bottom of the wheel.
                          if (_notice != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: wheel * .06,
                              child: IgnorePointer(
                                child: Center(
                                  child: TweenAnimationBuilder<double>(
                                    key: ValueKey(_notice),
                                    tween: Tween(begin: 0, end: 1),
                                    duration: Duration(milliseconds: _reduced ? 0 : 420),
                                    curve: Curves.easeOutBack,
                                    builder: (_, t, child) => Opacity(
                                      opacity: t.clamp(0.0, 1.0),
                                      child: Transform.scale(scale: .8 + .2 * t, child: child),
                                    ),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(18),
                                          color: const Color(0xEE1F0A3D),
                                          border: Border.all(color: fwGold, width: 1.5),
                                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                                        ),
                                        child: Text(
                                          _notice!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: fwCream,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _tickerView()),
                const SizedBox(width: 8),
                _spinButton(),
              ],
            ),
            const SizedBox(height: 8),
            _cards(),
            const SizedBox(height: 8),
            _chipRow(),
          ],
        ),
      );

  Widget _wheel() => AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = box.maxWidth;
            final r = size * .5 * .84 * .64;
            final symbol = size * .15;
            final center = _result != null && phase != FruitPhase.spinning
                ? '${_result!.totalPrize}'
                : phase == FruitPhase.spinning
                    ? '...'
                    : '0';
            return Semantics(
              label: phase == FruitPhase.spinning
                  ? _s.text('spinning')
                  : _result == null
                      ? _s.text('title')
                      : '${_s.text('outcome')}: ${_s.text(_result!.outcome)}',
              liveRegion: true,
              button: phase == FruitPhase.spinning,
              onTap: phase == FruitPhase.spinning ? skip : null,
              child: GestureDetector(
                onTap: skip,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_glow, _ambient]),
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size.square(size),
                        painter: FruitWheelPainter(
                          angle: _angle,
                          highlight: _highlight,
                          glow: _glow.value,
                          bulbPhase: phase == FruitPhase.spinning ? (_angle / (2 * pi)) % 1 : _ambient.value,
                        ),
                      ),
                      for (var i = 0; i < fruitSegments.length; i++)
                        Builder(
                          builder: (_) {
                            final a = _angle + (i + .5) * fruitSegmentAngle;
                            final pop = i == _highlight ? 1 + .25 * _glow.value : 1.0;
                            return Positioned(
                              left: size / 2 + r * sin(a) - symbol / 2,
                              top: size / 2 - r * cos(a) - symbol / 2,
                              child: Transform.scale(
                                scale: pop,
                                child: FruitArt(fruitSegments[i], size: symbol),
                              ),
                            );
                          },
                        ),
                      Positioned(
                        top: -size * .03,
                        left: size / 2 - size * .06,
                        child: CustomPaint(
                          size: Size(size * .12, size * .13),
                          painter: FruitPointerPainter(glow: _glow.value),
                        ),
                      ),
                      Positioned(
                        top: -size * .1,
                        left: size / 2 - size * .07,
                        child: FruitArt('crown', size: size * .14),
                      ),
                      Center(child: _hub(size * .27, center)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _hub(double size, String value) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [fwPurple, fwPurpleDeep]),
          border: Border.all(color: fwGold, width: size * .07),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.all(size * .12),
        child: FittedBox(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFFFF7A3A),
              fontSize: 30,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              shadows: [Shadow(color: fwRed, blurRadius: 8)],
            ),
          ),
        ),
      );

  Widget _tickerView() => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: const Color(0xFFD9D4E8), width: 1.5),
          gradient: const LinearGradient(colors: [fwPurpleDeep, fwPurple]),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: fwRed,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _s.text('new'),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _ticker.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    decoration: i == 0
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: fwGold.withValues(alpha: .8), blurRadius: 10)],
                          )
                        : null,
                    child: Semantics(
                      label: _s.text(_ticker[i]),
                      child: FruitArt(_ticker[i], size: i == 0 ? 34 : 28),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _spinButton() {
    final spinning = phase != FruitPhase.idle;
    final label = spinning
        ? '...'
        : bets.isEmpty
            ? _s.text('repeat')
            : _s.text('spin');
    final enabled = !spinning && (!bets.isEmpty || _lastBets != null);
    return Semantics(
      button: true,
      enabled: enabled,
      label: spinning ? _s.text('spinning') : label,
      child: _Pressable(
        onTap: enabled ? spin : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : .55,
          child: Container(
            width: 104,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(colors: [fwPink, Color(0xFF8E2BD6)]),
              border: Border.all(color: const Color(0xFFFFA6E3), width: 2),
              boxShadow: [
                BoxShadow(color: fwPink.withValues(alpha: .55), blurRadius: 14, offset: const Offset(0, 4)),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cards() => LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 300;
          final cardWidth = narrow ? 104.0 : (box.maxWidth - 16) / 3;
          final row = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final card in fruitCards) SizedBox(width: cardWidth, child: _card(card)),
            ],
          );
          return narrow
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: cardWidth * 3 + 16, child: row),
                )
              : row;
        },
      );

  Widget _card(String card) {
    final result = phase == FruitPhase.spinning ? null : _result;
    final mine = result?.bets[card] ?? bets[card];
    final won = result?.wonOn(card) ?? 0;
    final winning = result?.winner == card;
    final glow = winning ? _glow.value : 0.0;
    final bottom = won > 0 ? '+$won' : '$mine';
    return Semantics(
      button: true,
      label:
          '${_s.text(card)} ×${fruitMultipliers[card]}, ${_s.text('yourBet')}: $mine${won > 0 ? ', ${_s.text('won')} $won' : ''}',
      child: _Pressable(
        onTap: _busy ? null : () => placeChip(card),
        child: AnimatedBuilder(
          animation: _glow,
          builder: (context, _) => Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6A23B8), fwPurpleDeep],
              ),
              border: Border.all(color: winning ? fwCream : fwGold, width: winning ? 3 : 2),
              boxShadow: [
                if (winning) BoxShadow(color: fwGold.withValues(alpha: .8 * glow), blurRadius: 18, spreadRadius: 2),
                const BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: _s.text('today'),
                  child: Text(
                    fruitCompact(_today[card] ?? 0),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 2),
                FruitArt('capsule_$card', size: 58),
                Text(
                  'x${fruitMultipliers[card]}',
                  style: const TextStyle(
                    color: fwGold,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: fwGoldDark, offset: Offset(0, 2))],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: Text(
                    bottom,
                    key: ValueKey(bottom),
                    style: TextStyle(
                      color: won > 0 ? fwGreen : fwCream,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
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

  Widget _chipRow() => Row(
        children: [
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in _chips)
                  _Chip(
                    value: chip,
                    selected: chip == _chip,
                    onTap: _busy ? null : () => _pickChip(chip),
                  ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: _s.text('clear'),
            child: IconButton(
              tooltip: _s.text('clear'),
              onPressed: _busy || bets.isEmpty ? null : _clearBets,
              icon: const Icon(Icons.backspace_outlined),
              color: fwCream,
              disabledColor: fwMuted.withValues(alpha: .4),
            ),
          ),
        ],
      );
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();
  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [fwBlack, Color(0xFF210B44), Color(0xFF2B0F57)],
              ),
            ),
          ),
          Image.asset(
            'assets/images/games/fruit_wheel/background.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  const _RoundButton({required this.icon, required this.label, this.onTap, this.size = 44});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: fwPurple,
            shape: CircleBorder(side: BorderSide(color: fwPurpleLight.withValues(alpha: .9), width: 2)),
            elevation: 4,
            shadowColor: fwPurpleLight,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: size,
                child: Icon(icon, color: Colors.white, size: size * .48),
              ),
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _Pill({required this.label, this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: _Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [fwGold, Color(0xFFFF9F1C)]),
              boxShadow: [BoxShadow(color: fwGold.withValues(alpha: .5), blurRadius: 8)],
            ),
            child: Text(
              label,
              style: const TextStyle(color: fwPurpleDeep, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback? onTap;
  const _Chip({required this.value, required this.selected, this.onTap});
  static const _colors = {
    100: [Color(0xFF19BFFF), Color(0xFF0753BD)],
    1000: [Color(0xFF39D26B), Color(0xFF117A3A)],
    10000: [Color(0xFFF531B8), Color(0xFF9F147E)],
    100000: [Color(0xFFFFD332), Color(0xFFA75F0D)],
  };
  @override
  Widget build(BuildContext context) {
    final label = value >= 1000 ? '${value ~/ 1000}K' : '$value';
    final size = selected ? 52.0 : 44.0;
    return Semantics(
      button: true,
      selected: selected,
      label: '$value',
      child: _Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: _colors[value] ?? _colors[100]!),
            border: Border.all(color: selected ? Colors.white : fwCream.withValues(alpha: .6), width: selected ? 3 : 2),
            boxShadow: [
              if (selected) BoxShadow(color: Colors.white.withValues(alpha: .6), blurRadius: 10),
              const BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

/// Shrinks 3% while pressed, like a physical button.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      );
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/yummy_repository.dart';
import '../../services/device_tier.dart';
import 'yummy_bonus.dart';
import 'yummy_celebration.dart';
import 'yummy_engine.dart';
import 'yummy_fairness.dart';
import 'yummy_fx.dart';
import 'yummy_grid.dart';
import 'yummy_help.dart';
import 'yummy_preferences.dart';
import 'yummy_sfx.dart';
import 'yummy_social.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

class YummyScreen extends ConsumerStatefulWidget {
  final YummyRepository? repository;
  const YummyScreen({super.key, this.repository});
  @override
  ConsumerState<YummyScreen> createState() => _YummyScreenState();
}

/// Free spins in progress: which spin is showing and what they paid so far.
class _FreeState {
  final int count, multiplier;
  int spin = 0, total = 0;
  _FreeState(this.count, this.multiplier);
}

class _YummyScreenState extends ConsumerState<YummyScreen>
    with TickerProviderStateMixin {
  late final YummyRepository _repository =
      widget.repository ?? YummyRepository();
  final _sfx = YummySfx();
  final _random = Random();
  final _machine = GlobalKey<YummyMachineState>();
  late final YummyClock _clock = YummyClock(this);
  final bool _lite = DeviceTier.lite;
  int _spinId = 0;
  // While a round plays out the badge shows the pre-spin balance minus the
  // stake, so the server's settled balance never spoils the result early.
  int? _shownBalance;
  // The prize counter climbs with each tumble instead of jumping to the total.
  int _shownPrize = 0;
  int _ladder = -1;
  YummyWinTier _tier = YummyWinTier.none;
  int _tierPrize = 0;
  Completer<void>? _celebrating, _intro, _summary;
  _FreeState? _free;
  YummyRound? _summaryRound;
  YummyAutoplay? _auto;
  YummyPreferences? _preferences;
  Map<String, dynamic>? _layout;
  Map<String, dynamic>? _pending;
  List<YummyRound> _history = [];
  late final List<String> _initial =
      List.generate(15, (index) => yummySymbolIds[index % 8]);
  YummyRound? _last;
  bool _loading = true,
      _busy = false,
      _skipped = false,
      _arabic = true,
      _motion = true,
      _sound = true,
      _turbo = false;
  int _bet = 100, _lines = 9;
  String? _notice;
  YummyStrings get _strings => YummyStrings(_arabic);
  int get _balance => ref.read(authStateProvider).user?.coinsBalance ?? 0;
  int get _totalBet => yummyTotalBet(_bet, _lines);
  bool get _locked => _busy || _pending != null || _auto != null;
  List<int> get _steps => List<int>.from(
        _layout?['betSteps'] as List? ?? [10, 20, 50, 100, 200, 500, 1000],
      );
  bool get _reduced =>
      !_motion ||
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.of(context).accessibleNavigation;
  bool get _ambient => !_reduced && !_lite;
  YummyClock? get _ambientClock => _ambient ? _clock : null;
  YummyMachineState? get _m => _machine.currentState;
  List<int> get _ladderSteps => List<int>.from(
        _layout?['tumbleMultipliers'] as List? ?? yummyTumbleMultipliers,
      );

  @override
  void initState() {
    super.initState();
    YummyShaders.load();
    YummyWinFeed.instance.listen();
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  /// The ambient clock runs only with motion on and a phone that can afford it.
  void _syncClock() {
    _clock.enabled = _ambient;
    if (_ambient) {
      _clock.wake();
    } else {
      _clock.sleep();
    }
  }

  @override
  void dispose() {
    _auto = null;
    for (final completer in [_celebrating, _intro, _summary]) {
      if (completer?.isCompleted == false) completer!.complete();
    }
    _clock.dispose();
    _sfx.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() => _loading = true);
    try {
      final storage = await SharedPreferences.getInstance();
      if (!mounted) return;
      final account =
          ref.read(authStateProvider).user?.id.toString() ?? 'guest';
      final preferences = YummyPreferences(storage, account);
      setState(() {
        _preferences = preferences;
        _arabic = preferences.arabic;
        _motion = preferences.motion;
        _sound = preferences.sound;
        _turbo = preferences.turbo;
        _sfx.enabled = _sound;
        _history = preferences.history;
        _pending = preferences.pending;
      });
      _syncClock();
      final state = await _repository.fetchState();
      if (!mounted) return;
      final rounds = (state['history'] as List)
          .map(
            (row) => YummyRound.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      ref
          .read(authStateProvider.notifier)
          .updateCoinsBalance((state['balance'] as num).toInt());
      setState(() {
        _layout = Map<String, dynamic>.from(state['layout'] as Map);
        _history = preferences.visible(rounds);
        _last = rounds.isEmpty ? null : rounds.first;
        _shownPrize = _last?.totalPrize ?? 0;
        if (_pending != null) {
          _bet = _pending!['betPerLine'] as int;
          _lines = _pending!['activeLines'] as int;
        } else {
          _selectAllowedBet();
        }
        _notice = null;
      });
      _m?.setBoard(_last?.finalGrid ?? yummyDecorativeGrid(_random));
      await preferences.saveHistory(_history);
      unawaited(_loadFeed());
    } catch (_) {
      if (mounted) setState(() => _notice = _strings.text('error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFeed() async {
    try {
      YummyWinFeed.instance.seed(await _repository.feed());
    } catch (_) {}
  }

  bool _allowed(int bet, int lines) {
    final total = bet * lines;
    return total >= (_layout?['minBet'] as num? ?? 10) &&
        total <= (_layout?['maxBet'] as num? ?? 9000);
  }

  void _selectAllowedBet() {
    if (_steps.contains(_bet) && _allowed(_bet, _lines)) return;
    for (final bet in _steps) {
      for (var lines = 9; lines >= 1; lines--) {
        if (_allowed(bet, lines)) {
          _bet = bet;
          _lines = lines;
          return;
        }
      }
    }
  }

  void _changeBet(int direction) {
    final index = _steps.indexOf(_bet) + direction;
    if (!_locked &&
        index >= 0 &&
        index < _steps.length &&
        _allowed(_steps[index], _lines)) {
      setState(() => _bet = _steps[index]);
      _sfx.click();
    }
  }

  void _maximum() {
    for (final bet in _steps.reversed) {
      for (var lines = 9; lines >= 1; lines--) {
        if (_allowed(bet, lines)) {
          setState(() {
            _bet = bet;
            _lines = lines;
          });
          _sfx.click();
          return;
        }
      }
    }
  }

  /// STOP: skips the animation of the current step. The round itself was
  /// settled by the server before anything moved.
  void _stop() {
    _skipped = true;
    _m?.skip();
  }

  Future<void> _pause(double seconds) async {
    if (_reduced || _skipped || seconds <= 0) return;
    await Future<void>.delayed(
      Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  Future<void> _spin() async {
    if (_busy || _loading || _layout == null) return;
    if (_pending == null) {
      if (_layout!['enabled'] == false || !_allowed(_bet, _lines)) {
        setState(() => _notice = _strings.text('disabled'));
        _auto = null;
        return;
      }
      if (!yummyCanSpin(_balance, _bet, _lines)) {
        setState(() {
          _notice = _strings.text('lowBalance');
          _auto = null;
        });
        return;
      }
      _pending = {
        'requestId': const Uuid().v4(),
        'betPerLine': _bet,
        'activeLines': _lines,
      };
    }
    final stake =
        (_pending!['betPerLine'] as int) * (_pending!['activeLines'] as int);
    final machine = _m;
    machine?.pace = _turbo ? YummyPace.turbo : YummyPace.normal;
    setState(() {
      _busy = true;
      _skipped = false;
      _notice = null;
      _spinId++;
      _ladder = -1;
      _shownPrize = 0;
      _tier = YummyWinTier.none;
      _shownBalance = max(0, _balance - stake);
    });
    _clock.busy = true;
    machine?.startSpin();
    if (!_reduced) _sfx.spinStart();
    final started = DateTime.now();
    YummyRound? settled;
    try {
      await _preferences!.savePending(_pending);
      final result = await _repository.spin(
        _pending!['betPerLine'] as int,
        _pending!['activeLines'] as int,
        requestId: _pending!['requestId'] as String,
      );
      if (!mounted) return;
      ref.read(authStateProvider.notifier).updateCoinsBalance(result.balance);
      await _preferences!.savePending(null);
      if (!mounted) return;
      _pending = null;
      settled = result;
      await _present(
        result,
        DateTime.now().difference(started).inMilliseconds / 1000,
      );
      if (!mounted) return;
      setState(() {
        _last = result;
        _shownBalance = null;
        _shownPrize = result.totalPrize;
        _history = [result, ..._history.where((round) => round.id != result.id)]
            .take(50)
            .toList();
      });
      await _preferences!.saveHistory(_history);
      if (result.totalPrize >= result.totalBet * 50 ||
          result.jackpotTriggered) {
        // Our own big win shows on our ticker at once; others get the
        // server's broadcast.
        final user = ref.read(authStateProvider).user;
        YummyWinFeed.instance.add({
          'game': 'yummy',
          'userId': user?.id ?? 0,
          'name': user?.name ?? '',
          'prize': result.totalPrize,
          'x': result.totalPrize / result.totalBet,
          'tier': result.jackpotTriggered ? 'jackpot' : 'big',
        });
      }
    } catch (error) {
      if (!mounted) return;
      _auto = null;
      final code = error is YummyException ? error.code : 'NETWORK';
      if (![
        'NETWORK',
        'SPIN_FAILED',
        'FAILED',
        'REQUEST_IN_PROGRESS',
        'IDEMPOTENCY_UNAVAILABLE',
      ].contains(code)) {
        _pending = null;
        await _preferences?.savePending(null);
      }
      _m?.setBoard(_m?.board ?? _initial);
      if (mounted) {
        setState(
          () => _notice = _strings.text(
            code == 'INSUFFICIENT'
                ? 'lowBalance'
                : code == 'GAME_DISABLED'
                    ? 'disabled'
                    : 'error',
          ),
        );
      }
      // The server knows the real balance (gifts, other games); resync so the
      // badge stops promising coins that are not there.
      if (code == 'INSUFFICIENT') unawaited(_refreshBalance());
    } finally {
      _sfx.spinEnd();
      _clock.busy = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _shownBalance = null;
          _free = null;
        });
      }
    }
    if (mounted && settled != null) _continueAuto(settled);
  }

  void _continueAuto(YummyRound round) {
    final auto = _auto;
    if (auto == null) return;
    final keepGoing = auto.next(
      balance: round.balance,
      totalBet: round.totalBet,
      prize: round.totalPrize,
      freeSpins: round.freeSpins != null,
    );
    if (!keepGoing) {
      setState(() {
        _auto = null;
        _notice = _strings.text('autoStopped');
      });
      return;
    }
    setState(() {});
    Future<void>.delayed(Duration(milliseconds: _turbo ? 120 : 350), () {
      if (mounted && _auto == auto && !_busy) _spin();
    });
  }

  /// Replays a settled round: reels, then every tumble, then free spins.
  Future<void> _present(YummyRound result, double elapsed) async {
    final machine = _m;
    if (machine == null) return;
    await machine.land(result.grid, elapsed: elapsed);
    _sfx.spinEnd();
    if (!mounted) return;
    final base = await _playTumbles(result.tumbles, cap: result.totalPrize);
    if (!mounted) return;
    setState(() => _shownPrize = min(base, result.totalPrize));
    final tier = yummyWinTier(
      result.baseShown,
      result.totalBet,
      result.jackpotTriggered,
    );
    if (tier != YummyWinTier.none) {
      _sfx.bigWin();
      await _celebrate(tier, result.baseShown);
    } else if (result.baseShown >= result.totalBet * 3) {
      machine.coinBurst();
      _sfx.coins();
    }
    if (!mounted) return;
    final free = result.freeSpins;
    if (free != null) await _playFreeSpins(result, free);
  }

  /// Plays one spin's tumble chain on the machine. Returns what it paid.
  Future<int> _playTumbles(
    List<YummyTumble> tumbles, {
    int offset = 0,
    int? cap,
  }) async {
    final machine = _m;
    var paid = 0;
    for (var index = 0; index < tumbles.length; index++) {
      if (!mounted || machine == null) return paid;
      final step = tumbles[index];
      if (step.wins.isEmpty) break;
      paid += step.prize;
      setState(() {
        _ladder = index;
        _shownPrize = cap == null ? offset + paid : min(offset + paid, cap);
      });
      if (step.wins.any((w) => w.symbol == 'jackpot' || w.symbol == 'wild')) {
        _sfx.expand();
      }
      _sfx.win();
      await machine.showWins(
        step.wins,
        label: step.multiplier > 1
            ? '+${step.prize}  ×${step.multiplier}'
            : '+${step.prize}',
        hold: _turbo ? .5 : .95,
      );
      if (step.removed.isEmpty || index + 1 >= tumbles.length) break;
      _sfx.tumblePop();
      await machine.pop(step.removed);
      await machine.collapse(tumbles[index + 1].grid, step.removed);
    }
    return paid;
  }

  Future<void> _playFreeSpins(YummyRound result, YummyFreeSpins free) async {
    final machine = _m;
    if (machine == null) return;
    _sfx.freeSpinsIntro();
    _intro = Completer<void>();
    setState(() => _free = _FreeState(free.count, free.multiplier));
    await _intro!.future;
    if (!mounted) return;
    _intro = null;
    _sfx.freeSpinsMusic();
    final state = _free!;
    for (var index = 0; index < free.spins.length; index++) {
      if (!mounted) return;
      final spin = free.spins[index];
      setState(() {
        state.spin = index + 1;
        _ladder = -1;
        _skipped = false;
      });
      machine.startSpin();
      await machine.land(spin.landed);
      if (!mounted) return;
      if (spin.expandedReels.isNotEmpty) {
        _sfx.expand();
        await machine.expand(spin.expandedReels);
      }
      final paid = await _playTumbles(
        spin.tumbles,
        offset: result.baseShown + state.total,
        cap: result.totalPrize,
      );
      if (!mounted) return;
      setState(() => state.total += paid);
      await _pause(_turbo ? .15 : .4);
    }
    _sfx.freeSpinsEnd();
    if (!mounted) return;
    _summaryRound = result;
    _summary = Completer<void>();
    setState(() {});
    _sfx.bigWin();
    await _summary!.future;
    if (!mounted) return;
    _summary = null;
    setState(() {
      _summaryRound = null;
      _free = null;
      _ladder = -1;
    });
    machine.setBoard(result.finalGrid);
  }

  Future<void> _celebrate(YummyWinTier tier, int prize) async {
    _celebrating = Completer<void>();
    setState(() {
      _tier = tier;
      _tierPrize = prize;
    });
    await _celebrating!.future;
  }

  Future<void> _refreshBalance() async {
    try {
      final state = await _repository.fetchState();
      if (!mounted) return;
      ref
          .read(authStateProvider.notifier)
          .updateCoinsBalance((state['balance'] as num).toInt());
    } catch (_) {}
  }

  void _endCelebration() {
    if (!mounted) return;
    setState(() => _tier = YummyWinTier.none);
    if (_celebrating?.isCompleted == false) _celebrating!.complete();
  }

  void _startFree() {
    if (_intro?.isCompleted == false) _intro!.complete();
  }

  void _endSummary() {
    if (_summary?.isCompleted == false) _summary!.complete();
  }

  Future<void> _setting(String key, bool value) async {
    setState(() {
      if (key == 'arabic') _arabic = value;
      if (key == 'sound') {
        _sound = value;
        _sfx.set(value);
      }
      if (key == 'turbo') _turbo = value;
      if (key == 'motion') {
        _motion = value;
        if (!value) _stop();
      }
    });
    _syncClock();
    await _preferences?.setSetting(key, value);
  }

  Future<void> _openAutoplay() async {
    if (_auto != null) {
      setState(() {
        _auto = null;
        _notice = _strings.text('autoStopped');
      });
      return;
    }
    if (_busy || _layout == null) return;
    final settings = await showModalBottomSheet<YummyAutoSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF3FAFF),
      builder: (context) => Directionality(
        textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _strings.text('autoplay'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: yummyInk,
                    ),
                  ),
                  YummyAutoplaySheet(strings: _strings, totalBet: _totalBet),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (settings == null || !mounted) return;
    setState(() => _auto = YummyAutoplay(settings, _balance));
    unawaited(_spin());
  }

  Future<void> _settings() => yummySheet(
        context,
        _strings.text('settings'),
        StatefulBuilder(
          builder: (context, refresh) => Column(
            children: [
              SwitchListTile(
                title: Text(_strings.text('sound')),
                value: _sound,
                onChanged: (value) async {
                  await _setting('sound', value);
                  refresh(() {});
                },
              ),
              SwitchListTile(
                title: Text(_strings.text('motion')),
                value: _motion,
                onChanged: (value) async {
                  await _setting('motion', value);
                  refresh(() {});
                },
              ),
              SwitchListTile(
                title: Text(_strings.text('turbo')),
                value: _turbo,
                onChanged: (value) async {
                  await _setting('turbo', value);
                  refresh(() {});
                },
              ),
              SwitchListTile(
                title: Text('${_strings.text('language')} · العربية'),
                value: _arabic,
                onChanged: (value) async {
                  await _setting('arabic', value);
                  refresh(() {});
                },
              ),
              TextButton(
                onPressed: () async {
                  await _preferences?.clearHistory();
                  if (mounted) setState(() => _history = []);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(_strings.text('clear')),
              ),
              Text(
                _strings.text('responsible'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(_strings.text('responsibleBody')),
            ],
          ),
        ),
        _strings,
      );
  Future<void> _showHistory() => yummySheet(
        context,
        _strings.text('history'),
        Column(
          children: [
            if (_history.isEmpty) Text(_strings.text('empty')),
            for (final round in _history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '#${round.nonce} · ${round.totalPrize >= round.totalBet ? _strings.text('win') : _strings.text('loss')} · ${round.at.toLocal().toString().split('.').first}',
                ),
                subtitle: Text(
                  '${_strings.text('totalBet')}: ${round.totalBet}   ${_strings.text('prize')}: ${round.totalPrize}'
                  '${round.freeSpins != null ? '   🎁 ${round.freeSpins!.count}' : ''}'
                  '${round.tumbleChain > 1 ? '   ${_strings.text('tumble')} ×${round.tumbleChain}' : ''}'
                  '\n${_strings.text('balance')}: ${round.balance}',
                ),
                trailing: IconButton(
                  tooltip: _strings.text('fairness'),
                  icon: const Icon(Icons.verified_user_outlined),
                  onPressed: () => _fairness(round),
                ),
              ),
          ],
        ),
        _strings,
      );
  Future<void> _fairness([YummyRound? round]) => yummySheet(
        context,
        _strings.text('fairness'),
        YummyFairness(
          repository: _repository,
          strings: _strings,
          round: round ?? _last,
        ),
        _strings,
      );
  Future<void> _stats() => yummySheet(
        context,
        _strings.text('stats'),
        Column(
          children: [
            for (final entry in {
              'rounds': _history.length,
              'wagered':
                  _history.fold<int>(0, (sum, round) => sum + round.totalBet),
              'returned':
                  _history.fold<int>(0, (sum, round) => sum + round.totalPrize),
              'net': _history.fold<int>(
                0,
                (sum, round) => sum + round.totalPrize - round.totalBet,
              ),
            }.entries)
              ListTile(
                title: Text(_strings.text(entry.key)),
                trailing: Text(
                  '${entry.value}',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
          ],
        ),
        _strings,
      );
  Future<void> _leaderboard() => yummySheet(
        context,
        _strings.text('leaderboard'),
        YummyLeaderboard(
          repository: _repository,
          strings: _strings,
          userId: ref.read(authStateProvider).user?.id,
        ),
        _strings,
      );
  Future<void> _missions() => yummySheet(
        context,
        _strings.text('missions'),
        YummyMissions(repository: _repository, strings: _strings),
        _strings,
      );

  Widget _icon(IconData icon, String label, VoidCallback? action) => IconButton(
        tooltip: _strings.text(label),
        onPressed: action,
        icon: Icon(icon),
        color: Colors.white,
        style: IconButton.styleFrom(
          backgroundColor: yummyDeep.withValues(alpha: .9),
          minimumSize: const Size(44, 44),
          side: const BorderSide(color: Color(0x55FFFFFF)),
        ),
      );
  Widget _metric(String label, int value, {bool glow = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _strings.text(label),
            style: const TextStyle(fontSize: 11, color: Color(0xCCFFFFFF)),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: value.toDouble()),
            duration: _reduced || !glow
                ? Duration.zero
                : const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, shown, _) => Text(
              '${shown.round()}',
              style: TextStyle(
                fontSize: 20,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: yummyGold,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: glow && value > 0
                    ? const [Shadow(color: Color(0xAAFFB300), blurRadius: 10)]
                    : null,
              ),
            ),
          ),
        ],
      );
  Widget _stepper(
    String label,
    int value,
    VoidCallback? minus,
    VoidCallback? plus,
  ) {
    Widget step(IconData icon, String tip, VoidCallback? action) => Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: action,
            child: Opacity(
              opacity: action == null ? .35 : 1,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFF3A0), yummyGold, Color(0xFFFF9A25)],
                  ),
                ),
                child: Icon(icon, size: 20, color: yummyInk),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2F8BFF), yummyDeep, Color(0xFF053E8F)],
        ),
        border: Border.all(color: const Color(0x99FFFFFF), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55043180),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _strings.text(label),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xDDFFFFFF),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              step(
                Icons.remove_rounded,
                '${_strings.text('decrease')} ${_strings.text(label)}',
                minus,
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              step(
                Icons.add_rounded,
                '${_strings.text('increase')} ${_strings.text(label)}',
                plus,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// JACKPOT amount plus the tumble ladder (×1 ×2 ×3 ×5) lighting up.
  Widget _banner(YummyStrings strings) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6A2FB3), Color(0xFF44227A), Color(0xFF241047)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: yummyGold, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0x66FFD529), blurRadius: 16),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  '${yummyArt}jackpot.png',
                  width: 36,
                  height: 36,
                  cacheWidth: 120,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) =>
                      const Text('👑', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFFBD0),
                          yummyGold,
                          Color(0xFFFF9A25),
                        ],
                      ).createShader(bounds),
                      child: Text(
                        '${strings.text('jackpot')}  ${_bet * 1000}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Color(0x88000000),
                              offset: Offset(0, 2),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Semantics(
              label:
                  '${strings.text('tumble')} ${strings.text('multiplier')} ${_ladder < 0 ? 1 : _ladderSteps[min(_ladder, _ladderSteps.length - 1)]}',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _ladderSteps.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: _ladder >= i ? yummyGold : Colors.white38,
                      ),
                    YummyMultiplierBadge(
                      multiplier: _ladderSteps[i] * (_free?.multiplier ?? 1),
                      active: _ladder == i ||
                          (i == _ladderSteps.length - 1 && _ladder >= i),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  /// The big round SPIN. Long press opens autoplay.
  Widget _spinButton(YummyStrings strings) {
    final auto = _auto;
    final stopping = _busy || auto != null;
    final label = auto != null
        ? '${strings.text('stop')} · ${auto.left}'
        : strings.text(
            _busy
                ? 'stop'
                : _pending != null || _layout == null
                    ? 'retry'
                    : 'spin',
          );
    final VoidCallback? action = _loading
        ? null
        : auto != null
            ? () => setState(() => _auto = null)
            : _busy
                ? _stop
                : _layout == null
                    ? _boot
                    : _spin;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: action,
        onLongPress:
            _busy || _layout == null || auto != null ? null : _openAutoplay,
        child: _Squash(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-.3, -.4),
                colors: stopping
                    ? const [
                        Color(0xFFFFB3C8),
                        Color(0xFFFF4F86),
                        Color(0xFFC2134D),
                      ]
                    : const [Color(0xFFFFFBD0), yummyGold, Color(0xFFFF8A00)],
                stops: const [0, .55, 1],
              ),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: (stopping
                          ? const Color(0xFFE72965)
                          : const Color(0xFFFF9A25))
                      .withValues(alpha: .7),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: stopping ? Colors.white : yummyInk,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle(IconData icon, String label, bool on, VoidCallback? action) =>
      Expanded(
        child: GestureDetector(
          onTap: action,
          child: Opacity(
            opacity: action == null ? .5 : 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: on
                      ? const [Color(0xFFFFF3A0), yummyGold, Color(0xFFFF9A25)]
                      : const [Color(0xDD2F8BFF), Color(0xDD0753BD)],
                ),
                border: Border.all(
                  color: on ? Colors.white : const Color(0x88FFFFFF),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: on ? yummyInk : Colors.white),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _strings.text(label),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: on ? yummyInk : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(authStateProvider).user?.coinsBalance ?? 0;
    final strings = _strings;
    final free = _free;
    final clock = _ambientClock;
    final summary = _summaryRound;
    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: yummyDeep),
          textTheme: Theme.of(context)
              .textTheme
              .apply(bodyColor: yummyInk, displayColor: yummyInk),
        ),
        child: Scaffold(
          backgroundColor: yummySky,
          body: Listener(
            onPointerDown: (_) => _clock.wake(),
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              child: Actions(
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      if (_busy) {
                        _stop();
                      } else {
                        _spin();
                      }
                      return null;
                    },
                  ),
                },
                child: Focus(
                  autofocus: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: YummyBackdrop(
                          clock: clock,
                          freeSpins: free != null,
                        ),
                      ),
                      SafeArea(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                              child: _stage(strings, balance, clock, free),
                            ),
                          ),
                        ),
                      ),
                      if (_intro != null && free != null)
                        Positioned.fill(
                          child: YummyFreeSpinsIntro(
                            key: ValueKey('intro-$_spinId'),
                            count: free.count,
                            multiplier: free.multiplier,
                            strings: strings,
                            reduced: _reduced,
                            lite: _lite,
                            autoStart: Duration(
                              seconds: _auto != null || _turbo ? 2 : 6,
                            ),
                            onStart: _startFree,
                          ),
                        ),
                      if (summary != null && summary.freeSpins != null)
                        Positioned.fill(
                          child: YummyFreeSpinsSummary(
                            key: ValueKey('summary-$_spinId'),
                            total: summary.freeSpinsShown,
                            count: summary.freeSpins!.count,
                            capped: summary.capped,
                            strings: strings,
                            reduced: _reduced,
                            lite: _lite,
                            onDone: _endSummary,
                          ),
                        ),
                      if (_tier != YummyWinTier.none)
                        Positioned.fill(
                          child: YummyCelebration(
                            key: ValueKey('celebrate-$_spinId'),
                            tier: _tier,
                            prize: _tierPrize,
                            strings: strings,
                            reduced: _reduced,
                            lite: _lite,
                            onDone: _endCelebration,
                          ),
                        ),
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

  /// One screen, no scrolling: HUD, logo and jackpot ladder, the machine as
  /// the hero, a win meter, and the control dock. The machine takes whatever
  /// height is left; the logo only shows when there is room for it.
  Widget _stage(
    YummyStrings strings,
    int balance,
    YummyClock? clock,
    _FreeState? free,
  ) =>
      LayoutBuilder(
        builder: (context, box) {
          const hud = 46.0, banner = 100.0, meter = 54.0, dock = 74.0;
          const toggles = 40.0, gaps = 34.0;
          // The cabinet adds 32 px of frame around a 5:3 reel window.
          final reelsByWidth = (box.maxWidth - 32) * 3 / 5 + 32;
          final room =
              box.maxHeight - hud - banner - meter - dock - toggles - gaps;
          final machineH = min(reelsByWidth, room);
          final machineW = (machineH - 32) * 5 / 3 + 32;
          final logo = (room - machineH).clamp(0.0, 140.0);
          return Column(
            children: [
              SizedBox(height: hud, child: _hud(strings, balance, clock)),
              if (logo >= 40) YummyLogo(clock: clock, height: logo),
              const SizedBox(height: 4),
              SizedBox(
                height: banner,
                // Scales down rather than overflow on short or narrow phones.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: box.maxWidth,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: free != null && free.spin > 0
                          ? YummyFreeSpinsHud(
                              key: const ValueKey('hud'),
                              spin: free.spin,
                              count: free.count,
                              multiplier: free.multiplier,
                              total: free.total,
                              strings: strings,
                            )
                          : KeyedSubtree(
                              key: const ValueKey('banner'),
                              child: _banner(strings),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: min(box.maxWidth, machineW),
                    child: YummyMachine(
                      key: _machine,
                      initial: _initial,
                      strings: strings,
                      clock: clock,
                      reduced: _reduced,
                      lite: _lite,
                      freeSpins: free != null,
                      onReelStop: (reel, column) {
                        _sfx.reelStop(reel);
                        if (column.contains('bonus') ||
                            column.contains('jackpot')) {
                          _sfx.bonusLand();
                        }
                      },
                      onAnticipate: _sfx.anticipation,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(height: meter, child: _meter(strings)),
              const SizedBox(height: 8),
              SizedBox(height: dock, child: _dock(strings)),
              const SizedBox(height: 6),
              SizedBox(
                height: toggles,
                child: Row(
                  children: [
                    _toggle(
                      Icons.vertical_align_top_rounded,
                      'maximum',
                      false,
                      _locked || _layout == null ? null : _maximum,
                    ),
                    const SizedBox(width: 8),
                    _toggle(
                      Icons.autorenew,
                      'auto',
                      _auto != null,
                      _layout == null || (_busy && _auto == null)
                          ? null
                          : _openAutoplay,
                    ),
                    const SizedBox(width: 8),
                    _toggle(
                      Icons.bolt,
                      'turbo',
                      _turbo,
                      () => _setting('turbo', !_turbo),
                    ),
                  ],
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
            ],
          );
        },
      );

  Widget _hud(YummyStrings strings, int balance, YummyClock? clock) => Row(
        children: [
          _icon(Icons.arrow_back, 'back', () => Navigator.maybePop(context)),
          const SizedBox(width: 6),
          Expanded(child: YummyWinTicker(clock: clock, strings: strings)),
          const SizedBox(width: 6),
          _balancePill(strings, balance),
          const SizedBox(width: 6),
          _icon(
            Icons.settings_outlined,
            'settings',
            _preferences == null ? null : _settings,
          ),
          const SizedBox(width: 6),
          _icon(Icons.menu_rounded, 'menu', _menu),
        ],
      );

  /// Everything that is not playing the game lives one tap away.
  Future<void> _menu() async {
    final strings = _strings;
    final entries = <(IconData, String, VoidCallback?)>[
      (
        Icons.help_outline,
        'help',
        () => yummySheet(
              context,
              strings.text('help'),
              yummyHelp(strings, _layout ?? {}),
              strings,
            ),
      ),
      (Icons.history, 'history', _showHistory),
      (Icons.bar_chart, 'stats', _stats),
      (Icons.emoji_events_outlined, 'leaderboard', _leaderboard),
      (Icons.task_alt, 'missions', _missions),
      (
        Icons.verified_user_outlined,
        'fairness',
        _busy ? null : () => _fairness(),
      ),
      (
        _sound ? Icons.volume_up : Icons.volume_off,
        'sound',
        () => _setting('sound', !_sound),
      ),
    ];
    final picked = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0B2F72),
      builder: (context) => Directionality(
        textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (icon, key, action) in entries)
                  SizedBox(
                    width: 100,
                    child: Tooltip(
                      message: strings.text(key),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: action == null
                            ? null
                            : () => Navigator.pop(context, action),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFF3E9BFF), yummyDeep],
                                  ),
                                  border: Border.fromBorderSide(
                                    BorderSide(color: yummyGold, width: 1.5),
                                  ),
                                ),
                                child: Icon(icon, color: Colors.white),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                strings.text(key),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
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
    );
    picked?.call();
  }

  /// Total bet · what is happening · last prize, in one glass strip.
  Widget _meter(YummyStrings strings) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEE1C7BE8), Color(0xEE0753BD), Color(0xEE053E8F)],
          ),
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Row(
          children: [
            _metric('totalBet', _totalBet),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status(strings, _last),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: _metric('prize', _shownPrize, glow: true),
            ),
          ],
        ),
      );

  /// Bet - / + · the big SPIN · lines - / +.
  Widget _dock(YummyStrings strings) => Row(
        children: [
          Expanded(
            child: _stepper(
              'bet',
              _bet,
              _locked || _steps.indexOf(_bet) <= 0
                  ? null
                  : () => _changeBet(-1),
              _locked || _steps.indexOf(_bet) >= _steps.length - 1
                  ? null
                  : () => _changeBet(1),
            ),
          ),
          const SizedBox(width: 10),
          _spinButton(strings),
          const SizedBox(width: 10),
          Expanded(
            child: _stepper(
              'lines',
              _lines,
              _locked || _lines <= 1 || !_allowed(_bet, _lines - 1)
                  ? null
                  : () => setState(() => _lines--),
              _locked || _lines >= 9 || !_allowed(_bet, _lines + 1)
                  ? null
                  : () => setState(() => _lines++),
            ),
          ),
        ],
      );

  String _status(YummyStrings strings, YummyRound? last) {
    if (_notice != null) return _notice!;
    final auto = _auto;
    if (auto != null) {
      return '${strings.text('autoplay')} · ${auto.left} ${strings.text('autoLeft')}';
    }
    if (_busy) return strings.text('pending');
    if (last == null) return strings.text('ready');
    if (last.capped) {
      return '${strings.text('capped')}: ${last.requestedPrize} → ${last.totalPrize}';
    }
    if (last.jackpotTriggered) return '👑 ${strings.text('jackpot')}';
    if (last.totalPrize > 0) {
      return '${strings.text('prize')}: ${last.totalPrize}';
    }
    return strings.text('noWin');
  }

  Widget _balancePill(YummyStrings strings, int balance) => Semantics(
        liveRegion: true,
        label: strings.text('balance'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C7BE8), yummyDeep],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: yummyGold, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55043180),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.toll, color: yummyGold),
              const SizedBox(width: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(end: (_shownBalance ?? balance).toDouble()),
                duration: _reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  '${value.round()}',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
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

/// Presses in on touch and springs back.
class _Squash extends StatefulWidget {
  final Widget child;
  const _Squash({required this.child});
  @override
  State<_Squash> createState() => _SquashState();
}

class _SquashState extends State<_Squash> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? .9 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      );
}

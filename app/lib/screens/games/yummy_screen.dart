import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/yummy_repository.dart';
import 'yummy_bonus.dart';
import 'yummy_celebration.dart';
import 'yummy_engine.dart';
import 'yummy_fairness.dart';
import 'yummy_grid.dart';
import 'yummy_help.dart';
import 'yummy_preferences.dart';
import 'yummy_sfx.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

class YummyScreen extends ConsumerStatefulWidget {
  final YummyRepository? repository;
  const YummyScreen({super.key, this.repository});
  @override
  ConsumerState<YummyScreen> createState() => _YummyScreenState();
}

class _YummyScreenState extends ConsumerState<YummyScreen>
    with TickerProviderStateMixin {
  late final YummyRepository _repository =
      widget.repository ?? YummyRepository();
  final _sfx = YummySfx();
  final _random = Random();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  // Drives the cabinet bulbs. It only runs while reels spin or a win shows,
  // so an idle screen costs nothing on low-end phones.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  int _revealed = 5, _spinId = 0;
  // While reels spin the badge shows the pre-spin balance minus the stake,
  // so the server's settled balance never spoils the result early.
  int? _shownBalance;
  YummyWinTier _tier = YummyWinTier.none;
  Completer<void>? _celebrating;
  YummyPreferences? _preferences;
  Map<String, dynamic>? _layout;
  Map<String, dynamic>? _pending;
  List<YummyRound> _history = [];
  List<String> _grid = List.generate(15, (index) => yummySymbolIds[index % 8]);
  YummyRound? _last;
  YummyReplay? _replay;
  Timer? _shuffle;
  Completer<void>? _stopSignal;
  bool _loading = true,
      _busy = false,
      _arabic = true,
      _motion = true,
      _sound = true;
  int _bet = 100, _lines = 9;
  String? _notice;
  YummyStrings get _strings => YummyStrings(_arabic);
  int get _balance => ref.read(authStateProvider).user?.coinsBalance ?? 0;
  int get _totalBet => yummyTotalBet(_bet, _lines);
  bool get _locked => _busy || _pending != null;
  List<int> get _steps => List<int>.from(
        _layout?['betSteps'] as List? ?? [10, 20, 50, 100, 200, 500, 1000],
      );
  bool get _reduced =>
      !_motion ||
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.of(context).accessibleNavigation;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _shuffle?.cancel();
    if (_stopSignal?.isCompleted == false) _stopSignal!.complete();
    if (_celebrating?.isCompleted == false) _celebrating!.complete();
    _pulse.dispose();
    _ambient.dispose();
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
        _sfx.enabled = _sound;
        _history = preferences.history;
        _pending = preferences.pending;
      });
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
        _grid = _last?.grid ?? yummyDecorativeGrid(_random);
        if (_pending != null) {
          _bet = _pending!['betPerLine'] as int;
          _lines = _pending!['activeLines'] as int;
        } else {
          _selectAllowedBet();
        }
        _notice = null;
      });
      await preferences.saveHistory(_history);
    } catch (_) {
      if (mounted) setState(() => _notice = _strings.text('error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  void _stop() {
    _replay?.stop();
    if (_stopSignal?.isCompleted == false) _stopSignal!.complete();
  }

  Future<void> _delay(int milliseconds) async {
    if (_reduced || _stopSignal?.isCompleted == true) return;
    await Future.any([
      Future<void>.delayed(Duration(milliseconds: milliseconds)),
      _stopSignal!.future,
    ]);
  }

  Future<void> _spin() async {
    if (_busy || _loading || _layout == null) return;
    if (_pending == null) {
      if (_layout!['enabled'] == false || !_allowed(_bet, _lines)) {
        setState(() => _notice = _strings.text('disabled'));
        return;
      }
      if (!yummyCanSpin(_balance, _bet, _lines)) {
        setState(() => _notice = _strings.text('lowBalance'));
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
    setState(() {
      _busy = true;
      _notice = null;
      _replay = null;
      _revealed = 0;
      _spinId++;
      _tier = YummyWinTier.none;
      _shownBalance = max(0, _balance - stake);
    });
    _pulse.stop();
    _pulse.value = 0;
    if (!_reduced) _ambient.repeat();
    _stopSignal = Completer<void>();
    _sfx.spin();
    final started = DateTime.now();
    if (!_reduced) {
      _shuffle = Timer.periodic(const Duration(milliseconds: 70), (_) {
        if (!mounted || _stopSignal?.isCompleted == true) return;
        final decoration = yummyDecorativeGrid(_random);
        setState(
          () => _grid = List.generate(
            15,
            (index) => index % 5 < (_replay?.revealedReels ?? 0)
                ? _replay!.result.grid[index]
                : decoration[index],
          ),
        );
      });
    }
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
      _replay = YummyReplay(result);
      await _delay(
        max(0, 700 - DateTime.now().difference(started).inMilliseconds),
      );
      for (var reel = 0; reel < 5; reel++) {
        if (!mounted) return;
        _replay!.revealedReels = reel + 1;
        setState(() {
          _revealed = reel + 1;
          _grid = List.generate(
            15,
            (index) => index % 5 <= reel ? result.grid[index] : _grid[index],
          );
        });
        _sfx.click();
        await _delay(140);
      }
      _shuffle?.cancel();
      if (!mounted) return;
      setState(() {
        _last = result;
        _grid = result.grid;
        _revealed = 5;
        _shownBalance = null;
        _history = [result, ..._history.where((round) => round.id != result.id)]
            .take(50)
            .toList();
      });
      await _preferences!.saveHistory(_history);
      if (!mounted) return;
      if (result.jackpotTriggered) {
        _sfx.jackpot();
      } else if (result.totalPrize > 0) {
        _sfx.win();
      }
      if (result.totalPrize > 0 && !_reduced) {
        _pulse.repeat(reverse: true);
      } else {
        _ambient.stop();
      }
      final tier = yummyWinTier(
        result.totalPrize - result.bonusPrize,
        result.totalBet,
        result.jackpotTriggered,
      );
      if (tier != YummyWinTier.none) {
        _celebrating = Completer<void>();
        setState(() => _tier = tier);
        await _celebrating!.future;
        if (!mounted) return;
      }
      if (result.bonusTriggered) {
        await yummySheet(
          context,
          _strings.text('bonus'),
          YummyBonus(round: result, strings: _strings),
          _strings,
        );
      }
    } catch (error) {
      if (!mounted) return;
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
      _shuffle?.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _revealed = 5;
          _shownBalance = null;
        });
        if (!_pulse.isAnimating) _ambient.stop();
      }
    }
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

  Future<void> _setting(String key, bool value) async {
    setState(() {
      if (key == 'arabic') _arabic = value;
      if (key == 'sound') {
        _sound = value;
        _sfx.enabled = value;
      }
      if (key == 'motion') {
        _motion = value;
        if (!value) {
          _stop();
          _pulse.stop();
          _pulse.value = 0;
          _ambient.stop();
        }
      }
    });
    await _preferences?.setSetting(key, value);
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
                  '${_strings.text('totalBet')}: ${round.totalBet}   ${_strings.text('prize')}: ${round.totalPrize}\n${_strings.text('balance')}: ${round.balance}',
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

  Widget _icon(IconData icon, String label, VoidCallback? action) => IconButton(
        tooltip: _strings.text(label),
        onPressed: action,
        icon: Icon(icon),
        color: Colors.white,
        style: IconButton.styleFrom(
          backgroundColor: yummyDeep.withValues(alpha: .9),
          minimumSize: const Size(44, 44),
        ),
      );
  Widget _metric(String label, int value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _strings.text(label),
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: yummyGold,
            ),
          ),
        ],
      );
  Widget _stepper(
    String label,
    int value,
    VoidCallback? minus,
    VoidCallback? plus,
  ) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              _strings.text(label),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: yummyInk,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip:
                      '${_strings.text('decrease')} ${_strings.text(label)}',
                  onPressed: minus,
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: yummyDeep,
                  ),
                ),
                Flexible(
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: yummyInk,
                    ),
                  ),
                ),
                IconButton(
                  tooltip:
                      '${_strings.text('increase')} ${_strings.text(label)}',
                  onPressed: plus,
                  icon: const Icon(Icons.add_circle_outline, color: yummyDeep),
                ),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(authStateProvider).user?.coinsBalance ?? 0;
    final strings = _strings;
    final last = _last;
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
          body: Shortcuts(
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
                    Image.asset(
                      '${yummyArt}background.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              yummySky,
                              yummyDeep,
                            ],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 560,
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              14,
                              8,
                              14,
                              24,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    _icon(
                                      Icons.arrow_back,
                                      'back',
                                      () => Navigator.maybePop(
                                        context,
                                      ),
                                    ),
                                    const Spacer(),
                                    Semantics(
                                      liveRegion: true,
                                      label: strings.text('balance'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 9,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0xFF1C7BE8),
                                              yummyDeep,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          border: Border.all(
                                            color: yummyGold,
                                            width: 1.5,
                                          ),
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
                                            const Icon(
                                              Icons.toll,
                                              color: yummyGold,
                                            ),
                                            const SizedBox(
                                              width: 8,
                                            ),
                                            TweenAnimationBuilder<double>(
                                              tween: Tween(
                                                end: (_shownBalance ?? balance)
                                                    .toDouble(),
                                              ),
                                              duration: _reduced
                                                  ? Duration.zero
                                                  : const Duration(
                                                      milliseconds: 900,
                                                    ),
                                              curve: Curves.easeOutCubic,
                                              builder: (context, value, _) =>
                                                  Text(
                                                '${value.round()}',
                                                style: const TextStyle(
                                                  fontSize: 21,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  fontFeatures: [
                                                    FontFeature
                                                        .tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _arabic ? 'AR' : 'EN',
                                      style: const TextStyle(
                                        color: yummyInk,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _icon(
                                      Icons.settings_outlined,
                                      'settings',
                                      _preferences == null ? null : _settings,
                                    ),
                                    _icon(
                                      Icons.help_outline,
                                      'help',
                                      () => yummySheet(
                                        context,
                                        strings.text('help'),
                                        yummyHelp(
                                          strings,
                                          _layout ?? {},
                                        ),
                                        strings,
                                      ),
                                    ),
                                    _icon(
                                      Icons.history,
                                      'history',
                                      _showHistory,
                                    ),
                                    _icon(
                                      _sound
                                          ? Icons.volume_up
                                          : Icons.volume_off,
                                      'sound',
                                      () => _setting(
                                        'sound',
                                        !_sound,
                                      ),
                                    ),
                                    _icon(
                                      Icons.bar_chart,
                                      'stats',
                                      _stats,
                                    ),
                                    _icon(
                                      Icons.verified_user_outlined,
                                      'fairness',
                                      _busy ? null : () => _fairness(),
                                    ),
                                  ],
                                ),
                                Image.asset(
                                  '${yummyArt}logo.png',
                                  height: 112,
                                  width: 280,
                                  fit: BoxFit.contain,
                                  errorBuilder: (
                                    _,
                                    __,
                                    ___,
                                  ) =>
                                      const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    child: Text(
                                      'YUMMY',
                                      style: TextStyle(
                                        fontSize: 54,
                                        fontWeight: FontWeight.w900,
                                        color: yummyGold,
                                        shadows: [
                                          Shadow(
                                            color: yummyDeep,
                                            offset: Offset(
                                              3,
                                              4,
                                            ),
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF6A2FB3),
                                        Color(0xFF44227A),
                                        Color(0xFF241047),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: yummyGold,
                                      width: 2.5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x66FFD529),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            '${yummyArt}jackpot.png',
                                            width: 40,
                                            height: 40,
                                            excludeFromSemantics: true,
                                            errorBuilder: (_, __, ___) =>
                                                const Text(
                                              '👑',
                                              style: TextStyle(fontSize: 26),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: ShaderMask(
                                                shaderCallback: (bounds) =>
                                                    const LinearGradient(
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
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                    shadows: [
                                                      Shadow(
                                                        color:
                                                            Color(0x88000000),
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
                                      Text(
                                        strings.text(
                                          'jackpotRule',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _pulse,
                                    _ambient,
                                  ]),
                                  builder: (context, child) =>
                                      Transform.translate(
                                    offset: Offset(
                                      _pulse.isAnimating
                                          ? sin(
                                                _pulse.value * pi * 4,
                                              ) *
                                              1.5
                                          : 0,
                                      0,
                                    ),
                                    child: YummyGrid(
                                      grid: _grid,
                                      wins: _busy
                                          ? const []
                                          : last?.wins ?? const [],
                                      strings: strings,
                                      pulse: _pulse.value,
                                      ambient: _ambient.value,
                                      spinning: _busy,
                                      revealedReels: _revealed,
                                      spinId: _spinId,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(
                                    12,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF1C7BE8),
                                        yummyDeep,
                                        Color(0xFF053E8F),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0x66FFFFFF),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x55043180),
                                        blurRadius: 10,
                                        offset: Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _metric(
                                        'totalBet',
                                        _totalBet,
                                      ),
                                      Semantics(
                                        liveRegion: true,
                                        child: _metric(
                                          'prize',
                                          _busy ? 0 : last?.totalPrize ?? 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _stepper(
                                        'bet',
                                        _bet,
                                        _locked ||
                                                _steps.indexOf(
                                                      _bet,
                                                    ) <=
                                                    0
                                            ? null
                                            : () => _changeBet(
                                                  -1,
                                                ),
                                        _locked ||
                                                _steps.indexOf(
                                                      _bet,
                                                    ) >=
                                                    _steps.length - 1
                                            ? null
                                            : () => _changeBet(
                                                  1,
                                                ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _stepper(
                                        'lines',
                                        _lines,
                                        _locked ||
                                                _lines <= 1 ||
                                                !_allowed(
                                                  _bet,
                                                  _lines - 1,
                                                )
                                            ? null
                                            : () => setState(
                                                  () => _lines--,
                                                ),
                                        _locked ||
                                                _lines >= 9 ||
                                                !_allowed(
                                                  _bet,
                                                  _lines + 1,
                                                )
                                            ? null
                                            : () => setState(
                                                  () => _lines++,
                                                ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _locked || _layout == null
                                            ? null
                                            : _maximum,
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          minimumSize: const Size(
                                            0,
                                            54,
                                          ),
                                          foregroundColor: yummyDeep,
                                        ),
                                        child: Text(
                                          strings.text('maximum'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(30),
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: _busy
                                                ? const [
                                                    Color(0xFFFF7A9E),
                                                    Color(0xFFE72965),
                                                  ]
                                                : const [
                                                    Color(0xFFFFF3A0),
                                                    yummyGold,
                                                    Color(0xFFFF9A25),
                                                  ],
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_busy
                                                      ? const Color(0xFFE72965)
                                                      : const Color(0xFFFF9A25))
                                                  .withValues(alpha: .6),
                                              blurRadius: 14,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: FilledButton(
                                          onPressed: _loading
                                              ? null
                                              : _busy
                                                  ? _stop
                                                  : _layout == null
                                                      ? _boot
                                                      : _spin,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor:
                                                _busy ? Colors.white : yummyInk,
                                            minimumSize: const Size(
                                              0,
                                              58,
                                            ),
                                          ),
                                          child: Text(
                                            strings.text(
                                              _busy
                                                  ? 'stop'
                                                  : _pending != null ||
                                                          _layout == null
                                                      ? 'retry'
                                                      : 'spin',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (_loading) const LinearProgressIndicator(),
                                Semantics(
                                  liveRegion: true,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xB3082A5E),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _notice ??
                                          (_busy
                                              ? strings.text(
                                                  'pending',
                                                )
                                              : last == null
                                                  ? strings.text(
                                                      'ready',
                                                    )
                                                  : last.capped
                                                      ? '${strings.text('capped')}: ${last.requestedPrize} → ${last.totalPrize}'
                                                      : last.jackpotTriggered
                                                          ? '👑 ${strings.text('jackpot')}'
                                                          : last.totalPrize > 0
                                                              ? '${strings.text('prize')}: ${last.totalPrize}'
                                                              : strings.text(
                                                                  'noWin',
                                                                )),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!_busy && last != null)
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    children: [
                                      for (final win in last.wins)
                                        Chip(
                                          label: Text(
                                            '${strings.text('line')} ${win.line + 1} · ${win.count} ${strings.text(win.symbol)} · ${win.amount}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x99082A5E),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    strings.footer,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_tier != YummyWinTier.none && last != null)
                      Positioned.fill(
                        child: YummyCelebration(
                          key: ValueKey('celebrate-$_spinId'),
                          tier: _tier,
                          prize: last.totalPrize - last.bonusPrize,
                          strings: strings,
                          reduced: _reduced,
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
    );
  }
}

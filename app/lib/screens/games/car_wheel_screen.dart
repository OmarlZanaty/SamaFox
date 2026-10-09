import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/car_wheel_repository.dart';
import '../../services/socket_service.dart';
import 'car_wheel_art.dart';
import 'car_wheel_effects.dart';
import 'car_wheel_engine.dart';
import 'car_wheel_sfx.dart';
import 'car_wheel_sheets.dart';
import 'car_wheel_strings.dart';
import 'car_wheel_wheel.dart';
import 'car_wheel_widgets.dart';

/// عجلة السيارات: one shared wheel. Chips use real platform coins; the
/// committed server result determines the disk animation and every payout.
class CarWheelScreen extends ConsumerStatefulWidget {
  final CarWheelRepository? repository;

  /// Off in tests: the shared table is then fed through [CarWheelScreenState.applyState].
  final bool live;
  const CarWheelScreen({super.key, this.repository, this.live = true});
  @override
  ConsumerState<CarWheelScreen> createState() => CarWheelScreenState();
}

class CarWheelScreenState extends ConsumerState<CarWheelScreen>
    with TickerProviderStateMixin {
  late final CarWheelRepository _repository =
      widget.repository ?? CarWheelRepository();
  final _sfx = CarWheelSfx();
  final _socket = SocketService();

  /// Drives only the spin; the angle goes to [_angle], never to setState.
  late final Ticker _ticker = createTicker(_frame);

  /// Ambient light (bulbs, countdown pulse). Painters listen to it directly.
  late final AnimationController _ambient =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));
  final _angle = ValueNotifier<double>(0);
  final _secondsLeft = ValueNotifier<double>(0);
  Timer? _clock;
  Future<void> _queue = Future.value();
  SharedPreferences? _prefs;

  bool _loading = true, _arabic = true, _sound = true, _motion = true;
  bool _urgent = false, _timeUp = false;
  String? _error, _notice;
  CarWheelState? state;
  Map<String, int> myStakes = {};
  int _pending = 0;
  int chip = 1000;
  int _round = -1;

  String? _landed;
  ({DateTime start, double from, double end, String result})? _spin;
  int _lastPocket = 0;
  int? _announced;
  int _payout = 0;
  final _stageKey = GlobalKey(), _diskKey = GlobalKey(), _barKey = GlobalKey();
  final _cardKeys = {for (final s in carWheelSegments) s.key: GlobalKey()};
  final _flights = <({Key key, Offset from, Offset to, int amount})>[];
  int _flightId = 0;
  Timer? _noticeTimer;
  final _random = Random();

  CarWheelStrings get _s => CarWheelStrings(_arabic);
  int get _balance => ref.read(authStateProvider).user?.coinsBalance ?? 0;
  bool get _reduced => !_motion || MediaQuery.disableAnimationsOf(context);
  bool get _betting =>
      (state?.betting ?? false) && (state?.left.inMilliseconds ?? 0) > 0;
  int get _myTotal => myStakes.values.fold(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _boot();
    _clock =
        Timer.periodic(const Duration(milliseconds: 250), (_) => _tickClock());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient();
    for (final name in [
      'velvet_atrium',
      'rim',
      'hub',
      'pointer',
      for (final s in carWheelSegments) 'emblem_${s.key}',
    ]) {
      precacheImage(AssetImage('$carWheelArt/$name.png'), context,
          onError: (_, __) {},);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _noticeTimer?.cancel();
    _ticker.dispose();
    _ambient.dispose();
    _angle.dispose();
    _secondsLeft.dispose();
    _sfx.dispose();
    if (widget.live) {
      _socket.off('connect', _onReconnect);
      _socket.off('carwheel_state', _onSocketState);
      _socket.off('carwheel_result', _onSocketResult);
      _socket.emit('carwheel_leave_table', {});
    }
    super.dispose();
  }

  /// The countdown moves without rebuilding the screen; only the moments that
  /// change controls (last three seconds, time up) trigger a rebuild.
  void _tickClock() {
    if (!mounted) return;
    final left = state?.betting ?? false
        ? (state!.left.inMilliseconds / 1000).toDouble()
        : 0.0;
    _secondsLeft.value = left;
    final urgent = (state?.betting ?? false) && left > 0 && left <= 3;
    final timeUp = (state?.betting ?? false) && left <= 0;
    if (urgent != _urgent || timeUp != _timeUp) {
      setState(() {
        _urgent = urgent;
        _timeUp = timeUp;
      });
    }
  }

  void _syncAmbient() {
    if (!mounted) return;
    if (_reduced) {
      _ambient.stop();
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      final id = ref.read(authStateProvider).user?.id ?? 0;
      _arabic = prefs.getBool('carwheel.$id.arabic') ?? true;
      _sound = _sfx.enabled = prefs.getBool('carwheel.$id.sound') ?? true;
      _motion = prefs.getBool('carwheel.$id.motion') ?? true;
      chip = prefs.getInt('carwheel.$id.chip') ?? 1000;
      if (!carWheelChips.contains(chip)) chip = 1000;
      final body = await _repository.fetchState();
      if (!mounted) return;
      ref
          .read(authStateProvider.notifier)
          .updateCoinsBalance((body['balance'] as num?)?.toInt() ?? _balance);
      setState(() => _loading = false);
      _syncAmbient();
      if (body['state'] is Map) {
        applyState(Map<String, dynamic>.from(body['state'] as Map), mine: true);
      }
      if (widget.live) {
        _socket.on('connect', _onReconnect);
        _socket.on('carwheel_state', _onSocketState);
        _socket.on('carwheel_result', _onSocketResult);
        _socket.emit('carwheel_join_table', {});
      }
      _syncTicker();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _s.text('error');
        });
      }
    }
  }

  void _onReconnect(dynamic _) {
    _socket.emit('carwheel_join_table', {});
    _refreshMine();
  }

  void _onSocketState(dynamic data) {
    if (mounted && data is Map) applyState(Map<String, dynamic>.from(data));
  }

  void _onSocketResult(dynamic _) => _refreshMine();

  /// The player's own stakes and payout only come over REST.
  Future<void> _refreshMine() async {
    try {
      final body = await _repository.fetchState();
      if (!mounted) return;
      ref
          .read(authStateProvider.notifier)
          .updateCoinsBalance((body['balance'] as num?)?.toInt() ?? _balance);
      if (body['state'] is Map) {
        applyState(Map<String, dynamic>.from(body['state'] as Map), mine: true);
      }
    } catch (_) {}
  }

  /// Takes a table snapshot. [mine] marks one fetched for this player, which
  /// carries their stakes and payout; broadcasts do not.
  void applyState(Map<String, dynamic> json, {bool mine = false}) {
    final next = CarWheelState.fromJson(json);
    if (state != null && next.round < _round) return;
    final previous = state;
    final changedRound = next.round != _round;
    setState(() {
      state = next;
      if (changedRound) {
        _round = next.round;
        myStakes = {};
        _payout = 0;
        _notice = null;
        _landed = null;
        _announced = null;
        _spin = null;
      }
      if (mine) {
        myStakes = Map.of(next.myStakes);
        _payout = next.myPayout;
      }
    });
    _tickClock();
    if (next.phase == 'closing' && previous?.phase == 'betting') _sfx.lock();
    if (next.result != null &&
        next.phase == 'spinning' &&
        _spin == null &&
        _landed == null) {
      final end = carWheelSpinEnd(
        _angle.value,
        next.result!,
        turns: 4,
        jitter: (_random.nextDouble() - .5) * .6,
      );
      // A subscriber joining a spin sees its destination immediately.
      if (_reduced || previous?.phase != 'closing' || next.msLeft < 6500) {
        _angle.value = end;
        _landed = next.result;
      } else {
        _spin = (
          start: DateTime.now(),
          from: _angle.value,
          end: end,
          result: next.result!
        );
        _sfx.spin();
      }
    }
    if (next.phase == 'result' && next.result != null) {
      if (_landed == null) {
        _angle.value =
            _spin?.end ?? carWheelSpinEnd(_angle.value, next.result!);
        _landed = next.result;
        _spin = null;
      }
      if (mine && _announced != next.round) {
        _announced = next.round;
        if (_payout > 0) _sfx.win(_payout >= next.myStaked * 10);
      }
      if (!mine && previous?.phase != 'result') _refreshMine();
    }
    _syncTicker();
  }

  // ── Wheel motion ──────────────────────────────────────────────────────────
  void _syncTicker() {
    final run = _spin != null;
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  /// A short wind-up against the spin, then the long ease-out to the result.
  void _frame(Duration elapsed) {
    if (!mounted) return;
    final spin = _spin;
    if (spin == null) return;
    final u = _reduced
        ? 1.0
        : DateTime.now().difference(spin.start).inMilliseconds / 6000;
    const windUp = .06;
    _angle.value = u < windUp
        ? spin.from - .12 * sin(u / windUp * pi)
        : carWheelSpinFrame((u - windUp) / (1 - windUp), spin.from, spin.end);
    final pocket =
        ((_angle.value + carWheelSegmentAngle / 2) / carWheelSegmentAngle)
            .floor();
    if (pocket != _lastPocket) {
      _lastPocket = pocket;
      _sfx.tick();
    }
    if (u >= 1) {
      _sfx.stop();
      setState(() {
        _landed = spin.result;
        _spin = null;
      });
      _syncTicker();
    }
  }

  /// Throws a chip from the dock to the card (or wedge) that took it.
  void _fly(String key, int amount, {bool fromWheel = false}) {
    if (_reduced) return;
    final stage = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    final bar = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null || bar == null) return;
    Offset? to;
    if (fromWheel) {
      final disk = _diskKey.currentContext?.findRenderObject() as RenderBox?;
      if (disk != null) {
        final a = carWheelCenter(key) + _angle.value - pi / 2;
        final local = disk.size.center(Offset.zero) +
            Offset(cos(a), sin(a)) * disk.size.width * .3;
        // The disk is rotated; place the chip in screen space instead.
        to = stage.globalToLocal(
                disk.localToGlobal(disk.size.center(Offset.zero)),) +
            (local - disk.size.center(Offset.zero));
      }
    } else {
      final card =
          _cardKeys[key]?.currentContext?.findRenderObject() as RenderBox?;
      if (card != null) {
        to = stage
            .globalToLocal(card.localToGlobal(card.size.center(Offset.zero)));
      }
    }
    if (to == null) return;
    // Thrown from the selected chip's slot in the dock.
    final slot = carWheelChips.indexOf(amount).clamp(0, 3);
    final from = stage.globalToLocal(bar.localToGlobal(
        Offset(bar.size.width * (slot + .5) / 4, bar.size.height / 2),),);
    if (_flights.length >= 6) _flights.removeAt(0);
    setState(() => _flights.add(
        (key: ValueKey(_flightId++), from: from, to: to!, amount: amount),),);
  }

  void _say(String? text) {
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    if (text != null) {
      _noticeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _notice = null);
      });
    }
  }

  // ── Betting ───────────────────────────────────────────────────────────────
  void _send(
    Future<Map<String, dynamic>> Function() call, {
    bool chipSound = true,
    String? target,
    int? amount,
    bool fromWheel = false,
  }) {
    if (!_betting) {
      _say(_s.text('closing'));
      return;
    }
    final requestRound = _round;
    setState(() => _pending++);
    // The chip leaves the hand at once; the server confirms behind it.
    if (target != null) _fly(target, amount ?? chip, fromWheel: fromWheel);
    _queue = _queue.then((_) async {
      try {
        if (!mounted || !_betting || requestRound != _round) return;
        final body = await call();
        if (!mounted) return;
        if (chipSound) _sfx.chip();
        ref
            .read(authStateProvider.notifier)
            .updateCoinsBalance((body['balance'] as num?)?.toInt() ?? _balance);
        if (requestRound != _round ||
            (body['round'] != null && body['round'] != _round)) {
          _refreshMine();
          return;
        }
        setState(() {
          myStakes = {
            for (final e
                in Map<String, dynamic>.from(body['stakes'] as Map? ?? const {})
                    .entries)
              e.key: (e.value as num).toInt(),
          };
          _notice = null;
        });
      } on CarWheelException catch (e) {
        if (mounted) _say(_s.error(e.code));
      } catch (_) {
        if (mounted) _say(_s.text('NETWORK'));
      } finally {
        if (mounted) setState(() => _pending--);
      }
    });
  }

  void placeChip(String key, {bool fromWheel = false}) {
    if (chip > _balance) {
      _say(_s.text('INSUFFICIENT_COINS'));
      return;
    }
    final amount = chip;
    _send(() => _repository.bet(key, amount),
        target: key, amount: amount, fromWheel: fromWheel,);
  }

  void _undo() => _send(_repository.undo, chipSound: false);
  void _clear() {
    _sfx.clear();
    _send(_repository.clear, chipSound: false);
  }

  void _rebet() => _send(_repository.repeat);

  void _pickChip(int value) {
    _sfx.click();
    setState(() => chip = value);
    _prefs?.setInt(
      'carwheel.${ref.read(authStateProvider).user?.id ?? 0}.chip',
      value,
    );
  }

  void _setting(String key, bool value) => _prefs?.setBool(
        'carwheel.${ref.read(authStateProvider).user?.id ?? 0}.$key',
        value,
      );

  // ── Sheets ────────────────────────────────────────────────────────────────
  void _sheet(String title, Widget body) {
    _sfx.click();
    carWheelSheet<void>(context, _s, _s.text(title), body);
  }

  void _openHelp({bool paytable = false}) => _sheet(
        paytable ? 'paytable' : 'help',
        CarWheelHelp(
          strings: _s,
          paytable: paytable,
          seedHash: state?.seedHash ?? '',
          seed: state?.seed,
          history: state?.history ?? const [],
        ),
      );

  Future<void> _openHistory() async {
    final rounds = await _repository
        .history()
        .catchError((Object _) => <Map<String, dynamic>>[]);
    if (mounted) {
      _sheet('history', CarWheelHistoryView(strings: _s, rounds: rounds));
    }
  }

  Future<void> _openRanking() async {
    Map<String, dynamic> board = const {};
    try {
      board = await _repository.ranking();
    } catch (_) {}
    if (!mounted) return;
    final me = Map<String, dynamic>.from(board['me'] as Map? ?? const {});
    _sheet(
      'ranking',
      CarWheelBoard(
        strings: _s,
        rows: (board['entries'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
        valueKey: 'net',
        empty: 'emptyRanking',
        footer: Text(
          '${_s.text('rank')}: ${me['rank'] ?? '—'} · ${_s.text('todayNet')}: ${me['net'] ?? 0} · ${_s.text('bestWin')}: ${me['best'] ?? 0}',
          style: const TextStyle(color: cwGoldLight),
        ),
      ),
    );
  }

  void _openPlayers() => _sheet(
        'players',
        CarWheelBoard(
          strings: _s,
          rows: state?.players ?? const [],
          valueKey: 'staked',
          empty: 'emptyPlayers',
        ),
      );

  void _openSettings() => _sheet(
        'settings',
        CarWheelSettings(
          strings: _s,
          sound: _sound,
          motion: _motion,
          onArabic: (v) {
            setState(() => _arabic = v);
            _setting('arabic', v);
          },
          onSound: (v) {
            setState(() => _sound = _sfx.enabled = v);
            _setting('sound', v);
          },
          onMotion: (v) {
            setState(() => _motion = v);
            _setting('motion', v);
            _syncAmbient();
            _syncTicker();
          },
        ),
      );

  // ── Layout ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(authStateProvider).user?.coinsBalance ?? 0;
    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: cwBlack,
        body: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF12030A), Color(0xFF3A0820), cwPurpleDark],
              ),
            ),
          ),
          Image.asset('$carWheelArt/velvet_atrium.png',
              fit: BoxFit.cover,
              cacheWidth: 1080,
              errorBuilder: (_, __, ___) => Image.asset(
                  '$carWheelArt/background.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),),),
          SafeArea(
            child: _loading
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(color: cwGold),
                      const SizedBox(height: 10),
                      Text(_s.text('loading'),
                          style: const TextStyle(color: Colors.white),),
                    ],),
                  )
                : _error != null
                    ? _errorView()
                    : _game(balance),
          ),
        ],),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: cwGold, foregroundColor: cwPurpleDark,),
            onPressed: _boot,
            child: Text(_s.text('retry')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.maybePop(context),
            child: Text(_s.text('back')),
          ),
        ],),
      );

  /// Fixed heights for everything but the wheel; the wheel takes what is left,
  /// so the whole game fits one screen without scrolling.
  Widget _game(int balance) => LayoutBuilder(builder: (context, box) {
        final width = min(box.maxWidth, 520.0);
        final inner = width - 20;
        final cardW = (inner - 3 * 6) / 4;
        const hud = 48.0, crowd = 46.0, totals = 44.0, dock = 70.0, gaps = 30.0;
        final room = box.maxHeight - hud - crowd - totals - dock - gaps - 6;
        final minCard = (cardW * .78).clamp(58.0, 76.0);
        final wheel = min(inner * .96, room - minCard * 2).clamp(200.0, 520.0);
        // A tall phone's spare height goes to bigger cards, not a gap.
        final cardH = ((room - wheel) / 2).clamp(minCard, 96.0);
        final fixed = hud + crowd + totals + dock + cardH * 2 + 6 + 12;
        final wheelTop = hud + crowd + (box.maxHeight - fixed - wheel) / 2;
        final phase = state?.phase ?? 'betting';
        final result = state?.result;
        return Center(
          child: SizedBox(
            width: width,
            child: Stack(key: _stageKey, clipBehavior: Clip.none, children: [
              Column(children: [
                SizedBox(height: hud, child: _hud(balance)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: CarWheelCrowdRow(
                    players: state?.players ?? const [],
                    playerCount: state?.playerCount ?? 0,
                    history: state?.history ?? const [],
                    strings: _s,
                    onPlayers: _openPlayers,
                    onHistory: _openHistory,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: CarWheelWheel(
                      size: wheel,
                      angle: _angle,
                      ambient: _ambient,
                      secondsLeft: _secondsLeft,
                      phase: _landed == null && phase == 'result'
                          ? 'spinning'
                          : phase,
                      result: _landed ?? (phase == 'result' ? result : null),
                      myStakes: myStakes,
                      reduced: _reduced,
                      diskKey: _diskKey,
                      onBet: _betting
                          ? (k) => placeChip(k, fromWheel: true)
                          : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: CarWheelTotalsRow(
                    total: state?.totalBet ?? 0,
                    mine: _myTotal,
                    phaseText: _phaseText(phase),
                    urgent: _urgent,
                    strings: _s,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    height: cardH * 2 + 6,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      crossAxisCount: 4,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: cardW / cardH,
                      children: [
                        for (final s in carWheelSegments)
                          CarWheelBetCard(
                            key: _cardKeys[s.key],
                            segment: s,
                            mine: myStakes[s.key] ?? 0,
                            all: state?.totals[s.key] ?? 0,
                            winner: phase == 'result' && result == s.key,
                            loser: phase == 'result' &&
                                result != null &&
                                result != s.key,
                            enabled: _betting && !_timeUp,
                            strings: _s,
                            onTap: () => placeChip(s.key),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                CarWheelDock(
                  selected: chip,
                  canRenew: _betting && _pending == 0,
                  strings: _s,
                  barKey: _barKey,
                  onPick: _pickChip,
                  onRenew: _renew,
                ),
              ],),
              if (phase == 'result' && result != null && _landed != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: wheelTop + wheel * .7,
                  child: _resultPlaque(result),
                ),
              if (phase == 'result' &&
                  _landed != null &&
                  _payout > 0 &&
                  !_reduced)
                Positioned.fill(
                  child: CarWheelCoinBurst(
                    key: ValueKey('burst-$_round'),
                    big: _payout >= max(1, state?.myStaked ?? 1) * 10,
                  ),
                ),
              if (_notice != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: dock + cardH * 2 + totals + 24,
                  child: _toast(_notice!),
                ),
              for (final f in _flights)
                CarWheelFlyingChip(
                  key: f.key,
                  from: f.from,
                  to: f.to,
                  amount: f.amount,
                  onDone: () {
                    if (mounted) setState(() => _flights.remove(f));
                  },
                ),
            ],),
          ),
        );
      },);

  String _phaseText(String phase) {
    if (phase == 'betting' && _timeUp) return _s.text('closing');
    return switch (phase) {
      'closing' => _s.text('closing'),
      'spinning' => _s.text('spinning'),
      'result' => _s.text('result'),
      _ => _s.text('betting'),
    };
  }

  Widget _hud(int balance) {
    final date = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          CarWheelRoundButton(
            icon: Icons.arrow_back_rounded,
            tooltip: _s.text('home'),
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_s.round(state?.round ?? 0),
                        style: const TextStyle(
                            color: cwGoldLight,
                            fontSize: 14,
                            height: 1.15,
                            fontWeight: FontWeight.w900,),),
                    Text('${date.year} / ${two(date.month)} / ${two(date.day)}',
                        style: const TextStyle(
                            color: cwMuted, fontSize: 10, height: 1.15,),),
                  ],),
            ),
          ),
          Flexible(child: FittedBox(child: CarWheelBalance(balance: balance))),
          const SizedBox(width: 6),
          CarWheelRoundButton(
            icon: Icons.emoji_events_rounded,
            tooltip: _s.text('ranking'),
            onTap: _openRanking,
            child: SizedBox.square(
              dimension: 26,
              child: carWheelImage(
                  'trophy', const Icon(Icons.emoji_events, color: cwGold),),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: _s.text('menu'),
            color: cwNavy,
            padding: EdgeInsets.zero,
            icon: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF8B54D6), Color(0xFF4A1C86)],),
                border: Border.fromBorderSide(
                    BorderSide(color: Color(0x88FFE7A2), width: 1.2),),
              ),
              child: const Icon(Icons.menu_rounded, color: Colors.white),
            ),
            itemBuilder: (_) => [
              for (final key in [
                'help',
                'paytable',
                'history',
                'players',
                'settings',
              ])
                PopupMenuItem(
                  value: key,
                  child: Text(_s.text(key),
                      style: const TextStyle(color: Colors.white),),
                ),
            ],
            onSelected: (key) {
              switch (key) {
                case 'help':
                  _openHelp();
                case 'paytable':
                  _openHelp(paytable: true);
                case 'history':
                  _openHistory();
                case 'players':
                  _openPlayers();
                case 'settings':
                  _openSettings();
              }
            },
          ),
        ],),
      ),
    );
  }

  Widget _resultPlaque(String result) {
    final won = _payout > 0;
    final big = won && _payout >= max(1, state?.myStaked ?? 1) * 10;
    return Center(
      child: CarWheelPopIn(
        key: ValueKey('plaque-$_round'),
        reduced: _reduced,
        child: Semantics(
          liveRegion: true,
          label:
              '${_s.winning(result)}. ${won ? '${_s.text('youWon')} ${cwNumber(_payout)}' : _s.text('noWin')}',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: cwPanel(radius: 18, lit: won).copyWith(boxShadow: [
                BoxShadow(
                    color: (won ? cwGold : Colors.black).withValues(alpha: .55),
                    blurRadius: 18,),
              ],),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CarWheelEmblem(segment: result, size: big ? 46 : 38),
                const SizedBox(width: 10),
                Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_s.winning(result),
                          style: const TextStyle(
                              color: cwGold,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,),),
                      if (won)
                        TweenAnimationBuilder<double>(
                          key: ValueKey('prize-$_round-$_payout'),
                          tween: Tween(begin: 0, end: _payout.toDouble()),
                          duration: Duration(
                              milliseconds: _reduced ? 0 : (big ? 1800 : 1000),),
                          builder: (_, value, __) => Text(
                            '${_s.text('youWon')} ${cwNumber(value.round())}',
                            style: TextStyle(
                                color: cwGoldLight,
                                fontSize: big ? 24 : 20,
                                fontWeight: FontWeight.w900,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],),
                          ),
                        )
                      else
                        Text(_s.text('noWin'),
                            style:
                                const TextStyle(color: cwMuted, fontSize: 13),),
                    ],),
              ],),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toast(String text) => IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xEE1A0830),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cwGold.withValues(alpha: .6)),
              ),
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: cwGoldLight, fontWeight: FontWeight.w700,),),
            ),
          ),
        ),
      );

  Future<void> _renew() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
        child: SimpleDialog(
          backgroundColor: cwNavy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: cwGold.withValues(alpha: .6)),
          ),
          title: Text(_s.text('renew'), style: const TextStyle(color: cwGold)),
          children: [
            for (final key in ['rebet', 'undo', 'clear', 'cancel'])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, key),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_s.text(key),
                      style: const TextStyle(color: Colors.white),),
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rebet':
        _rebet();
      case 'undo':
        _undo();
      case 'clear':
        _clear();
    }
  }
}

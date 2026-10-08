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
import 'car_wheel_engine.dart';
import 'car_wheel_sfx.dart';
import 'car_wheel_sheets.dart';
import 'car_wheel_strings.dart';

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
    with SingleTickerProviderStateMixin {
  late final CarWheelRepository _repository =
      widget.repository ?? CarWheelRepository();
  final _sfx = CarWheelSfx();
  final _socket = SocketService();
  late final Ticker _ticker = createTicker(_frame);
  Timer? _clock;
  Future<void> _queue = Future.value();
  SharedPreferences? _prefs;

  bool _loading = true, _arabic = true, _sound = true, _motion = true;
  String? _error, _notice;
  CarWheelState? state;
  Map<String, int> myStakes = {};
  int _pending = 0;
  int chip = 1000;
  int _round = -1;

  double _wheel = 0, _glow = 0;
  String? _landed;
  ({DateTime start, double from, double end, String result})? _spin;
  int _lastPocket = 0;
  int? _announced;
  int _payout = 0;
  List<Map<String, dynamic>> _chips = [];
  final _stageKey = GlobalKey(), _diskKey = GlobalKey(), _barKey = GlobalKey();
  ({DateTime start, Offset from, Offset to, int amount})? _flight;
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
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _ticker.dispose();
    _sfx.dispose();
    if (widget.live) {
      _socket.off('connect', _onReconnect);
      _socket.off('carwheel_state', _onSocketState);
      _socket.off('carwheel_result', _onSocketResult);
      _socket.emit('carwheel_leave_table', {});
    }
    super.dispose();
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
        _chips = [];
        _payout = 0;
        _notice = null;
        _landed = null;
        _announced = null;
        _spin = null;
      }
      if (mine) {
        myStakes = Map.of(next.myStakes);
        _chips = next.myChips;
        _payout = next.myPayout;
      }
    });
    if (next.phase == 'closing' && previous?.phase == 'betting') _sfx.lock();
    if (next.result != null &&
        next.phase == 'spinning' &&
        _spin == null &&
        _landed == null) {
      final end = carWheelSpinEnd(_wheel, next.result!,
          turns: 4, jitter: (_random.nextDouble() - .5) * .6,);
      // A subscriber joining a spin sees its destination immediately.
      if (_reduced || previous?.phase != 'closing' || next.msLeft < 6500) {
        _wheel = end;
        _landed = next.result;
      } else {
        _spin = (
          start: DateTime.now(),
          from: _wheel,
          end: end,
          result: next.result!
        );
        _sfx.spin();
      }
    }
    if (next.phase == 'result' && next.result != null) {
      if (_landed == null) {
        _wheel = _spin?.end ?? carWheelSpinEnd(_wheel, next.result!);
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
    final run = _spin != null ||
        _flight != null ||
        (state?.phase == 'result' && !_reduced);
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  void _frame(Duration elapsed) {
    if (!mounted) return;
    final spin = _spin;
    setState(() {
      if (spin != null) {
        final u = _reduced
            ? 1.0
            : DateTime.now().difference(spin.start).inMilliseconds / 6000;
        _wheel = carWheelSpinFrame(u, spin.from, spin.end);
        final pocket =
            ((_wheel + carWheelSegmentAngle / 2) / carWheelSegmentAngle)
                .floor();
        if (pocket != _lastPocket) {
          _lastPocket = pocket;
          _sfx.tick();
        }
        if (u >= 1) {
          _landed = spin.result;
          _spin = null;
          _sfx.stop();
        }
      }
      _glow = .5 + .5 * sin(elapsed.inMilliseconds / 220);
      if (_flight != null &&
          DateTime.now().difference(_flight!.start).inMilliseconds >= 380) {
        _flight = null;
      }
    });
    _syncTicker();
  }

  void _fly(String key, int amount) {
    if (_reduced) return;
    final stage = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    final disk = _diskKey.currentContext?.findRenderObject() as RenderBox?;
    final bar = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null || disk == null || bar == null) return;
    final a = carWheelCenter(key) - pi / 2;
    final local = disk.size.center(Offset.zero) +
        Offset(cos(a), sin(a)) * disk.size.width * .30;
    _flight = (
      start: DateTime.now(),
      from:
          stage.globalToLocal(bar.localToGlobal(bar.size.center(Offset.zero))),
      to: stage.globalToLocal(disk.localToGlobal(local)),
      amount: amount
    );
    _syncTicker();
  }

  // ── Betting ───────────────────────────────────────────────────────────────
  void _send(
    Future<Map<String, dynamic>> Function() call, {
    bool chipSound = true,
    String? target,
    int? amount,
  }) {
    if (!_betting) {
      setState(() => _notice = _s.text('closing'));
      return;
    }
    final requestRound = _round;
    setState(() => _pending++);
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
          _chips = (body['chipList'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _notice = null;
        });
        if (target != null) _fly(target, amount ?? chip);
      } on CarWheelException catch (e) {
        if (mounted) setState(() => _notice = _s.error(e.code));
      } catch (_) {
        if (mounted) setState(() => _notice = _s.text('NETWORK'));
      } finally {
        if (mounted) setState(() => _pending--);
      }
    });
  }

  void placeChip(String key) {
    if (chip > _balance) {
      setState(() => _notice = _s.text('INSUFFICIENT_COINS'));
      return;
    }
    final amount = chip;
    _send(() => _repository.bet(key, amount), target: key, amount: amount);
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
                          colors: [cwBlack, cwNavy, cwPurpleDark],),),),
              Image.asset('$carWheelArt/background.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),),
              SafeArea(
                  child: _loading
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          const CircularProgressIndicator(color: cwGold),
                          Text(_s.text('loading'),
                              style: const TextStyle(color: Colors.white),),
                        ],),)
                      : _error != null
                          ? Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  Text(_error!,
                                      style:
                                          const TextStyle(color: Colors.white),),
                                  TextButton(
                                      onPressed: _boot,
                                      child: Text(_s.text('retry')),),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.maybePop(context),
                                      child: Text(_s.text('back')),),
                                ],),)
                          : _game(balance),),
            ],),),);
  }

  Widget _game(int balance) => LayoutBuilder(builder: (context, box) {
        final width = min(box.maxWidth, 560.0);
        final wheelSize = min(box.maxWidth * .92, 460.0);
        return Stack(key: _stageKey, children: [
          Column(children: [
            Expanded(
                child: SingleChildScrollView(
                    child: Center(
                        child: SizedBox(
                            width: width,
                            child: Column(children: [
                              _topBar(),
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 8,),
                                  child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 18,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                            '${_s.text('balance')}: ${_number(balance)}',
                                            style: const TextStyle(
                                                color: cwGold,
                                                fontWeight: FontWeight.w800,),),
                                        Text(
                                            '${_s.text(state?.phase ?? 'betting')} · ${_s.seconds(((state?.left.inMilliseconds ?? 0) / 1000).ceil())}',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,),),
                                      ],),),
                              _wheelView(wheelSize),
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10,),
                                  child: Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Row(children: [
                                        Expanded(
                                            child: _total(_s.text('totalBet'),
                                                state?.totalBet ?? 0,),),
                                        Expanded(
                                            child: _total(_s.text('myTotalBet'),
                                                _myTotal,),),
                                      ],),),),
                              if (state?.phase == 'result' &&
                                  state?.result != null)
                                Semantics(
                                    liveRegion: true,
                                    label:
                                        '${_s.winning(state!.result!)}. ${_payout > 0 ? '${_s.text('youWon')} ${_number(_payout)}' : _s.text('noWin')}',
                                    child: ExcludeSemantics(
                                        child: Column(children: [
                                      Text(_s.winning(state!.result!),
                                          style: const TextStyle(
                                              color: cwGold,
                                              fontSize: 19,
                                              fontWeight: FontWeight.w900,),),
                                      if (_payout > 0)
                                        TweenAnimationBuilder<double>(
                                            key: ValueKey(
                                                'prize-$_round-$_payout',),
                                            tween: Tween(
                                                begin: 0,
                                                end: _payout.toDouble(),),
                                            duration: Duration(
                                                milliseconds:
                                                    _reduced ? 0 : 1000,),
                                            builder: (_, value, __) => Text(
                                                '${_s.text('youWon')} ${_number(value.round())}',
                                                style: const TextStyle(
                                                    color: cwGoldLight,
                                                    fontSize: 22,
                                                    fontWeight:
                                                        FontWeight.w900,),),)
                                      else
                                        Text(_s.text('noWin'),
                                            style: const TextStyle(
                                                color: cwMuted,),),
                                    ],),),),
                              if (_notice != null)
                                Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Semantics(
                                        liveRegion: true,
                                        child: Text(_notice!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: cwGoldLight,),),),),
                              if (state?.history.isNotEmpty ?? false)
                                Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Semantics(
                                        label: _s.text('lastResults'),
                                        child: Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 5,
                                            runSpacing: 5,
                                            children: [
                                              for (final key
                                                  in state!.history.reversed)
                                                carWheelBadge(key, size: 25),
                                            ],),),),
                              const SizedBox(height: 8),
                            ],),),),),),
            _chipBar(width),
          ],),
          if (_flight != null) _flyingChip(),
        ],);
      },);

  Widget _total(String title, int value) => Column(children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text(carWheelCompact(value),
            style: const TextStyle(
                color: cwGold,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],),),
      ],);

  Widget _topBar() {
    final date = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              DecoratedBox(
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Color(0xFF3677DE), cwPurple],),),
                  child: IconButton(
                      tooltip: _s.text('home'),
                      onPressed: () => Navigator.maybePop(context),
                      icon:
                          const Icon(Icons.home_rounded, color: Colors.white),),),
              const SizedBox(width: 6),
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 9,),
                      decoration: BoxDecoration(
                          color: const Color(0xFFAD83D3).withValues(alpha: .4),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white38),),
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                              '${date.year} / ${two(date.month)} / ${two(date.day)}   ${_s.round(state?.round ?? 0)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,),),),),),
              IconButton(
                  tooltip: _s.text('ranking'),
                  onPressed: _openRanking,
                  icon: SizedBox.square(
                      dimension: 28,
                      child: carWheelImage('trophy',
                          const Icon(Icons.emoji_events, color: cwGold),),),),
              PopupMenuButton<String>(
                  tooltip: _s.text('menu'),
                  color: cwNavy,
                  icon: const Icon(Icons.menu_rounded, color: Colors.white),
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
                                  style: const TextStyle(color: Colors.white),),),
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
                  },),
            ],),),);
  }

  Widget _wheelView(double size) {
    final phase = state?.phase ?? 'betting';
    final hubText = switch (phase) {
      'betting' => '${((state?.left.inMilliseconds ?? 0) / 1000).ceil()}',
      'closing' => '?',
      'spinning' => '...',
      _ => 'x${carWheelBet(state?.result ?? '')?.multiplier ?? 0}',
    };
    return SizedBox.square(
        dimension: size,
        child: Stack(alignment: Alignment.center, children: [
          Transform.rotate(
              angle: _wheel,
              child: GestureDetector(
                  key: _diskKey,
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _betting
                      ? (d) {
                          // Transform already un-rotates this local position.
                          final key = carWheelKeyAt(d.localPosition, size);
                          if (key != null) placeChip(key);
                        }
                      : null,
                  child: SizedBox.square(
                      dimension: size,
                      child: Stack(children: [
                        Positioned.fill(
                            child: CustomPaint(
                                painter: CarWheelDiskPainter(
                                    winner: phase == 'result'
                                        ? state?.result
                                        : null,
                                    glow: _glow,),),),
                        for (final (i, b) in carWheelSegments.indexed)
                          _wedge(b, i, size),
                      ],),),),),
          Positioned.fill(
              child: IgnorePointer(
                  child: carWheelImage('rim',
                      const CustomPaint(painter: CarWheelRimPainter()),),),),
          SizedBox.square(
              dimension: size * .23,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                    child: carWheelImage(
                        'hub',
                        Container(
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const RadialGradient(
                                    colors: [cwPurple, cwPurpleDark],),
                                border: Border.all(color: cwGold, width: 3),
                                boxShadow: const [
                              BoxShadow(color: cwPink, blurRadius: 12),
                            ],),),),),
                Transform.scale(
                    scale: phase == 'result' && !_reduced ? 1 + .08 * _glow : 1,
                    child: Text(hubText,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            color: cwGoldLight,
                            fontSize: size * .075,
                            fontWeight: FontWeight.w900,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],),),),
              ],),),
          Positioned(
              top: 0,
              child: IgnorePointer(
                  child: SizedBox(
                      width: size * .10,
                      height: size * .14,
                      child: carWheelImage(
                          'pointer',
                          const CustomPaint(
                              painter: CarWheelPointerPainter(),),),),),),
        ],),);
  }

  Widget _wedge(CarWheelSegment b, int index, double size) {
    final angle = index * carWheelSegmentAngle;
    final at = Offset(
        size / 2 + sin(angle) * size * .265, size / 2 - cos(angle) * size * .265,);
    final chips = _chips.where((c) => c['key'] == b.key).toList();
    final winner = state?.phase == 'result' && state?.result == b.key;
    return Positioned(
        // Kept inside the red disk: the rim art covers everything past ~40%.
        left: at.dx - size * .12,
        top: at.dy - size * .125,
        width: size * .24,
        height: size * .25,
        child: Transform.rotate(
            angle: angle,
            child: Semantics(
                button: true,
                enabled: _betting,
                label: _s.betLabel(b),
                onTap: _betting ? () => placeChip(b.key) : null,
                child: ExcludeSemantics(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          CarWheelEmblem(segment: b.key, size: size * .085),
                          Text(b.name,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: size * .026,
                                  fontWeight: FontWeight.w800,),),
                          Text('x${b.multiplier}',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                  color: winner ? cwGoldLight : Colors.white,
                                  fontSize: size * .048,
                                  fontWeight: FontWeight.w900,),),
                          Text(
                              '${carWheelCompact(myStakes[b.key] ?? 0)} / ${carWheelCompact(state?.totals[b.key] ?? 0)}',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                  color: cwGoldLight,
                                  fontSize: size * .023,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],),),
                          if (winner)
                            Text(_s.text('win'),
                                style: const TextStyle(
                                    color: cwGold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,),)
                          else
                            SizedBox(
                                width: size * .20,
                                height: size * .065,
                                child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      for (final (j, c) in chips
                                          .take(5)
                                          .indexed)
                                        Positioned(
                                            left: j * size * .027,
                                            top: j.isEven ? 0 : 2,
                                            child: Transform.rotate(
                                                angle: (((c['id'] as num?)
                                                                    ?.toInt() ??
                                                                j) *
                                                            17 %
                                                            25 -
                                                        12) *
                                                    pi /
                                                    180,
                                                child: CarWheelChip(
                                                    amount:
                                                        (c['amount'] as num?)
                                                                ?.toInt() ??
                                                            100,
                                                    size: size * .058,
                                                    glow: c ==
                                                        _chips.lastOrNull,),),),
                                      if (chips.length > 5)
                                        Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                                color: cwPurpleDark,
                                                child: Text(
                                                    '+${chips.length - 5}',
                                                    style: const TextStyle(
                                                        color: cwGold,
                                                        fontSize: 10,),),),),
                                    ],),),
                        ],),),),),),);
  }

  Widget _chipBar(double width) => Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
          color: cwPurple.withValues(alpha: .35),
          border: const Border(top: BorderSide(color: Colors.white24)),),
      child: Row(children: [
        Expanded(
            child: Row(
                key: _barKey,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
              for (final amount in carWheelChips)
                Semantics(
                    button: true,
                    selected: chip == amount,
                    label: _number(amount),
                    child: GestureDetector(
                        onTap: () => _pickChip(amount),
                        child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: CarWheelChip(
                                amount: amount,
                                size: min(48, (width - 112) / 5),
                                selected: chip == amount,),),),),
            ],),),
        const SizedBox(width: 8),
        DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                    colors: [Color(0xFFF39430), Color(0xFFD83944)],),),
            child: TextButton(
                onPressed: _betting && _pending == 0 ? _renew : null,
                child: Text(_s.text('renew'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900,),),),),
      ],),);

  Future<void> _renew() async {
    final action = await showDialog<String>(
        context: context,
        builder: (context) => Directionality(
            textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
            child: SimpleDialog(
                backgroundColor: cwNavy,
                title: Text(_s.text('renew'),
                    style: const TextStyle(color: cwGold),),
                children: [
                  for (final key in ['rebet', 'undo', 'clear', 'cancel'])
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, key),
                        child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(_s.text(key),
                                style: const TextStyle(color: Colors.white),),),),
                ],),),);
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

  Widget _flyingChip() {
    final f = _flight!;
    final t = (DateTime.now().difference(f.start).inMilliseconds / 380)
        .clamp(0.0, 1.0);
    final at = Offset.lerp(f.from, f.to, Curves.easeOut.transform(t))!;
    return Positioned(
        left: at.dx - 17,
        top: at.dy - 17,
        child: IgnorePointer(
            child: Transform.scale(
                scale: .7 + .3 * t,
                child: CarWheelChip(amount: f.amount, size: 34, glow: true),),),);
  }

  String _number(int value) => value
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

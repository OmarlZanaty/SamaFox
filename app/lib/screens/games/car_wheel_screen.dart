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

part 'car_wheel_layout.dart';

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
  bool _urgent = false, _timeUp = false, _artCached = false;
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
  List<Map<String, dynamic>> _chips = [];
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
    if (_artCached) return;
    _artCached = true;
    for (final name in [
      'velvet_atrium_v2',
      'background',
      'trophy',
      'chip_100',
      'chip_1k',
      'chip_10k',
      'chip_100k',
      'rim',
      'hub',
      'pointer',
      for (final s in carWheelSegments) 'emblem_${s.key}',
    ]) {
      precacheImage(
        carWheelProvider(name),
        context,
        onError: (_, __) {},
      );
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
      if (_spin != null) {
        _angle.value = _spin!.end;
        _landed = _spin!.result;
        _spin = null;
        _ticker.stop();
      }
      _flights.clear();
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
        : DateTime.now().difference(spin.start).inMilliseconds / 6800;
    const windUp = .06;
    if (u < windUp) {
      _angle.value = spin.from - .12 * sin(u / windUp * pi / 2);
    } else if (u < .94) {
      _angle.value = carWheelSpinFrame(
        (u - windUp) / (.94 - windUp),
        spin.from - .12,
        spin.end + .035,
      );
    } else {
      _angle.value = spin.end + .035 * (1 - ((u - .94) / .06).clamp(0, 1));
    }
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
              disk.localToGlobal(disk.size.center(Offset.zero)),
            ) +
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
    final from = stage.globalToLocal(
      bar.localToGlobal(
        Offset(bar.size.width * (slot + .5) / 4, bar.size.height / 2),
      ),
    );
    if (_flights.length >= 6) _flights.removeAt(0);
    setState(
      () => _flights.add(
        (key: ValueKey(_flightId++), from: from, to: to!, amount: amount),
      ),
    );
  }

  void _finishFlight(Key key) {
    if (mounted) setState(() => _flights.removeWhere((f) => f.key == key));
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
          _chips = (body['chipList'] as List? ?? const [])
              .whereType<Map>()
              .map((c) => Map<String, dynamic>.from(c))
              .toList();
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
    _send(
      () => _repository.bet(key, amount),
      target: key,
      amount: amount,
      fromWheel: fromWheel,
    );
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF12030A), Color(0xFF3A0820), cwPurpleDark],
                ),
              ),
            ),
            Image.asset(
              '$carWheelArt/velvet_atrium_v2.png',
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (_, __, ___) => Image.asset(
                '$carWheelArt/background.png',
                cacheWidth: 900,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x18120316),
                    Color(0x38120316),
                    Color(0x70120316),
                  ],),
            ),),),
            SafeArea(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: cwGold),
                          const SizedBox(height: 10),
                          Text(
                            _s.text('loading'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? _errorView()
                      : _game(balance),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cwGold,
                foregroundColor: cwPurpleDark,
              ),
              onPressed: _boot,
              child: Text(_s.text('retry')),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => Navigator.maybePop(context),
              child: Text(_s.text('back')),
            ),
          ],
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
                  child: Text(
                    _s.text(key),
                    style: const TextStyle(color: Colors.white),
                  ),
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

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/roulette_repository.dart';
import '../../services/socket_service.dart';
import '../wallet_screen.dart';
import 'roulette_art.dart';
import 'roulette_engine.dart';
import 'roulette_sfx.dart';
import 'roulette_sheets.dart';
import 'roulette_strings.dart';

/// الروليت: one European single-zero table shared by everyone. Bets go in
/// while the timer runs; the server rolls the committed seed, the wheel and
/// ball replay it, and winners are paid from the game's prize pool.
class RouletteScreen extends ConsumerStatefulWidget {
  final RouletteRepository? repository;

  /// Off in tests: the shared table is then fed through [RouletteScreenState.applyState].
  final bool live;
  const RouletteScreen({super.key, this.repository, this.live = true});
  @override
  ConsumerState<RouletteScreen> createState() => RouletteScreenState();
}

class RouletteScreenState extends ConsumerState<RouletteScreen>
    with SingleTickerProviderStateMixin {
  late final RouletteRepository _repository =
      widget.repository ?? RouletteRepository();
  final _sfx = RouletteSfx();
  final _socket = SocketService();
  late final Ticker _ticker = createTicker(_frame);
  Timer? _clock;
  Future<void> _queue = Future.value();
  SharedPreferences? _prefs;

  bool _loading = true, _arabic = true, _sound = true, _motion = true;
  String? _error, _notice;
  RouletteState? state;
  Map<String, int> myStakes = {};
  int _pending = 0;
  int chip = 1000;
  int _round = -1;

  // Wheel and ball.
  double _wheel = 0, _ball = 0, _lift = 0;
  int? _landed;

  /// Last round's pocket: the ball rests there while the next round takes bets.
  int? _rest;
  double _glow = 0;
  ({DateTime start, Duration length, double wheelStart, int result})? _spin;
  Duration _lastFrame = Duration.zero;
  int _lastPocket = 0;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  int? _announced;

  /// Bumped every animation frame; only the wheel listens to it.
  final _pose = ValueNotifier<int>(0);

  /// Betting countdown in whole seconds; only the phase label listens.
  final _seconds = ValueNotifier<int>(0);

  RouletteStrings get _s => RouletteStrings(_arabic);
  int get _balance => ref.read(authStateProvider).user?.coinsBalance ?? 0;
  bool get _reduced => !_motion || MediaQuery.disableAnimationsOf(context);
  bool get _betting => state?.betting ?? false;
  int get _myTotal => myStakes.values.fold(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _boot();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) _seconds.value = state?.left.inSeconds ?? 0;
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _ticker.dispose();
    _pose.dispose();
    _seconds.dispose();
    _sfx.dispose();
    if (widget.live) {
      _socket.off('roulette_state', _onSocketState);
      _socket.off('roulette_result', _onSocketResult);
      _socket.emit('roulette_leave_table', {});
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
      _arabic = prefs.getBool('roulette.$id.arabic') ?? true;
      _sound = _sfx.enabled = prefs.getBool('roulette.$id.sound') ?? true;
      _motion = prefs.getBool('roulette.$id.motion') ?? true;
      chip = prefs.getInt('roulette.$id.chip') ?? 1000;
      if (!rouletteChips.contains(chip)) chip = 1000;
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
        _socket.on('roulette_state', _onSocketState);
        _socket.on('roulette_result', _onSocketResult);
        _socket.emit('roulette_join_table', {});
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
    final next = RouletteState.fromJson(json);
    final previous = state;
    setState(() {
      state = next;
      if (next.round != _round) {
        _round = next.round;
        if (next.betting) {
          myStakes = {};
          _notice = null;
          _rest = _landed ?? _rest;
          _landed = null;
          _glow = 0;
          _announced = null;
        }
      }
      if (mine && json['me'] is Map) myStakes = Map.of(next.myStakes);
    });
    if (next.phase == 'closing' && previous?.phase == 'betting') _sfx.lock();
    if (next.result != null &&
        (next.phase == 'spinning') &&
        _spin?.result != next.result &&
        _landed == null) {
      _startSpin(next);
    } else if (next.result != null &&
        next.phase == 'result' &&
        _landed == null &&
        _spin == null) {
      _land(next.result!, sound: false);
    }
    if (next.phase == 'result' &&
        mine &&
        next.result != null &&
        _announced != next.round) {
      _announce(next);
    }
  }

  void _announce(RouletteState s) {
    if (_landed == null && _spin != null) return; // wait for the ball
    _announced = s.round;
    final won = s.myPayout;
    if (won > 0) _sfx.win(won >= s.myStaked * 5);
    setState(() {
      _notice = s.myStaked == 0
          ? _s.winning(s.result!)
          : won > 0
              ? '${_s.winning(s.result!)} — ${_s.text('youWon')} $won'
              : '${_s.winning(s.result!)} — ${_s.text('noWin')}';
    });
  }

  // ── Wheel motion ──────────────────────────────────────────────────────────
  void _syncTicker() {
    final run = _spin != null || !_reduced;
    if (run && !_ticker.isActive) {
      _lastFrame = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _startSpin(RouletteState s) {
    if (_reduced) {
      _land(s.result!);
      return;
    }
    _sfx.spin();
    _spin = (
      start: DateTime.now(),
      length: s.left < const Duration(milliseconds: 1500)
          ? const Duration(milliseconds: 1500)
          : s.left - const Duration(milliseconds: 300),
      wheelStart: _wheel,
      result: s.result!
    );
    _lastPocket = _pocketUnderBall();
    _syncTicker();
  }

  int _pocketUnderBall() =>
      (((_ball - _wheel) % (2 * pi)) / roulettePocketAngle).floor() %
      rouletteWheel.length;

  void _frame(Duration elapsed) {
    final dt = (elapsed - _lastFrame).inMicroseconds / 1e6;
    _lastFrame = elapsed;
    final spin = _spin;
    if (spin != null) {
      final u = DateTime.now().difference(spin.start).inMicroseconds /
          spin.length.inMicroseconds;
      final f = rouletteSpinFrame(
        u: u,
        wheelStart: spin.wheelStart,
        result: spin.result,
      );
      _wheel = f.wheel;
      _ball = f.ball;
      _lift = f.radius;
      _pose.value++;
      final pocket = _pocketUnderBall();
      if (pocket != _lastPocket) {
        _lastPocket = pocket;
        final now = DateTime.now();
        if (now.difference(_lastTick).inMilliseconds > 60) {
          _lastTick = now;
          _sfx.tick();
        }
      }
      if (u >= 1) _land(spin.result);
      return;
    }
    // Idle: the wheel drifts; a landed ball rides with it.
    _wheel += dt * 2 * pi / 24;
    final resting = _landed ?? _rest;
    if (resting != null) _ball = _wheel + roulettePocketCenter(resting);
    if (_glow > 0 && _landed != null) {
      _glow = .6 + .4 * sin(elapsed.inMilliseconds / 250);
    }
    _pose.value++;
  }

  void _land(int result, {bool sound = true}) {
    _spin = null;
    if (sound) _sfx.stop();
    setState(() {
      _landed = result;
      _ball = _wheel + roulettePocketCenter(result);
      _lift = 0;
      _glow = 1;
    });
    _syncTicker();
    final s = state;
    if (s != null && s.phase == 'result') {
      _refreshMine();
    }
  }

  /// Hurries the animation; the result was fixed before the wheel moved.
  void skip() {
    final s = _spin;
    if (s != null) _land(s.result);
  }

  // ── Betting ───────────────────────────────────────────────────────────────
  void _send(
    Future<Map<String, dynamic>> Function() call, {
    bool chipSound = true,
  }) {
    if (!_betting) {
      setState(() => _notice = _s.text('closing'));
      return;
    }
    setState(() => _pending++);
    _queue = _queue.then((_) async {
      try {
        final body = await call();
        if (!mounted) return;
        if (chipSound) _sfx.chip();
        ref
            .read(authStateProvider.notifier)
            .updateCoinsBalance((body['balance'] as num?)?.toInt() ?? _balance);
        setState(() {
          myStakes = {
            for (final e
                in Map<String, dynamic>.from(body['stakes'] as Map? ?? const {})
                    .entries)
              e.key: (e.value as num).toInt(),
          };
          _notice = null;
        });
      } on RouletteException catch (e) {
        if (mounted) setState(() => _notice = _s.text(e.code));
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
    _send(() => _repository.bet(key, chip));
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
      'roulette.${ref.read(authStateProvider).user?.id ?? 0}.chip',
      value,
    );
  }

  void _setting(String key, bool value) => _prefs?.setBool(
        'roulette.${ref.read(authStateProvider).user?.id ?? 0}.$key',
        value,
      );

  // ── Sheets ────────────────────────────────────────────────────────────────
  void _sheet(String title, Widget body) {
    _sfx.click();
    rouletteSheet<void>(context, _s, _s.text(title), body);
  }

  void _openHelp() => _sheet(
        'help',
        RouletteHelp(
          strings: _s,
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
      _sheet('history', RouletteHistoryView(strings: _s, rounds: rounds));
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
      RouletteBoard(
        strings: _s,
        rows: (board['entries'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
        valueKey: 'net',
        empty: 'emptyRanking',
        footer: Text(
          '${_s.text('todayNet')}: ${me['net'] ?? 0} · ${_s.text('bestWin')}: ${me['best'] ?? 0}',
          style: const TextStyle(color: rlGoldLight),
        ),
      ),
    );
  }

  void _openPlayers() => _sheet(
        'players',
        RouletteBoard(
          strings: _s,
          rows: state?.players ?? const [],
          valueKey: 'staked',
          empty: 'emptyPlayers',
        ),
      );

  void _openSettings() => _sheet(
        'settings',
        RouletteSettings(
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
        backgroundColor: rlBlack,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [rlBlack, rlNavy, rlPurpleDark],
                ),
              ),
            ),
            Image.asset(
              'assets/images/games/roulette/background.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            SafeArea(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: rlGold),
                          const SizedBox(height: 12),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: rlPink),
                onPressed: _boot,
                child: Text(_s.text('retry')),
              ),
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: Text(
                  _s.text('back'),
                  style: const TextStyle(color: rlMuted),
                ),
              ),
            ],
          ),
        ),
      );

  /// One screen, no scrolling. The whole wheel is always on stage at the top;
  /// the felt lies under it the way a real table does, numbers running
  /// left to right, with the outside bets along its bottom edge.
  Widget _game(int balance) => LayoutBuilder(
        builder: (context, box) {
          final width = min(box.maxWidth, 560.0);
          return Center(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    _header(balance),
                    _metaBar(),
                    const SizedBox(height: 6),
                    _historyRow(),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, area) {
                          final felt = _Felt(area.maxWidth);
                          // Totals bar (≈36) and the gaps around it.
                          final room = area.maxHeight - felt.height - 50;
                          final wheel = max(0.0, min(area.maxWidth * .92, room));
                          return Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: wheel,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.center,
                                      children: [
                                        _wheelBlock(wheel),
                                        if (_notice != null)
                                          Positioned(
                                            left: -20,
                                            right: -20,
                                            bottom: wheel * .04,
                                            child: _noticeView(),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              _totals(),
                              const SizedBox(height: 6),
                              _table(felt),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    _chipBar(),
                    const SizedBox(height: 6),
                  ],
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
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(
                      color: rlGold,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: rlPurple, blurRadius: 8)],
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    label: '${_s.text('balance')}: $balance',
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: rlGold,
                            size: 16,
                          ),
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
            _RoundButton(
              icon: Icons.settings,
              label: _s.text('settings'),
              onTap: _openSettings,
            ),
            const SizedBox(width: 6),
            _Pill(
              label: _s.text('recharge'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalletScreen()),
              ),
            ),
          ],
        ),
      );

  String _phaseText() {
    final s = state;
    if (s == null) return '';
    return switch (s.phase) {
      'betting' => '${_s.text('betting')} · ${_s.seconds(s.left.inSeconds)}',
      'closing' => _s.text('closing'),
      'spinning' => _s.text('spinning'),
      _ => s.result == null || _landed == null
          ? _s.text('spinning')
          : _s.winning(s.result!),
    };
  }

  Widget _metaBar() => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 6, 4),
        decoration: BoxDecoration(
          color: rlNavy2.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: rlFeltBorder.withValues(alpha: .5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s.round(state?.round ?? 0),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(
                        color: rlGoldLight,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _seconds,
                      builder: (_, __, ___) {
                        final urgent =
                            _betting && (state?.left.inSeconds ?? 99) < 4;
                        return Text(
                          _phaseText(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                urgent ? const Color(0xFFFF6B7A) : Colors.white,
                            fontWeight:
                                urgent ? FontWeight.w900 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            _RoundButton(
              icon: Icons.groups,
              label: _s.text('players'),
              onTap: _openPlayers,
              size: 40,
            ),
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: _s.text('ranking'),
              child: InkWell(
                onTap: _openRanking,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient:
                        const LinearGradient(colors: [rlPurple, rlPurpleDark]),
                    border: Border.all(color: rlGold),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const RouletteArt(
                        'trophy',
                        size: 22,
                        fallback: Icon(
                          Icons.emoji_events,
                          color: rlGold,
                          size: 20,
                        ),
                      ),
                      // Narrow phones keep the trophy; the word needs room.
                      if (MediaQuery.sizeOf(context).width >= 380) ...[
                        const SizedBox(width: 4),
                        Text(
                          _s.text('ranking'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  /// The painted wheel at [size]. It repaints from [_pose] alone, so the ball
  /// can run at 60 fps without rebuilding the felt.
  Widget _wheelBlock(double size) {
    return Semantics(
      label: _phaseText(),
      button: _spin != null,
      onTap: _spin != null ? skip : null,
      child: GestureDetector(
        onTap: skip,
        child: SizedBox.square(
          dimension: size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _pose,
              builder: (_, __) => Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(size),
                    painter: RouletteWheelPainter(
                      wheelAngle: _wheel,
                      ballAngle: _ball,
                      ballLift: _lift,
                      highlight: _landed,
                      glow: _glow,
                      showBall:
                          _spin != null || _landed != null || _rest != null,
                    ),
                  ),
                  Transform.rotate(
                    angle: _wheel,
                    child: RouletteArt(
                      'turret',
                      size: size * .4,
                      fallback:
                          const CustomPaint(painter: RouletteTurretPainter()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyRow() {
    final history = (state?.history ?? const <int>[])
        .reversed
        .take(rouletteHistoryLength)
        .toList();
    return Row(
      children: [
        Semantics(
          button: true,
          label: _s.text('history'),
          child: InkWell(
            onTap: _openHistory,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: rlFeltDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: rlFeltBorder),
              ),
              child: Text(
                '${_s.text('new')} ›',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (i, n) in history.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Semantics(
                      label: '$n ${_s.color(n)}',
                      child: rouletteBall(n, size: 28, ring: i == 0),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _RoundButton(
          icon: Icons.question_mark,
          label: _s.text('help'),
          onTap: _openHelp,
          size: 40,
        ),
      ],
    );
  }

  Widget _totals() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [rlNavy2, rlPurpleDark]),
          border: Border.all(color: rlGold.withValues(alpha: .6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '${_s.text('totalBet')}: ${state?.totalBet ?? 0}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                '${_s.text('myTotalBet')}: $_myTotal',
                maxLines: 1,
                style: const TextStyle(
                  color: rlGoldLight,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_pending > 0)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 6),
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: rlGold,
                  ),
                ),
              ),
          ],
        ),
      );

  /// The round's outcome as a plaque over the bottom of the wheel.
  Widget _noticeView() => IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_notice),
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: _reduced ? 0 : 380),
            curve: Curves.easeOutBack,
            builder: (_, t, child) => Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.scale(scale: .85 + .15 * t, child: child),
            ),
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xEE1D2454), Color(0xEE260C4C)],
                  ),
                  border: Border.all(color: rlGold, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 10),
                  ],
                ),
                child: Text(
                  _notice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: rlGoldLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  // ── The felt ──────────────────────────────────────────────────────────────
  /// A real table's layout: zero on the left, three rows of twelve numbers
  /// (3 … 36 on top, 1 … 34 at the bottom), the 2:1 columns on the right,
  /// then the dozens and the even-money bets along the bottom edge.
  Widget _table(_Felt f) {
    final result =
        state?.phase == 'result' && _landed != null ? state?.result : null;
    final locked = !_betting;
    Widget outside(String key, double w, double h, {Color? fill}) {
      final mine = myStakes[key] ?? 0, all = state?.totals[key] ?? 0;
      final wins = result != null &&
          (rouletteBet(key)?.numbers.contains(result) ?? false);
      return SizedBox(
        width: w,
        height: h,
        child: Semantics(
          button: true,
          label:
              '${_s.bet(key)}, ×${rouletteBet(key)!.multiplier}, $mine / $all',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => placeChip(key),
            child: Container(
              decoration: BoxDecoration(
                color: fill ?? (wins ? rlGold.withValues(alpha: .25) : null),
                border: Border.all(
                  color: wins ? rlGoldLight : Colors.white60,
                  width: wins ? 2 : .7,
                ),
                boxShadow: wins
                    ? [
                        BoxShadow(
                          color: rlGold.withValues(alpha: .7),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: FittedBox(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _s.text(key),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            '$mine/$all',
                            style: const TextStyle(
                              color: rlGoldLight,
                              fontSize: 10,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (mine > 0)
                    PositionedDirectional(
                      end: 1,
                      top: 1,
                      child: RouletteChip(value: mine, size: min(w, h) * .62),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedOpacity(
        opacity: locked ? .7 : 1,
        duration: const Duration(milliseconds: 250),
        child: Container(
          width: f.width,
          height: f.height,
          padding: const EdgeInsets.all(_Felt.pad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const RadialGradient(
              radius: 1.2,
              colors: [Color(0xFF0E8A55), rlFelt, rlFeltDark],
              stops: [0, .55, 1],
            ),
            border: Border.all(color: rlGold.withValues(alpha: .8), width: 2),
            boxShadow: [
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: rlFeltBorder.withValues(alpha: .2),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _zeroCell(f.zeroW, f.cellH * 3, result),
                  SizedBox(
                    width: f.cellW * rouletteRows,
                    height: f.cellH * 3,
                    child: _grid(f.cellW, f.cellH, result),
                  ),
                  Column(
                    children: [
                      for (final key in rouletteColumns.reversed)
                        outside(key, f.columnW, f.cellH),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(width: f.zeroW),
                  for (final key in rouletteDozens)
                    outside(key, f.cellW * 4, f.rowH),
                ],
              ),
              Row(
                children: [
                  SizedBox(width: f.zeroW),
                  for (final key in rouletteOutside)
                    outside(
                      key,
                      f.cellW * 2,
                      f.rowH,
                      fill: key == 'red'
                          ? rlRed
                          : key == 'black'
                              ? rlPocketBlack
                              : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zeroCell(double w, double h, int? result) {
    final mine = myStakes['n:0'] ?? 0;
    final wins = result == 0;
    return Semantics(
      button: true,
      label: '0 ${_s.text('green')}, ×26, $mine',
      child: GestureDetector(
        onTap: () => placeChip('n:0'),
        child: Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF16A867), rlZero, Color(0xFF05532F)],
            ),
            borderRadius:
                BorderRadius.horizontal(left: Radius.circular(w * .9)),
            border: Border.all(
              color: wins ? rlGoldLight : Colors.white60,
              width: wins ? 2.5 : .7,
            ),
            boxShadow: wins
                ? [BoxShadow(color: rlGold.withValues(alpha: .8), blurRadius: 12)]
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: w * .7,
                child: const FittedBox(
                  child: Text(
                    '0',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              if (mine > 0)
                Positioned(
                  bottom: 4,
                  child: RouletteChip(value: mine, size: w * .8),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Twelve columns of three. The engine counts in its own terms (row =
  /// which three, col = 1st/2nd/3rd of them), so a tap is turned a quarter:
  /// across the felt is down the engine's rows, up the felt is across.
  Widget _grid(double cellW, double cellH, int? result) {
    final winning = result == null
        ? const <String>{}
        : rouletteWinningKeys(myStakes, result);
    final chipSize = min(cellW, cellH) * .8;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final p = d.localPosition;
        final row = (p.dx / cellW).floor().clamp(0, rouletteRows - 1),
            line = (p.dy / cellH).floor().clamp(0, 2);
        placeChip(
          rouletteKeyAt(
            row,
            2 - line,
            1 - (p.dy / cellH - line),
            p.dx / cellW - row,
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var row = 0; row < rouletteRows; row++)
            for (var col = 0; col < 3; col++)
              Positioned(
                left: row * cellW,
                top: (2 - col) * cellH,
                width: cellW,
                height: cellH,
                child: Builder(
                  builder: (_) {
                    final n = rouletteNumberAt(row, col);
                    final wins = result == n;
                    final base = roulettePaint(n);
                    return Semantics(
                      button: true,
                      label: '$n ${_s.color(n)}, ×26, ${myStakes['n:$n'] ?? 0}',
                      onTap: () => placeChip('n:$n'),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white60, width: .5),
                        ),
                        padding: const EdgeInsets.all(1.5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.lerp(base, Colors.white, .18)!,
                                base,
                                Color.lerp(base, Colors.black, .3)!,
                              ],
                            ),
                            border: wins
                                ? Border.all(color: rlGoldLight, width: 2)
                                : null,
                            boxShadow: wins
                                ? [
                                    BoxShadow(
                                      color: rlGold.withValues(alpha: .9),
                                      blurRadius: 12,
                                    ),
                                  ]
                                : null,
                          ),
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Text(
                                '$n',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(color: Colors.black45, blurRadius: 2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          for (final entry in myStakes.entries)
            if (entry.value > 0 &&
                rouletteAnchor(entry.key) != null &&
                rouletteAnchor(entry.key)!.dy >= 0)
              Positioned(
                left: rouletteAnchor(entry.key)!.dy * cellW - chipSize / 2,
                top: (3 - rouletteAnchor(entry.key)!.dx) * cellH - chipSize / 2,
                child: IgnorePointer(
                  child: AnimatedScale(
                    scale: winning.contains(entry.key) ? 1.25 : 1,
                    duration: const Duration(milliseconds: 300),
                    child: RouletteChip(value: entry.value, size: chipSize),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Pinned under the felt: chips on one row, actions under them.
  Widget _chipBar() => Column(
        children: [
          LayoutBuilder(
            builder: (_, box) {
              final size = min(44.0, box.maxWidth / 5 - 14);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final value in rouletteChips)
                    Semantics(
                      button: true,
                      selected: value == chip,
                      label: '$value',
                      child: GestureDetector(
                        onTap: () => _pickChip(value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: value == chip
                                  ? rlGoldLight
                                  : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: value == chip
                                ? [
                                    BoxShadow(
                                      color: rlGold.withValues(alpha: .7),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: RouletteChip(
                            value: value,
                            size: value == chip ? size + 6 : size,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.undo,
                  label: _s.text('undo'),
                  onTap: _betting && _myTotal > 0 ? _undo : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionButton(
                  icon: Icons.delete_sweep,
                  label: _s.text('clear'),
                  onTap: _betting && _myTotal > 0 ? _clear : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionButton(
                  icon: Icons.replay,
                  label: _s.text('rebet'),
                  onTap: _betting && _myTotal == 0 ? _rebet : null,
                  primary: true,
                ),
              ),
            ],
          ),
        ],
      );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  const _RoundButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 44,
  });
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: rlPurple,
            shape: CircleBorder(
              side: BorderSide(
                color: rlFeltBorder.withValues(alpha: .8),
                width: 2,
              ),
            ),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: size,
                child: Icon(icon, color: Colors.white, size: size * .5),
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
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [rlGoldLight, rlGold]),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: rlPurpleDark,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: Opacity(
          opacity: onTap == null ? .5 : 1,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: LinearGradient(
                  colors:
                      primary ? [rlPink, rlPurple] : [rlNavy2, rlPurpleDark],
                ),
                border: Border.all(
                  color: primary
                      ? const Color(0xFFFFA6D5)
                      : rlFeltBorder.withValues(alpha: .6),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
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

/// The felt's measurements at [width]: zero (1.1 cells), twelve number
/// columns, the 2:1 bets (1.3 cells), then two rows of outside bets.
class _Felt {
  static const pad = 4.0, border = 2.0;
  final double width;
  _Felt(this.width);
  late final double inner = width - 2 * (pad + border);
  late final double cellW = inner / 14.4;
  late final double zeroW = cellW * 1.1;
  late final double columnW = inner - zeroW - cellW * rouletteRows;
  late final double cellH = (cellW * 1.3).clamp(26.0, 46.0);
  late final double rowH = cellH * .85;
  late final double height = cellH * 3 + rowH * 2 + 2 * (pad + border);
}

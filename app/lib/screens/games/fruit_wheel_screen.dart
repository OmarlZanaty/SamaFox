import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/fruit_wheel_repository.dart';
import '../../services/socket_service.dart';
import '../wallet_screen.dart';
import 'fruit_wheel_art.dart';
import 'fruit_wheel_engine.dart';
import 'fruit_wheel_preferences.dart';
import 'fruit_wheel_sfx.dart';
import 'fruit_wheel_sheets.dart';
import 'fruit_wheel_strings.dart';

class FruitWheelScreen extends ConsumerStatefulWidget {
  final FruitWheelRepository? repository;
  final bool live;
  const FruitWheelScreen({super.key, this.repository, this.live = true});
  @override
  ConsumerState<FruitWheelScreen> createState() => FruitWheelScreenState();
}

class FruitWheelScreenState extends ConsumerState<FruitWheelScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final FruitWheelRepository _repository =
      widget.repository ?? FruitWheelRepository();
  final _sfx = FruitWheelSfx();
  final _socket = SocketService();
  late final AnimationController _spin = AnimationController(vsync: this);
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _ambient =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));
  Animation<double>? _spinAngle;
  FruitWheelPreferences? _preferences;
  Map<String, dynamic>? _layout;
  FruitWheelState? state;
  bool _loading = true, _arabic = true, _sound = true, _motion = true;
  bool _pending = false, _subscribed = false, _refreshing = false;
  String? _error, _notice;
  double _angle = 0;
  int? _highlight, _animatedRound, _announced;
  int _chip = fruitChips.first, _seconds = 0, _lastWarning = -1, _payout = 0;
  FruitBets bets = FruitBets();
  List<List<String>> _ticker = [];
  List<Map<String, dynamic>> _leaders = [];
  int? _myRank;
  int _myWon = 0;
  Timer? _clock, _noticeTimer;
  int _pollTicks = 0, _mutation = 0;

  FruitWheelStrings get _s => FruitWheelStrings(_arabic);
  int get _balance => ref.read(authStateProvider).user?.coinsBalance ?? 0;
  double get _maxBet => (_layout?['maxPerKey'] as num?)?.toDouble() ?? double.infinity;
  Map<String, double> get _multipliers =>
      fruitTableMultipliers(_layout?['multipliers']);
  List<int> get _chips => fruitChips;
  bool get _reduced => !_motion || MediaQuery.disableAnimationsOf(context);
  bool get _betting => state?.betting == true && state!.left.inMilliseconds > 0;
  bool get _busy => !_betting || _pending;
  bool get _urgent => _betting && _seconds <= 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spin.addListener(() {
      if (mounted && _spinAngle != null) {
        setState(() => _angle = _spinAngle!.value);
      }
    });
    _clock = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _tickClock();
      // REST repairs missed socket events and also powers the offline preview.
      if (++_pollTicks % 15 == 0 && !_loading) _refreshMine();
    });
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onReconnect(null);
  }

  void _syncAmbient() {
    if (!_reduced) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      _ambient.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _noticeTimer?.cancel();
    if (_subscribed) {
      _socket.off('connect', _onReconnect);
      _socket.off('fruitwheel_state', _onSocketState);
      _socket.off('fruitwheel_result', _onSocketResult);
      _socket.emit('fruitwheel_leave_table', {});
    }
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
      final account =
          ref.read(authStateProvider).user?.id.toString() ?? 'guest';
      final prefs = _preferences ??=
          FruitWheelPreferences(await SharedPreferences.getInstance(), account);
      if (!mounted) return;
      _arabic = prefs.arabic;
      _sound = _sfx.enabled = prefs.sound;
      _motion = prefs.motion;
      _chip = fruitChips.contains(prefs.chip) ? prefs.chip : 100;
      if (widget.live && !_subscribed) {
        _subscribed = true;
        _socket.on('connect', _onReconnect);
        _socket.on('fruitwheel_state', _onSocketState);
        _socket.on('fruitwheel_result', _onSocketResult);
        _socket.emit('fruitwheel_join_table', {});
      }
      final body = await _repository.fetchState();
      if (!mounted) return;
      _acceptMine(body);
      setState(() => _loading = false);
      _syncAmbient();
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

  void _acceptMine(Map<String, dynamic> body) {
    ref
        .read(authStateProvider.notifier)
        .updateCoinsBalance((body['balance'] as num?)?.toInt() ?? _balance);
    if (body['layout'] is Map) {
      _layout = Map<String, dynamic>.from(body['layout']);
    }
    if (body['state'] is Map) {
      applyState(Map<String, dynamic>.from(body['state']), mine: true);
    }
  }

  void _onReconnect(dynamic _) {
    if (widget.live) _socket.emit('fruitwheel_join_table', {});
    _refreshMine();
  }

  void _onSocketState(dynamic data) {
    if (mounted && data is Map) applyState(Map<String, dynamic>.from(data));
  }

  void _onSocketResult(dynamic _) => _refreshMine();
  Future<void> _refreshMine() async {
    if (_refreshing || _pending) return;
    _refreshing = true;
    final mutation = _mutation;
    try {
      final body = await _repository.fetchState();
      if (mounted && !_pending && mutation == _mutation) _acceptMine(body);
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  void _tickClock() {
    if (!mounted) return;
    final seconds = ((state?.left.inMilliseconds ?? 0) / 1000).ceil();
    if (seconds != _seconds) setState(() => _seconds = seconds);
    if (_urgent && seconds > 0 && seconds != _lastWarning) {
      _lastWarning = seconds;
      _sfx.tick();
    }
  }

  void applyState(Map<String, dynamic> json, {bool mine = false}) {
    if (!mounted) return;
    final next = FruitWheelState.fromJson(json);
    const phases = ['betting', 'closing', 'spinning', 'result'];
    final changedTable = state != null &&
        next.tableId.isNotEmpty &&
        next.tableId != state!.tableId;
    if (state != null &&
        !changedTable &&
        (next.round < state!.round ||
            (next.round == state!.round &&
                phases.indexOf(next.phase) < phases.indexOf(state!.phase)))) {
      return;
    }
    final changed = changedTable || next.round != state?.round;
    setState(() {
      if (changed) {
        _announced = null;
        _spin.stop();
        _spinAngle = null;
        _highlight = null;
        _animatedRound = null;
        bets = FruitBets();
        _payout = 0;
        _lastWarning = -1;
        _notice = null;
      }
      state = next;
      if (mine) {
        bets = FruitBets(next.myStakes);
        _payout = next.myPayout;
      }
      _ticker = next.historyResults.reversed.take(10).toList();
    });
    _tickClock();
    if (next.phase == 'spinning' &&
        next.result != null &&
        _animatedRound != next.round) {
      _animatedRound = next.round;
      final end =
          fruitStopAngle(_angle, next.segment, next.offset, _reduced ? 0 : 5);
      if (_reduced || next.msLeft < 5500) {
        setState(() => _angle = end);
      } else {
        _spinAngle = Tween<double>(begin: _angle, end: end).animate(
          CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic),
        );
        _spin.duration = Duration(milliseconds: next.msLeft);
        _spin.forward(from: 0);
        _sfx.spin();
      }
    }
    if (next.phase == 'result' && next.results.isNotEmpty) {
      _spin.stop();
      _spinAngle = null;
      _angle = fruitStopAngle(_angle, next.segment, next.offset, 0);
      _highlight = next.results.length > 1 ? null : next.segment;
      _glow.value = 1;
      if (mine && _announced != next.round) {
        _announced = next.round;
        if (_payout > 0) {
          _sfx.win(_payout >= next.myStaked * _multipliers['sevens']!);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              state?.round == next.round &&
              state?.phase == 'result') {
            showDialog<void>(
              context: context,
              builder: (_) => FruitWinners(
                strings: _s,
                winners: next.winners,
                staked: next.myStaked,
                payout: next.myPayout,
                results: next.results,
                multipliers: _multipliers,
                duration: next.left,
              ),
            );
          }
        });
        unawaited(_loadLeaders());
      } else if (!mine) {
        _refreshMine();
      }
    }
  }

  void _say(String key) {
    _noticeTimer?.cancel();
    setState(() => _notice = _s.text(key));
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _pickChip(int chip) {
    if (_busy) return;
    setState(() => _chip = chip);
    _preferences?.setChip(chip);
    _sfx.click();
  }

  void placeChip(String card) {
    if (_busy || !fruitCards.contains(card)) return;
    if (bets[card] == 0 && fruitCards.where((c) => bets[c] > 0).length >= 2) {
      _say('MAX_CARDS');
      return;
    }
    if (bets[card] + _chip > _maxBet) {
      _say('MAX_BET');
      return;
    }
    if (_chip > _balance) {
      _say('INSUFFICIENT_COINS');
      return;
    }
    _send(() => _repository.bet(card, _chip));
  }

  Future<void> _send(Future<Map<String, dynamic>> Function() call) async {
    if (_busy) return;
    final requestRound = state!.round;
    _mutation++;
    setState(() => _pending = true);
    try {
      final body = await call();
      if (!mounted) return;
      ref
          .read(authStateProvider.notifier)
          .updateCoinsBalance((body['balance'] as num?)?.toInt() ?? _balance);
      if (requestRound == state?.round) {
        setState(
          () => bets = FruitBets.fromJson(body['stakes']) ?? FruitBets(),
        );
      }
      _sfx.click();
    } on FruitWheelException catch (e) {
      if (mounted) _say(e.code);
    } catch (_) {
      if (mounted) _say('FAILED');
    } finally {
      if (mounted) {
        setState(() => _pending = false);
        unawaited(_refreshMine());
      }
    }
  }

  void _clearBets() => _send(_repository.clear);
  Future<void> _loadLeaders() async {
    try {
      final body = await _repository.ranking();
      if (mounted) {
        setState(() {
          _leaders = (body['entries'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _myRank = (body['me']?['rank'] as num?)?.toInt();
          _myWon = (body['me']?['net'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {}
  }

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

  void _open(String key, Widget body) =>
      fruitSheet<void>(context, _s, _s.text(key), body);
  void _openHelp() => _open(
        'help',
        FruitHelp(strings: _s, layout: _layout ?? {}, state: state),
      );
  Future<void> _openHistory() async {
    try {
      final rows = await _repository.history();
      if (mounted) _open('history', FruitHistory(strings: _s, rounds: rows));
    } catch (_) {
      if (mounted) _say('NETWORK');
    }
  }

  void _openLeaders() => _open(
        'leaders',
        FruitLeaders(
          strings: _s,
          entries: _leaders,
          myRank: _myRank,
          myWon: _myWon,
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
        ),
      );

  // ── Layout ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(authStateProvider).user?.coinsBalance ?? 0;
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
                          Text(
                            _s.text('loading'),
                            style: const TextStyle(color: Colors.white),
                          ),
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
              Text(
                _error!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: fwPink),
                onPressed: _boot,
                child: Text(_s.text('retry')),
              ),
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: Text(
                  _s.text('back'),
                  style: const TextStyle(color: fwMuted),
                ),
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
            physics: box.maxHeight >= 640
                ? const NeverScrollableScrollPhysics()
                : null,
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
                    label:
                        '${_s.text('balance')}: $balance ${_s.text('coins')}',
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: fwGold,
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
            _s.round(state?.round ?? 0),
            style: const TextStyle(
              color: fwCream,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: '${_s.text('weekRank')}: ${_s.rank(_myRank)}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient:
                    const LinearGradient(colors: [fwCream, fwGold, fwGoldDark]),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events, color: fwPurpleDeep, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    _s.rank(_myRank),
                    style: const TextStyle(
                      color: fwPurpleDeep,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
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
                  _RoundButton(
                    icon: Icons.people,
                    label: _s.text('leaders'),
                    onTap: _openLeaders,
                    size: 34,
                  ),
                  const SizedBox(width: 5),
                  _RoundButton(
                    icon: Icons.question_mark,
                    label: _s.text('help'),
                    onTap: _openHelp,
                    size: 34,
                  ),
                  const SizedBox(width: 5),
                  _RoundButton(
                    icon: Icons.receipt_long,
                    label: _s.text('history'),
                    onTap: _openHistory,
                    size: 34,
                  ),
                  const SizedBox(width: 5),
                  _RoundButton(
                    icon: soundIcon,
                    label: _s.text(_sound ? 'soundOff' : 'soundOn'),
                    onTap: () => _setSound(!_sound),
                    size: 34,
                  ),
                  const SizedBox(width: 5),
                  _RoundButton(
                    icon: Icons.settings,
                    label: _s.text('settings'),
                    onTap: _openSettings,
                    size: 34,
                  ),
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
                colors: [
                  fwPurpleDeep.withValues(alpha: .9),
                  fwPinkDark.withValues(alpha: .5),
                ],
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
                                    gradient: const LinearGradient(
                                      colors: [fwGold, fwPink],
                                    ),
                                    boxShadow: [
                                      if (e == _leaders.first)
                                        const BoxShadow(
                                          color: fwGold,
                                          blurRadius: 8,
                                        ),
                                    ],
                                  ),
                                  child: fruitAvatar(
                                    e['avatarUrl']?.toString(),
                                    e['name']?.toString() ?? '',
                                    34,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '🔥 ${fruitCompact((e['net'] as num?)?.toInt() ?? 0)}',
                                style: const TextStyle(
                                  color: fwGold,
                                  fontSize: 11,
                                ),
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
            BoxShadow(
              color: fwBlueBright.withValues(alpha: .35),
              blurRadius: 18,
              spreadRadius: 1,
            ),
            const BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
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
                                    duration: Duration(
                                      milliseconds: _reduced ? 0 : 420,
                                    ),
                                    curve: Curves.easeOutBack,
                                    builder: (_, t, child) => Opacity(
                                      opacity: t.clamp(0.0, 1.0),
                                      child: Transform.scale(
                                        scale: .8 + .2 * t,
                                        child: child,
                                      ),
                                    ),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          color: const Color(0xEE1F0A3D),
                                          border: Border.all(
                                            color: fwGold,
                                            width: 1.5,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black54,
                                              blurRadius: 10,
                                            ),
                                          ],
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
                IconButton(
                  tooltip: _s.text('undo'),
                  color: fwCream,
                  onPressed: _busy ? null : () => _send(_repository.undo),
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: _s.text('repeatBets'),
                  color: fwCream,
                  onPressed: _busy ? null : () => _send(_repository.repeat),
                  icon: const Icon(Icons.repeat),
                ),
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
            final center = state?.betting == true
                ? '$_seconds'
                : state?.phase == 'result'
                    ? '$_payout'
                    : '…';
            return Semantics(
              label: state?.betting == true
                  ? '${_s.text('betting')} $_seconds'
                  : _s.text(state?.phase ?? 'loading'),
              liveRegion: true,
              child: SizedBox(
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
                          winningCards: state?.phase == 'result'
                              ? state!.results : const [],
                          glow: _glow.value,
                          bulbPhase: state?.phase == 'spinning'
                              ? (_angle / (2 * pi)) % 1
                              : _ambient.value,
                        ),
                      ),
                      for (var i = 0; i < fruitSegments.length; i++)
                        Builder(
                          builder: (_) {
                            final a = _angle + (i + .5) * fruitSegmentAngle;
                            final pop = state?.phase == 'result' &&
                                    state!.results.contains(fruitSegments[i])
                                ? 1 + .25 * _glow.value : 1.0;
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
                      if (!(state?.phase == 'result' && (state?.results.length ?? 0) > 1))
                      Positioned(
                        top: -size * .03,
                        left: size / 2 - size * .06,
                        child: CustomPaint(
                          size: Size(size * .12, size * .13),
                          painter: FruitPointerPainter(glow: _glow.value),
                        ),
                      ),
                      Center(
                        child: Transform.scale(
                          scale: _urgent && !_reduced
                              ? 1 + .08 * sin(_ambient.value * 2 * pi)
                              : 1,
                          child: _hub(size * .27, center),
                        ),
                      ),
                      if (state?.phase == 'result' && state?.bonus != null)
                        Positioned(
                          top: size * .04,
                          left: 12,
                          right: 12,
                          child: _bonusLabel(_s.bonusBanner(state!.bonus!)),
                        ),
                      if (state?.bonusEnabled == true &&
                          state?.roundsToBonus != null &&
                          (state!.phase == 'betting' || state!.phase == 'closing'))
                        Positioned(
                          left: 8,
                          right: 8,
                          top: size * .76,
                          child: _bonusLabel(_s.bonusCountdown(state!.roundsToBonus!)),
                        ),
                      // A pill just under the hub: bare red text over the
                      // wedges was unreadable against the fruit art.
                      if (_urgent)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: size / 2 + size * .27 / 2 + 6,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: fwPurpleDeep.withOpacity(.92),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: fwRed, width: 1.5),
                              ),
                              child: Text(
                                _s.text('urgent'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _bonusLabel(String text) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: fwPurpleDeep,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: fwGold, fontSize: 12, fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

  Widget _hub(double size, String value) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: _urgent ? [fwRed, fwPinkDark] : [fwPurple, fwPurpleDeep],
          ),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
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
                            boxShadow: [
                              BoxShadow(
                                color: fwGold.withValues(alpha: .8),
                                blurRadius: 10,
                              ),
                            ],
                          )
                        : null,
                    child: Semantics(
                      label: _ticker[i].map((card) => card == 'crown' ? '—' : _s.text(card)).join(' + '),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final card in _ticker[i])
                            FruitArt(card, size: i == 0 ? 34 : 28),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _cards() => LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 300;
          final cardWidth = narrow ? 104.0 : (box.maxWidth - 16) / 3;
          final row = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final card in fruitCards)
                SizedBox(width: cardWidth, child: _card(card)),
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
    final mine = bets[card];
    final winning = state?.phase == 'result' && state!.results.contains(card);
    // A bonus payout is a round total; show it in the hub and winners dialog.
    final won = winning && state?.bonus == null ? _payout : 0;
    final glow = winning ? _glow.value : 0.0;
    final bottom = won > 0 ? '+$won' : '$mine';
    return Semantics(
      button: true,
      label:
          '${_s.text(card)} ${fruitMultiplierLabel(_multipliers[card]!)}, ${_s.text('yourBet')}: $mine${won > 0 ? ', ${_s.text('won')} $won' : ''}',
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
              border: Border.all(
                color: winning ? fwCream : fwGold,
                width: winning ? 3 : 2,
              ),
              boxShadow: [
                if (winning)
                  BoxShadow(
                    color: fwGold.withValues(alpha: .8 * glow),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                const BoxShadow(
                  color: Colors.black45,
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: _s.text('totalBet'),
                  child: Text(
                    fruitCompact(state?.totals[card] ?? 0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FruitArt('capsule_$card', size: 58),
                Text(
                  fruitMultiplierLabel(_multipliers[card]!),
                  style: const TextStyle(
                    color: fwGold,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: fwGoldDark, offset: Offset(0, 2))],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
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
            color: fwPurple,
            shape: CircleBorder(
              side: BorderSide(
                color: fwPurpleLight.withValues(alpha: .9),
                width: 2,
              ),
            ),
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
              gradient:
                  const LinearGradient(colors: [fwGold, Color(0xFFFF9F1C)]),
              boxShadow: [
                BoxShadow(color: fwGold.withValues(alpha: .5), blurRadius: 8),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: fwPurpleDeep,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
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
            border: Border.all(
              color: selected ? Colors.white : fwCream.withValues(alpha: .6),
              width: selected ? 3 : 2,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: Colors.white.withValues(alpha: .6),
                  blurRadius: 10,
                ),
              const BoxShadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
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
        onTapDown:
            widget.onTap == null ? null : (_) => setState(() => _down = true),
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

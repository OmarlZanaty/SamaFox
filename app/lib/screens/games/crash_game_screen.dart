import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../repositories/crash_repository.dart';
import '../../services/socket_service.dart';

/// طيّار — the Aviator-style crash game.
///
/// The server owns the crash point, the clock and every coin movement
/// (backend/src/services/crash.service.ts). This screen animates the published
/// curve `m(t) = e^(GROWTH * t)` locally so the multiplier is perfectly smooth
/// without streaming ticks, and asks the server to bet / cash out.
///
/// The flight clock is anchored off the server's own `elapsedMs` rather than its
/// wall clock, so a device with a skewed clock still draws the right curve.
class CrashGameScreen extends ConsumerStatefulWidget {
  const CrashGameScreen({super.key});

  @override
  ConsumerState<CrashGameScreen> createState() => _CrashGameScreenState();
}

class _CrashGameScreenState extends ConsumerState<CrashGameScreen>
    with TickerProviderStateMixin {
  /// Must match CRASH_GROWTH in backend/src/services/crash.service.ts.
  static const double _growth = 0.0001;

  // Palette. The original spec called for grey #1b1b1b with maroon #9b1c31 and
  // bootstrap-ish buttons, but desaturated grey has no hue to catch light, so
  // every glow drawn over it read as dirt rather than neon. Moved to a
  // saturated indigo-violet base with hot accents — see
  // assets/images/crash/ART_BRIEF.md, which the artwork is being drawn against.
  static const _bg = Color(0xFF0B0A1F); // deep indigo, never grey
  static const _bgGlow = Color(0xFF16123A); // violet-navy
  static const _curveCool = Color(0xFF7B2FF7); // violet, at the origin
  static const _curveRed = Color(0xFFFF3D7F); // hot magenta, the curve's body
  static const _curveHot = Color(0xFFFFB020); // gold, at the plane
  static const _flewAway = Color(0xFFFF2D55); // vivid crash red
  static const _betGreen = Color(0xFF3BE8B0); // mint-cyan
  static const _cancelRed = Color(0xFFFF2D55);
  static const _cashGold = Color(0xFFFFC634);
  static const _accent = Color(0xFF22E6D3); // cyan
  static const _win = Color(0xFF3BE8B0);
  static const _textDim = Color(0xFFA9A6C9); // lavender-grey, not white70

  final CrashRepository _repo = CrashRepository();
  final SocketService _socket = SocketService();
  final AudioPlayer _sfx = AudioPlayer();
  final AudioPlayer _engine = AudioPlayer();

  late final Ticker _ticker = Ticker(_onTick);
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  /// Fires when the multiplier crosses a milestone (2x, 5x, …) — a quick swell
  /// of the multiplier text plus an expanding ring.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// Coin burst + rising payout number after a successful cash out.
  late final AnimationController _celebrate = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  int _celebrateAmount = 0;

  /// Explosion, debris and the plane spiralling away.
  late final AnimationController _crashFx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  static const _milestones = [2.0, 5.0, 10.0, 20.0, 50.0, 100.0];
  int _nextMilestone = 0;

  /// Crash points of the last few rounds, drawn behind the live curve.
  final List<double> _ghosts = [];

  /// Whoever last cleared 10x, shown as a toast for a few seconds.
  CrashBet? _bigWin;
  Timer? _bigWinTimer;

  /// Bloom post-process. Null until loaded, and stays null on devices where the
  /// shader will not compile — the painter falls back to its blur stack.
  ui.FragmentShader? _bloom;

  /// Illustrated artwork. Null until decoded; the painter keeps its procedural
  /// drawing as the fallback, so the screen works before (and without) it.
  _CrashArt? _art;

  CrashState? _state;
  int _balance = 0;
  String? _clientSeed;
  String? _notice;

  /// Local epoch-ms the current flight started at, derived from the server's
  /// `elapsedMs` so our own clock offset never matters.
  int? _flightAnchor;
  double _multiplier = 1.0;
  double _lastCrashPoint = 0;

  /// Milliseconds of flight so far — drives the propeller and the parallax,
  /// which must keep moving even when the multiplier is barely changing.
  int _elapsedMs = 0;

  final List<CrashChatMessage> _chat = [];
  bool _chatOpen = false;
  final TextEditingController _chatInput = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  CrashRain? _rain;
  bool _rainClaimed = false;

  /// One panel per bet slot, exactly like Aviator's two independent panels.
  late final List<_PanelState> _panels = [_PanelState(0), _PanelState(1)];

  Timer? _countdown;
  int _msLeft = 0;

  int? get _myId => ref.read(authStateProvider).user?.id;

  @override
  void initState() {
    super.initState();
    _balance = ref.read(authStateProvider).user?.coinsBalance ?? 0;

    _socket.on('crash_state', _onState);
    _socket.on('crash_takeoff', _onTakeoff);
    _socket.on('crash_crashed', _onCrashed);
    _socket.on('crash_bets', _onBets);
    _socket.on('crash_cashout', _onSomeoneCashedOut);
    _socket.on('crash_chat', _onChat);
    _socket.on('crash_chat_history', _onChatHistory);
    _socket.on('crash_rain', _onRain);
    _socket.on('crash_rain_claimed', _onRainClaimed);
    _socket.emit('crash_join_table', {});

    _repo.fetchState().then((snap) {
      if (!mounted) return;
      setState(() => _clientSeed = snap.clientSeed);
      if (snap.state != null) _applyState(snap.state!);
    }).catchError((_) {});

    _countdown = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _msLeft <= 0) return;
      setState(() => _msLeft = math.max(0, _msLeft - 100));
    });

    _loadBloom();
    _CrashArt.load().then((art) {
      if (mounted) setState(() => _art = art);
    }).catchError((Object e) {
      debugPrint('[crash] artwork unavailable, using procedural art: $e');
    });
  }

  /// Best-effort: a device that cannot compile the shader simply goes without
  /// bloom rather than losing the game screen.
  Future<void> _loadBloom() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/bloom.frag');
      if (!mounted) return;
      setState(() => _bloom = program.fragmentShader());
    } catch (e) {
      debugPrint('[crash] bloom shader unavailable, using blur fallback: $e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shake.dispose();
    _pulse.dispose();
    _celebrate.dispose();
    _crashFx.dispose();
    _bloom?.dispose();
    _countdown?.cancel();
    _bigWinTimer?.cancel();
    _chatInput.dispose();
    _chatScroll.dispose();
    _sfx.dispose();
    _engine.dispose();
    for (final p in _panels) {
      p.dispose();
    }
    _socket.off('crash_state');
    _socket.off('crash_takeoff');
    _socket.off('crash_crashed');
    _socket.off('crash_bets');
    _socket.off('crash_cashout');
    _socket.off('crash_chat');
    _socket.off('crash_chat_history');
    _socket.off('crash_rain');
    _socket.off('crash_rain_claimed');
    _socket.emit('crash_leave_table', {});
    super.dispose();
  }

  // ── Socket handlers ───────────────────────────────────────
  void _onState(dynamic data) {
    if (data is! Map) return;
    _applyState(CrashState.fromJson(Map<String, dynamic>.from(data)));
  }

  void _applyState(CrashState s) {
    if (!mounted) return;
    final previous = _state;
    setState(() {
      _state = s;
      _msLeft = s.msLeft;
      _rain = s.rain;
      if (previous == null || previous.roundId != s.roundId) {
        _rainClaimed = false;
        _lastCrashPoint = 0;
        _nextMilestone = 0;
        _elapsedMs = 0;
        for (final p in _panels) {
          p.resetForNewRound();
        }
      }
    });

    if (s.isFlying) {
      _flightAnchor ??= DateTime.now().millisecondsSinceEpoch - s.elapsedMs;
      if (!_ticker.isActive) _ticker.start();
      _startEngineSound();
    } else {
      _flightAnchor = null;
      if (_ticker.isActive) _ticker.stop();
      _stopEngineSound();
      if (s.isBetting) {
        setState(() => _multiplier = 1.0);
        _autoBetIfArmed();
      }
    }
  }

  void _onTakeoff(dynamic data) {
    if (data is! Map || !mounted) return;
    _flightAnchor = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _multiplier = 1.0;
      _elapsedMs = 0;
      _nextMilestone = 0;
    });
    if (!_ticker.isActive) _ticker.start();
    _startEngineSound();
  }

  void _onCrashed(dynamic data) {
    if (data is! Map || !mounted) return;
    final map = Map<String, dynamic>.from(data);
    final point = (map['crashPoint'] as num?)?.toDouble() ?? _multiplier;

    _ticker.stop();
    _flightAnchor = null;
    _stopEngineSound();
    _play('sounds/crash_whoosh.wav');
    HapticFeedback.mediumImpact();
    _shake.forward(from: 0);
    _crashFx.forward(from: 0);

    setState(() {
      _multiplier = point;
      _lastCrashPoint = point;
      // Keep the round as a ghost for the next few flights.
      _ghosts.insert(0, point);
      if (_ghosts.length > 3) _ghosts.removeLast();
    });

    // Anything of ours still pending at the crash is a loss — the stake was
    // already debited when the bet was placed.
    for (final raw in ((map['results'] as List?) ?? const []).whereType<Map>()) {
      final bet = CrashBet.fromJson(Map<String, dynamic>.from(raw));
      if (bet.userId != _myId) continue;
      final panel = _panels[bet.slot.clamp(0, _panels.length - 1)];
      setState(() {
        panel.settled = bet.status;
        panel.settledPayout = bet.payout;
        panel.settledMultiplier = bet.cashOutMultiplier;
        panel.hasBet = false;
        panel.cashedOut = bet.status == 'win';
      });
    }
  }

  void _onBets(dynamic data) {
    if (data is! Map || !mounted) return;
    final rows = (data['bets'] as List?) ?? const [];
    setState(() {
      _state = _state == null
          ? null
          : _copyWithBets(
              _state!,
              rows
                  .whereType<Map>()
                  .map((e) => CrashBet.fromJson(Map<String, dynamic>.from(e)))
                  .toList(),
            );
    });
  }

  void _onSomeoneCashedOut(dynamic data) {
    if (data is! Map || !mounted) return;

    // Anyone clearing 10x is table news, whoever they are.
    final m = (data['multiplier'] as num?)?.toDouble() ?? 1.0;
    if (m >= 10) {
      final win = CrashBet.fromJson({
        ...Map<String, dynamic>.from(data),
        'status': 'win',
        'cashOutMultiplier': m,
      });
      setState(() => _bigWin = win);
      _bigWinTimer?.cancel();
      _bigWinTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _bigWin = null);
      });
    }

    if ((data['userId'] as num?)?.toInt() != _myId) return;

    // Our own auto-cash-out fired server-side — reflect the payout locally.
    final slot = (data['slot'] as num?)?.toInt() ?? 0;
    final payout = (data['payout'] as num?)?.toInt() ?? 0;
    final panel = _panels[slot.clamp(0, _panels.length - 1)];
    if (panel.cashedOut) return; // manual cash-out already handled it

    setState(() {
      panel.cashedOut = true;
      panel.hasBet = false;
      panel.settled = 'win';
      panel.settledPayout = payout;
      panel.settledMultiplier = m;
      _balance += payout;
      _notice = 'سحبت عند ${m.toStringAsFixed(2)}x — ربحت $payout';
    });
    ref.read(authStateProvider.notifier).updateCoinsBalance(_balance);
    _play('sounds/crash_cashout.wav');
    HapticFeedback.lightImpact();
    _celebrateCashOut(payout);
  }

  void _onChat(dynamic data) {
    if (data is! Map || !mounted) return;
    setState(() {
      _chat.add(CrashChatMessage.fromJson(Map<String, dynamic>.from(data)));
      if (_chat.length > 200) _chat.removeAt(0);
    });
    _scrollChatToEnd();
  }

  void _onChatHistory(dynamic data) {
    if (data is! List || !mounted) return;
    setState(() {
      _chat
        ..clear()
        ..addAll(data
            .whereType<Map>()
            .map((e) => CrashChatMessage.fromJson(Map<String, dynamic>.from(e))));
    });
    _scrollChatToEnd();
  }

  void _onRain(dynamic data) {
    if (data is! Map || !mounted) return;
    setState(() {
      _rain = CrashRain.fromJson(Map<String, dynamic>.from(data));
      _rainClaimed = false;
    });
    _play('sounds/crash_rain.wav');
    HapticFeedback.selectionClick();
  }

  void _onRainClaimed(dynamic data) {
    if (data is! Map || !mounted || _rain == null) return;
    final left = (data['claimsLeft'] as num?)?.toInt() ?? 0;
    setState(() {
      _rain = CrashRain(
        id: _rain!.id,
        amount: _rain!.amount,
        claimsLeft: left,
        expiresAt: _rain!.expiresAt,
      );
    });
  }

  CrashState _copyWithBets(CrashState s, List<CrashBet> bets) => CrashState(
        roundId: s.roundId,
        nonce: s.nonce,
        phase: s.phase,
        serverSeedHash: s.serverSeedHash,
        serverSeed: s.serverSeed,
        crashPoint: s.crashPoint,
        msLeft: s.msLeft,
        elapsedMs: s.elapsedMs,
        minBet: s.minBet,
        maxBet: s.maxBet,
        slots: s.slots,
        bets: bets,
        history: s.history,
        rain: s.rain,
      );

  // ── Flight clock ──────────────────────────────────────────
  void _onTick(Duration _) {
    final anchor = _flightAnchor;
    if (anchor == null) return;
    final elapsed = DateTime.now().millisecondsSinceEpoch - anchor;
    final m = math.exp(_growth * math.max(0, elapsed));

    // The propeller and parallax are driven by elapsed time, so repaint every
    // frame of the flight rather than only when the multiplier moves.
    setState(() {
      _multiplier = m;
      _elapsedMs = elapsed;
    });

    while (_nextMilestone < _milestones.length && m >= _milestones[_nextMilestone]) {
      _nextMilestone++;
      _pulse.forward(from: 0);
      HapticFeedback.selectionClick();
    }
    _updateEnginePitch(m);
  }

  /// White below 2x, warming through gold, hot pink once the round is a big one.
  Color _multiplierColor(double m) {
    if (m < 2) return Colors.white;
    if (m < 10) {
      return Color.lerp(Colors.white, _cashGold, ((m - 2) / 8).clamp(0.0, 1.0))!;
    }
    return Color.lerp(_cashGold, _curveRed, ((m - 10) / 40).clamp(0.0, 1.0))!;
  }

  void _celebrateCashOut(int payout) {
    setState(() => _celebrateAmount = payout);
    _celebrate.forward(from: 0);
  }

  // ── Sound ─────────────────────────────────────────────────
  // The asset files are optional: a missing file must never break the round, so
  // every play is best-effort. See assets/sounds/README.txt.
  Future<void> _play(String asset) async {
    try {
      await _sfx.play(AssetSource(asset), volume: 0.8);
    } catch (_) {/* asset not shipped yet */}
  }

  Future<void> _startEngineSound() async {
    try {
      await _engine.setReleaseMode(ReleaseMode.loop);
      await _engine.play(AssetSource('sounds/crash_engine.wav'), volume: 0.35);
    } catch (_) {/* asset not shipped yet */}
  }

  Future<void> _stopEngineSound() async {
    try {
      await _engine.stop();
    } catch (_) {}
  }

  /// Engine pitch and volume rise with the multiplier, as in the original.
  Future<void> _updateEnginePitch(double m) async {
    try {
      await _engine.setPlaybackRate((1.0 + math.log(m) * 0.25).clamp(1.0, 2.0));
      await _engine.setVolume((0.35 + math.log(m) * 0.12).clamp(0.35, 0.9));
    } catch (_) {}
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _placeBet(_PanelState panel) async {
    final s = _state;
    if (s == null || !s.isBetting || panel.hasBet) return;

    final amount = panel.amount;
    if (amount < s.minBet || amount > s.maxBet) {
      setState(() => _notice = 'الرهان بين ${s.minBet} و ${s.maxBet}');
      return;
    }
    if (_balance < amount) {
      setState(() => _notice = 'رصيدك لا يكفي');
      return;
    }

    try {
      final result = await _repo.placeBet(
        slot: panel.slot,
        amount: amount,
        autoCashOut: panel.autoCashOutOn ? panel.autoCashOut : null,
      );
      if (!mounted) return;
      setState(() {
        panel.hasBet = true;
        panel.betAmount = amount;
        panel.settled = null;
        panel.cashedOut = false;
        _balance = result.balance;
        _notice = null;
      });
      ref.read(authStateProvider.notifier).updateCoinsBalance(_balance);
      _play('sounds/crash_bet.wav');
      HapticFeedback.selectionClick();
    } on CrashException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _cancelBet(_PanelState panel) async {
    if (!panel.hasBet) return;
    try {
      final balance = await _repo.cancelBet(panel.slot);
      if (!mounted) return;
      setState(() {
        panel.hasBet = false;
        _balance = balance;
        _notice = null;
      });
      ref.read(authStateProvider.notifier).updateCoinsBalance(_balance);
    } on CrashException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _cashOut(_PanelState panel) async {
    if (!panel.hasBet || panel.cashedOut) return;
    // Optimistically lock the button so a double tap cannot fire twice; the
    // server is the one that decides the multiplier anyway.
    setState(() => panel.cashingOut = true);
    try {
      final result = await _repo.cashOut(panel.slot);
      if (!mounted) return;
      setState(() {
        panel.cashedOut = true;
        panel.hasBet = false;
        panel.settled = 'win';
        panel.settledPayout = result.payout;
        panel.settledMultiplier = result.multiplier;
        _balance = result.balance;
        _notice = 'سحبت عند ${result.multiplier.toStringAsFixed(2)}x — ربحت ${result.payout}';
      });
      ref.read(authStateProvider.notifier).updateCoinsBalance(_balance);
      _play('sounds/crash_cashout.wav');
      HapticFeedback.lightImpact();
      _celebrateCashOut(result.payout);
    } on CrashException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => panel.cashingOut = false);
    }
  }

  /// Re-places a bet automatically at the start of each betting window.
  void _autoBetIfArmed() {
    for (final panel in _panels) {
      if (panel.autoBetOn && !panel.hasBet) {
        _placeBet(panel);
      }
    }
  }

  Future<void> _claimRain() async {
    if (_rain == null || _rainClaimed) return;
    try {
      final claim = await _repo.claimRain();
      if (!mounted) return;
      setState(() {
        _rainClaimed = true;
        _balance = claim.balance;
        _notice = 'استلمت ${claim.amount} من المطر 🌧️';
      });
      ref.read(authStateProvider.notifier).updateCoinsBalance(_balance);
    } on CrashException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _sendChat() async {
    final text = _chatInput.text.trim();
    if (text.isEmpty) return;
    _chatInput.clear();
    try {
      await _repo.sendChat(text);
    } on CrashException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: Row(children: [
            const Text('طيّار', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('🪙 $_balance',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: _openMenu,
            ),
          ],
        ),
        body: Column(children: [
          _HistoryBar(
            ticks: s?.history ?? const [],
            onTap: _openFairness,
          ),
          if (_rain != null && _rain!.claimsLeft > 0) _rainBanner(),
          Expanded(
            child: Stack(children: [
              _flightArea(),
              Positioned(top: 8, right: 8, child: _liveBetsPanel()),
              Positioned(top: 12, left: 0, right: 0, child: Center(child: _bigWinToast())),
              if (_chatOpen)
                Positioned(left: 0, top: 0, bottom: 0, width: 240, child: _chatPanel()),
              Positioned(
                right: 8,
                bottom: 8,
                child: FloatingActionButton.small(
                  heroTag: 'crash-chat',
                  backgroundColor: Colors.white.withOpacity(0.12),
                  onPressed: () => setState(() => _chatOpen = !_chatOpen),
                  child: Icon(_chatOpen ? Icons.close : Icons.chat_bubble_outline,
                      color: Colors.white),
                ),
              ),
            ]),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(_notice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
            ),
          _betPanels(),
        ]),
      ),
    );
  }

  Widget _rainBanner() => GestureDetector(
        onTap: _rainClaimed ? null : _claimRain,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: const Color(0xFF1B3A5C),
          child: Row(children: [
            Image.asset('assets/images/crash/rain_cloud.png',
                width: 34, height: 34, fit: BoxFit.contain),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _rainClaimed
                    ? 'استلمت نصيبك من المطر'
                    : 'مطر! ${_rain!.amount} عملة — باقي ${_rain!.claimsLeft}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (!_rainClaimed)
              const Text('اضغط للاستلام',
                  style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12)),
          ]),
        ),
      );

  Widget _flightArea() {
    final s = _state;
    final crashed = s?.isCrashed == true;
    final betting = s?.isBetting == true;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Short shake on the crash, decaying to nothing.
        final t = _shake.value;
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 8) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [_bgGlow, _bg],
          ),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _crashFx,
                builder: (context, _) => CustomPaint(
                  painter: _FlightPainter(
                    multiplier: _multiplier,
                    flying: s?.isFlying == true,
                    crashed: crashed,
                    betting: betting,
                    elapsedMs: betting
                        ? DateTime.now().millisecondsSinceEpoch % 100000
                        : _elapsedMs,
                    crashT: crashed ? _crashFx.value : 0,
                    ghosts: _ghosts,
                    bloom: _bloom,
                    art: _art,
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (betting) ...[
                const Text('في انتظار الجولة القادمة',
                    style: TextStyle(color: _textDim, fontSize: 14)),
                const SizedBox(height: 8),
                Text('${(_msLeft / 1000).ceil()}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(
                    value: (_msLeft / 5000).clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(_cashGold),
                  ),
                ),
              ] else ...[
                // Latin text inside an RTL subtree: without forcing LTR the
                // trailing "!" is reordered to the front ("!FLEW AWAY").
                if (crashed)
                  const Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('FLEW AWAY!',
                        style: TextStyle(
                            color: _flewAway,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                  ),
                _multiplierReadout(crashed),
              ],
            ]),
          ),
          // Cash-out celebration sits above everything, ignoring taps.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _celebrate,
                builder: (context, _) => _celebrate.isDismissed
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        painter: _CelebrationPainter(
                          t: _celebrate.value,
                          amount: _celebrateAmount,
                          art: _art,
                        ),
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// The multiplier itself: colour ramps with the value, and each milestone
  /// swells the text and throws off an expanding ring.
  Widget _multiplierReadout(bool crashed) {
    final color = crashed ? _flewAway : _multiplierColor(_multiplier);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        // One swell that settles back, not a bounce.
        final scale = 1.0 + math.sin(t * math.pi) * 0.18;

        return SizedBox(
          height: 96,
          child: Stack(alignment: Alignment.center, children: [
            if (t > 0 && t < 1)
              Container(
                width: 120 + t * 190,
                height: 120 + t * 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity((1 - t) * 0.55),
                    width: 2.5,
                  ),
                ),
              ),
            Transform.scale(
              scale: crashed ? 1.0 : scale,
              child: Text(
                '${_multiplier.toStringAsFixed(2)}x',
                style: TextStyle(
                  color: color,
                  fontSize: _multiplier >= 10 ? 64 : (_multiplier >= 2 ? 58 : 52),
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: color.withOpacity(0.55), blurRadius: 22),
                  ],
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _liveBetsPanel() {
    final bets = _state?.bets ?? const <CrashBet>[];

    // An empty feed used to sit there as a large blank box covering a third of
    // the flight area. Collapse to a single chip until there is something to
    // show, and size the panel to its contents rather than a fixed height.
    if (bets.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Text('لا رهانات بعد',
            style: TextStyle(color: _textDim, fontSize: 10)),
      );
    }

    return Container(
      width: 150,
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الرهانات المباشرة (${bets.length})',
              style: const TextStyle(color: _textDim, fontSize: 11)),
          const Divider(color: Colors.white12, height: 10),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: bets.length,
              itemBuilder: (context, i) => _liveBetRow(bets[i]),
            ),
          ),
        ],
      ),
    );
  }

  /// One row of the live feed. Winners keep a green tint and a highlighted
  /// backing so a successful cash-out is visible in peripheral vision; losers
  /// dim out of the way.
  Widget _liveBetRow(CrashBet b) {
    final color = b.isWin
        ? _win
        : (b.isLoss ? Colors.white24 : Colors.white70);

    final row = Container(
      key: ValueKey(b.betId),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: b.isWin ? _win.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: b.isWin
            ? Border.all(color: _win.withOpacity(0.35))
            : null,
      ),
      child: Row(children: [
        _avatar(b),
        const SizedBox(width: 5),
        Expanded(
          child: Text(b.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 10)),
        ),
        Text(
          b.isWin ? '${b.cashOutMultiplier!.toStringAsFixed(2)}x' : '${b.amount}',
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: b.isWin ? FontWeight.bold : null),
        ),
      ]),
    );

    // Rows slide in as bets land, rather than blinking into existence.
    return TweenAnimationBuilder<double>(
      key: ValueKey(b.betId),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset((1 - v) * 18, 0), child: child),
      ),
      child: row,
    );
  }

  Widget _avatar(CrashBet b) {
    final url = b.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: 8, backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      radius: 8,
      backgroundColor: Colors.white.withOpacity(0.14),
      child: Text(
        b.name.isEmpty ? '?' : b.name.characters.first,
        style: const TextStyle(fontSize: 8, color: Colors.white70),
      ),
    );
  }

  /// Slides in when anyone clears 10x — the moment the whole table reacts to.
  Widget _bigWinToast() {
    final win = _bigWin;
    if (win == null) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      key: ValueKey(win.betId),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - v) * -22), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB8860B), Color(0xFFE91E63)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: const Color(0xFFE91E63).withOpacity(0.5), blurRadius: 16),
          ],
        ),
        child: Text(
          '🏆 ${win.name} — ${win.cashOutMultiplier!.toStringAsFixed(2)}x',
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _chatPanel() => Container(
        color: Colors.black.withOpacity(0.55),
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          const Text('الدردشة', style: TextStyle(color: _textDim, fontSize: 12)),
          const Divider(color: Colors.white12, height: 10),
          Expanded(
            child: ListView.builder(
              controller: _chatScroll,
              itemCount: _chat.length,
              itemBuilder: (context, i) {
                final m = _chat[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: '${m.name}: ',
                        style: const TextStyle(
                            color: _cashGold, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: m.text,
                        style: const TextStyle(color: _textDim, fontSize: 11),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _chatInput,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                onSubmitted: (_) => _sendChat(),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'اكتب رسالة…',
                  hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.white70, size: 18),
              onPressed: _sendChat,
            ),
          ]),
        ]),
      );

  Widget _betPanels() => Container(
        color: Colors.black.withOpacity(0.3),
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _panels
              .map((p) => Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _betPanel(p),
                  )))
              .toList(),
        ),
      );

  Widget _betPanel(_PanelState panel) {
    final s = _state;
    final betting = s?.isBetting == true;
    final flying = s?.isFlying == true;
    final canCashOut = flying && panel.hasBet && !panel.cashedOut;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Amount + quick steps
        Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, color: Colors.white54, size: 18),
            onPressed: betting ? () => setState(() => panel.nudge(-100, s!.minBet, s.maxBet)) : null,
          ),
          Expanded(
            child: Text('${panel.amount}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, color: Colors.white54, size: 18),
            onPressed: betting ? () => setState(() => panel.nudge(100, s!.minBet, s.maxBet)) : null,
          ),
        ]),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            for (final step in const [100, 500, 1000, 5000])
              _chip('+$step',
                  onTap: betting ? () => setState(() => panel.nudge(step, s!.minBet, s.maxBet)) : null),
            _chip('½',
                onTap: betting
                    ? () => setState(() => panel.setAmount(_balance ~/ 2, s!.minBet, s.maxBet))
                    : null),
            _chip('الكل',
                onTap: betting
                    ? () => setState(() => panel.setAmount(_balance, s!.minBet, s.maxBet))
                    : null),
          ],
        ),
        const SizedBox(height: 6),
        // Auto bet / auto cash out
        Row(children: [
          Expanded(
            child: _toggleRow('تلقائي', panel.autoBetOn,
                (v) => setState(() => panel.autoBetOn = v)),
          ),
        ]),
        Row(children: [
          Expanded(
            child: _toggleRow('سحب عند', panel.autoCashOutOn,
                (v) => setState(() => panel.autoCashOutOn = v)),
          ),
          // Numbers stay LTR and the box is wide enough for "2.00x" — at 56px
          // with a suffix it clipped to "x2.0(".
          SizedBox(
            width: 62,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: panel.autoController,
                enabled: panel.autoCashOutOn,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  suffixText: 'x',
                  suffixStyle: TextStyle(color: _textDim, fontSize: 11),
                ),
                onChanged: (v) =>
                    panel.autoCashOut = double.tryParse(v) ?? panel.autoCashOut,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // The one action button, switching identity with the round phase.
        SizedBox(
          width: double.infinity,
          height: 48,
          child: canCashOut
              ? ElevatedButton(
                  onPressed: panel.cashingOut ? null : () => _cashOut(panel),
                  style: ElevatedButton.styleFrom(backgroundColor: _cashGold),
                  child: Text(
                    'CASH OUT\n${(panel.betAmount * _multiplier).floor()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                )
              : panel.hasBet
                  ? ElevatedButton(
                      onPressed: betting ? () => _cancelBet(panel) : null,
                      style: ElevatedButton.styleFrom(backgroundColor: _cancelRed),
                      child: const Text('CANCEL',
                          style:
                              TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  : ElevatedButton(
                      onPressed: betting ? () => _placeBet(panel) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _betGreen,
                        disabledBackgroundColor: Colors.white12,
                      ),
                      child: const Text('BET',
                          style:
                              TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
        ),
        if (panel.settled != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              panel.settled == 'win'
                  ? 'ربحت ${panel.settledPayout} عند ${panel.settledMultiplier?.toStringAsFixed(2)}x'
                  : 'خسرت ${panel.betAmount}',
              style: TextStyle(
                color: panel.settled == 'win' ? _win : Colors.white38,
                fontSize: 11,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _chip(String label, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(onTap == null ? 0.03 : 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: onTap == null ? Colors.white24 : Colors.white70, fontSize: 10)),
        ),
      );

  /// The RTL subtree mirrors a Switch, so an OFF toggle put its knob on the
  /// right and read as ON. Forcing the control itself to LTR restores the
  /// universal "knob left = off, knob right = on", and the track colour makes
  /// the state unambiguous either way.
  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(children: [
        // Transform.scale only scales the paint — the Switch still claimed its
        // full ~60px of layout width, which is what squeezed the label into an
        // ellipsis. FittedBox actually shrinks the box, freeing that space.
        SizedBox(
          width: 34,
          height: 26,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeColor: Colors.white,
                activeTrackColor: _betGreen,
                inactiveThumbColor: Colors.white70,
                inactiveTrackColor: Colors.white24,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: value ? _betGreen : _textDim,
                  fontSize: 10,
                  fontWeight: value ? FontWeight.bold : null)),
        ),
      ]);

  // ── Menu sheets ───────────────────────────────────────────
  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.rule, color: Colors.white70),
            title: const Text('القواعد', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openRules();
            },
          ),
          ListTile(
            leading: const Icon(Icons.verified_user, color: Colors.white70),
            title: const Text('إثبات العدالة', style: TextStyle(color: Colors.white)),
            subtitle: Text('بذرتك: ${_clientSeed ?? '—'}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              _openSeedEditor();
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart, color: Colors.white70),
            title: const Text('إحصائياتي', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openStats();
            },
          ),
        ]),
      ),
    );
  }

  void _openRules() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgGlow,
        title: const Text('القواعد', style: TextStyle(color: Colors.white)),
        content: const Text(
          'ضع رهانك قبل الإقلاع على لوحة واحدة أو اثنتين. بعد الإقلاع يبدأ المضاعف من '
          '1.00x ويزداد. اضغط CASH OUT قبل أن تطير الطائرة لتقبض رهانك مضروبًا في '
          'المضاعف الحالي. إذا طارت قبل أن تسحب، تخسر رهانك.\n\n'
          'كل جولة مستقلة، ونقطة التحطم محسوبة من بذرة خادم يُنشر تجزئتها قبل الجولة '
          'وتُكشف بعدها، فيمكنك التحقق منها بنفسك.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('تمام')),
        ],
      ),
    );
  }

  void _openSeedEditor() {
    final controller = TextEditingController(text: _clientSeed ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgGlow,
        title: const Text('بذرة العميل', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'بذرتك تدخل في حساب نقطة التحطم مع بذرة الخادم والعداد. غيّرها متى شئت — '
            'تُستخدم من الجولة التالية.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              try {
                final seed = await _repo.setClientSeed(controller.text.trim());
                if (mounted) setState(() => _clientSeed = seed);
              } on CrashException catch (e) {
                if (mounted) setState(() => _notice = e.message);
              }
              navigator.pop();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _openStats() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      builder: (_) => FutureBuilder<CrashStats>(
        future: _repo.fetchStats(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final st = snap.data!;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('إحصائياتي',
                    style: TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _statRow('جولات', '${st.rounds}'),
                _statRow('رهنت', '${st.wagered}'),
                _statRow('ربحت', '${st.won}'),
                _statRow('الصافي', '${st.net}'),
                _statRow('فوز / خسارة', '${st.wins} / ${st.losses}'),
                _statRow('أعلى مضاعف', '${st.bestMultiplier.toStringAsFixed(2)}x'),
                _statRow('أعلى ربح', '${st.bestPayout}'),
                _statRow('متوسط مضاعف الجولات',
                    '${st.averageRoundMultiplier.toStringAsFixed(2)}x'),
                const Divider(color: Colors.white12),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    itemCount: st.bets.length,
                    itemBuilder: (context, i) {
                      final b = st.bets[i];
                      final win = b.status == 'win';
                      return ListTile(
                        dense: true,
                        title: Text('${b.amount}',
                            style: const TextStyle(color: _textDim, fontSize: 12)),
                        trailing: Text(
                          win ? '+${b.payout} (${b.cashOutMultiplier?.toStringAsFixed(2)}x)' : '-${b.amount}',
                          style: TextStyle(
                              color: win ? _win : Colors.white30,
                              fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
      );

  /// Tapping any multiplier in the history bar opens its verification detail.
  void _openFairness(int roundId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgGlow,
        title: const Text('إثبات العدالة', style: TextStyle(color: Colors.white)),
        content: FutureBuilder<CrashFairness>(
          future: _repo.fetchFairness(roundId),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text('تعذر تحميل تفاصيل الجولة',
                  style: TextStyle(color: Colors.white54, fontSize: 12));
            }
            if (!snap.hasData) {
              return const SizedBox(
                  height: 80, child: Center(child: CircularProgressIndicator()));
            }
            final f = snap.data!;
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _fairRow('الجولة', '#${f.roundId}'),
                _fairRow('العداد (nonce)', '${f.nonce}'),
                _fairRow('نقطة التحطم', '${f.crashPoint.toStringAsFixed(2)}x'),
                _fairRow('تجزئة البذرة (منشورة قبل الجولة)', f.serverSeedHash),
                _fairRow('بذرة الخادم (مكشوفة)', f.serverSeed),
                _fairRow('بذور اللاعبين', f.clientSeeds.join(', ')),
                _fairRow('التجزئة النهائية', f.hash),
                const SizedBox(height: 8),
                Text(
                  f.verified
                      ? '✅ أعاد الخادم الحساب من البذور فطابقت النتيجة'
                      : '⚠️ لم تتطابق النتيجة',
                  style: TextStyle(
                      color: f.verified ? _win : Colors.orangeAccent,
                      fontSize: 12),
                ),
              ]),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _fairRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          SelectableText(value,
              style: const TextStyle(color: _textDim, fontSize: 11)),
        ]),
      );
}

/// Per-slot bet panel state. Two of these give Aviator's twin panels.
class _PanelState {
  _PanelState(this.slot);

  final int slot;
  int amount = 1000;
  int betAmount = 0;
  bool hasBet = false;
  bool cashedOut = false;
  bool cashingOut = false;
  bool autoBetOn = false;
  bool autoCashOutOn = false;
  double autoCashOut = 2.0;
  String? settled; // win | loss, for the round just ended
  int settledPayout = 0;
  double? settledMultiplier;

  final TextEditingController autoController = TextEditingController(text: '2.00');

  void nudge(int delta, int min, int max) => setAmount(amount + delta, min, max);

  void setAmount(int value, int min, int max) => amount = value.clamp(min, max);

  void resetForNewRound() {
    hasBet = false;
    cashedOut = false;
    cashingOut = false;
    settled = null;
    settledPayout = 0;
    settledMultiplier = null;
  }

  void dispose() => autoController.dispose();
}

/// Everything inside the flight box: sky, clouds, parallax stars, ghost curves
/// of past rounds, the live flight curve, the plane, the crash, and the runway
/// staging during the betting phase.
///
/// Bloom is applied as a post-process — the glowable art is rendered once into a
/// half-resolution texture, run through shaders/bloom.frag and composited back
/// additively. If the shader is unavailable the layered-blur fallback still
/// produces a decent glow, so the game never depends on it.
class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.multiplier,
    required this.flying,
    required this.crashed,
    required this.betting,
    required this.elapsedMs,
    required this.crashT,
    required this.ghosts,
    required this.bloom,
    required this.art,
  });

  final double multiplier;
  final bool flying;
  final bool crashed;
  final bool betting;

  /// Milliseconds since take-off — drives the propeller spin and the parallax,
  /// which must keep moving even while the multiplier barely changes.
  final int elapsedMs;

  /// 0→1 over the crash animation; 0 when there is no crash on screen.
  final double crashT;

  /// Crash points of the last few rounds, newest first, drawn as faint replays.
  final List<double> ghosts;

  final ui.FragmentShader? bloom;

  /// Illustrated artwork; null until decoded, in which case everything below
  /// falls back to the procedural drawing.
  final _CrashArt? art;

  static const _curveRed = _CrashGameScreenState._curveRed;
  static const _curveCool = _CrashGameScreenState._curveCool;
  static const _curveHot = _CrashGameScreenState._curveHot;
  static const _flewAway = _CrashGameScreenState._flewAway;

  /// Three depth layers: the far ones barely drift, the near ones streak past.
  /// That difference is what reads as speed.
  static final List<List<Offset>> _starLayers = List.generate(3, (layer) {
    final r = math.Random(7919 * (layer + 1));
    return List.generate(
      [34, 22, 14][layer],
      (_) => Offset(r.nextDouble(), r.nextDouble()),
    );
  });

  static const _layerDepth = [0.10, 0.30, 0.75];
  static const _layerAlpha = [0.10, 0.16, 0.26];
  static const _layerRadius = [0.9, 1.3, 1.9];

  /// Cloud decks: x, y, scale, depth. Depth drives both parallax speed and size.
  static final List<List<double>> _clouds = List.generate(9, (i) {
    final r = math.Random(31337 + i * 977);
    return [
      r.nextDouble(),
      0.15 + r.nextDouble() * 0.75,
      0.6 + r.nextDouble() * 0.9,
      0.25 + r.nextDouble() * 0.9,
    ];
  });

  static final List<double> _debris =
      List.generate(22, (i) => math.Random(i * 5711).nextDouble());

  /// How far up the canvas the flight has climbed, 0..1 (log-scaled so a 100x
  /// round still fits, just flatter).
  double get _progress =>
      (math.log(math.max(1, multiplier)) / math.log(10)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final p = _progress;

    // Background layers are never bloomed.
    _paintSky(canvas, size, p);
    _paintGrid(canvas, size, p);
    _paintStars(canvas, size, p);
    _paintClouds(canvas, size, p);

    if (betting) {
      _paintRunway(canvas, size);
      return;
    }
    if (!flying && !crashed) return;

    final geo = _geometry(size, p);

    // Ghost replays sit under everything and are deliberately not bloomed —
    // they should read as history, not as light.
    _paintGhosts(canvas, size);
    _paintUnderFill(canvas, size, geo);

    final art = _recordArt(geo, p);
    canvas.save();
    _applyCamera(canvas, geo, p);
    canvas.drawPicture(art);
    canvas.restore();

    _compositeBloom(canvas, size, art, p);

    if (crashT > 0) _paintCrashFx(canvas, size, geo);
  }

  // ── Geometry ──────────────────────────────────────────────
  _FlightGeometry _geometry(Size size, double p) {
    final origin = Offset(size.width * 0.06, size.height * 0.92);
    final tip = Offset(
      size.width * (0.12 + 0.78 * p),
      size.height * (0.9 - 0.75 * p),
    );
    // Control point pulled along the baseline so the curve leaves the ground
    // flat and steepens as it climbs.
    final control = Offset(origin.dx + (tip.dx - origin.dx) * 0.65, origin.dy);
    return _FlightGeometry(origin, control, tip);
  }

  Path _pathFor(_FlightGeometry g) => Path()
    ..moveTo(g.origin.dx, g.origin.dy)
    ..quadraticBezierTo(g.control.dx, g.control.dy, g.tip.dx, g.tip.dy);

  // ── Sky ───────────────────────────────────────────────────
  /// The sky climbs with the plane: night at ground level, a dawn band through
  /// the low multipliers, deep stratosphere blue, then black space with an
  /// aurora once the round is genuinely big.
  void _paintSky(Canvas canvas, Size size, double p) {
    final rect = Offset.zero & size;

    final a = art;
    if (a != null) {
      // Two layers crossfaded: low -> mid across the first half of the climb,
      // mid -> high across the second.
      final ui.Image under;
      final ui.Image over;
      final double blend;
      if (p < 0.5) {
        under = a.skyLow;
        over = a.skyMid;
        blend = (p / 0.5).clamp(0.0, 1.0);
      } else {
        under = a.skyMid;
        over = a.skyHigh;
        blend = ((p - 0.5) / 0.5).clamp(0.0, 1.0);
      }
      _drawCover(canvas, under, rect, 1.0);
      if (blend > 0.01) _drawCover(canvas, over, rect, blend);
      return;
    }


    const night = Color(0xFF16123A); // violet-navy
    const dawn = Color(0xFF3D1B4F); // violet with a warm cast
    const strato = Color(0xFF141A4A); // deep blue-violet
    const space = Color(0xFF0B0A1F); // near-black indigo

    Color top;
    Color bottom;
    if (p < 0.34) {
      final t = p / 0.34;
      top = Color.lerp(night, dawn, t)!;
      bottom = Color.lerp(const Color(0xFF2A2350), const Color(0xFFFF6B35), t)!;
    } else if (p < 0.68) {
      final t = (p - 0.34) / 0.34;
      top = Color.lerp(dawn, strato, t)!;
      bottom = Color.lerp(const Color(0xFFFF6B35), const Color(0xFF7B2FF7), t)!;
    } else {
      final t = (p - 0.68) / 0.32;
      top = Color.lerp(strato, space, t)!;
      bottom = Color.lerp(const Color(0xFF7B2FF7), const Color(0xFF16123A), t)!;
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );

    // Aurora only in the upper reaches — a reward for a big round.
    if (p > 0.72) {
      final strength = ((p - 0.72) / 0.28).clamp(0.0, 1.0);
      final wave = elapsedMs / 1400.0;
      const auroraColors = [
        Color(0xFF3BE8B0),
        Color(0xFF6C7BFF),
        Color(0xFFB86CFF),
      ];

      for (var i = 0; i < 3; i++) {
        final y = size.height * (0.16 + i * 0.09) + math.sin(wave + i) * 12;
        final path = Path()..moveTo(0, y);
        for (double x = 0; x <= size.width; x += 24) {
          path.lineTo(x, y + math.sin(wave * 1.3 + x / 90 + i) * 16);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = auroraColors[i].withOpacity(0.16 * strength)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 22
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
        );
      }
    }
  }

  /// Faint axis grid that scrolls with the climb — the strongest single cue
  /// that the plane is actually gaining altitude rather than the curve growing.
  void _paintGrid(Canvas canvas, Size size, double p) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..strokeWidth = 1;

    const spacing = 64.0;
    final shiftX = (p * size.width * 0.9) % spacing;
    final shiftY = (p * size.height * 0.8) % spacing;

    for (double x = -shiftX; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = size.height + shiftY; y > 0; y -= spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintStars(Canvas canvas, Size size, double p) {
    // Stars fade in as the sky darkens with altitude.
    final visibility = (0.35 + p * 0.65).clamp(0.0, 1.0);

    for (var layer = 0; layer < _starLayers.length; layer++) {
      final depth = _layerDepth[layer];
      final paint = Paint()
        ..color = Colors.white.withOpacity(_layerAlpha[layer] * visibility);
      final radius = _layerRadius[layer];

      final dx = (p * depth * 1.4) % 1.0;
      final dy = (p * depth * 1.0) % 1.0;

      for (final s in _starLayers[layer]) {
        final x = ((s.dx - dx) % 1.0) * size.width;
        final y = ((s.dy + dy) % 1.0) * size.height;
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  /// Soft cloud decks drifting past at their own depths. They thin out with
  /// altitude — above the weather there should be nothing left.
  void _paintClouds(Canvas canvas, Size size, double p) {
    final density = (1.0 - p * 1.25).clamp(0.0, 1.0);
    if (density <= 0.01) return;

    final a = art;
    if (a != null) {
      final src = _CrashArt.cloudsSrc;

      // Three decks, far to near. Each draws the full strip twice, offset by one
      // strip width, so it wraps without a seam.
      const decks = [
        [0.30, 0.62, 0.26], // depth, scale, opacity
        [0.60, 0.95, 0.40],
        [1.00, 1.45, 0.55],
      ];

      for (final deck in decks) {
        final depth = deck[0];
        final w = size.width * deck[1] * 1.6;
        final h = w * src.height / src.width;
        final opacity = (deck[2] * density).clamp(0.0, 1.0);
        if (opacity <= 0.01) continue;

        final paint = Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withOpacity(opacity);

        // Scroll left and settle downward as the plane climbs past the deck.
        final shift = (p * depth * size.width * 2.2) % w;
        final y = size.height * (0.30 + depth * 0.30) + p * depth * size.height * 0.75;
        if (y - h > size.height) continue;

        for (var tile = -1; tile <= 1; tile++) {
          canvas.drawImageRect(
            a.clouds,
            src,
            Rect.fromLTWH(-shift + tile * w, y - h / 2, w, h),
            paint,
          );
        }
      }
      return;
    }

    for (final c in _clouds) {
      final depth = c[3];
      final scale = c[2] * (0.35 + depth * 0.45);
      final drift = (c[0] - p * depth * 1.6) % 1.2 - 0.1;
      final x = drift * size.width;
      final y = c[1] * size.height + p * depth * size.height * 0.5;
      if (y > size.height * 1.1) continue;

      final opacity = (0.045 * density * (0.5 + depth * 0.6)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * scale);

      // A few overlapping lobes read as a cloud; one ellipse reads as a smudge.
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x, y), width: 96 * scale, height: 30 * scale),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x - 22 * scale, y + 4 * scale),
            width: 60 * scale,
            height: 23 * scale),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x + 26 * scale, y + 3 * scale),
            width: 52 * scale,
            height: 20 * scale),
        paint,
      );
    }
  }

  // ── Runway (betting phase) ────────────────────────────────
  /// Staging before take-off: a lit runway with chasing edge lights, ground fog
  /// and the plane idling with its propeller ticking over.
  void _paintRunway(Canvas canvas, Size size) {
    final y = size.height * 0.92;

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = Colors.white.withOpacity(0.20)
        ..strokeWidth = 2,
    );

    for (double x = 10; x < size.width; x += 46) {
      canvas.drawLine(
        Offset(x, y + 7),
        Offset(x + 22, y + 7),
        Paint()
          ..color = Colors.white.withOpacity(0.10)
          ..strokeWidth = 2,
      );
    }

    // Edge lights chase toward the take-off end.
    final chase = (elapsedMs / 90).floor();
    for (var i = 0; i < 12; i++) {
      final x = size.width * (0.04 + i * 0.08);
      final lit = (chase - i) % 12 < 3;
      canvas.drawCircle(
        Offset(x, y - 6),
        lit ? 3.4 : 2.0,
        Paint()
          ..color = (lit ? _CrashGameScreenState._cashGold : Colors.white24)
              .withOpacity(lit ? 0.95 : 0.4)
          ..maskFilter = lit ? const MaskFilter.blur(BlurStyle.normal, 4) : null,
      );
    }

    final fogRect = Rect.fromLTWH(0, y - 26, size.width, 42);
    canvas.drawRect(
      fogRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white.withOpacity(0.07)],
        ).createShader(fogRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // The plane waits on the mark, nose down the runway.
    canvas.save();
    canvas.translate(size.width * 0.12, y - 10);
    _paintPlaneBody(canvas, idle: true);
    canvas.restore();
  }

  // ── Ghost curves ──────────────────────────────────────────
  /// Faint replays of recent rounds, so the player can see at a glance whether
  /// this round is running long or short.
  void _paintGhosts(Canvas canvas, Size size) {
    final count = math.min(3, ghosts.length);
    for (var i = 0; i < count; i++) {
      final gp =
          (math.log(math.max(1, ghosts[i])) / math.log(10)).clamp(0.0, 1.0);
      canvas.drawPath(
        _pathFor(_geometry(size, gp)),
        Paint()
          ..color = Colors.white.withOpacity(0.09 - i * 0.025)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  void _paintUnderFill(Canvas canvas, Size size, _FlightGeometry g) {
    canvas.drawPath(
      Path.from(_pathFor(g))
        ..lineTo(g.tip.dx, g.origin.dy)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _curveRed.withOpacity(0.45),
            _curveCool.withOpacity(0.18),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
  }

  // ── Camera ────────────────────────────────────────────────
  /// A slow push-in that tracks the plane, so the frame feels handheld rather
  /// than static. Kept subtle — it should be felt, not noticed.
  void _applyCamera(Canvas canvas, _FlightGeometry g, double p) {
    final zoom = 1.0 + p * 0.06;
    final sway = math.sin(elapsedMs / 1600.0) * 3.0 * p;

    canvas.translate(g.tip.dx, g.tip.dy);
    canvas.scale(zoom);
    canvas.translate(-g.tip.dx + sway, -g.tip.dy - sway * 0.5);
  }

  // ── Glowable art ──────────────────────────────────────────
  ui.Picture _recordArt(_FlightGeometry g, double p) {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);

    _paintCometCurve(c, g, p);
    if (!crashed) {
      _paintTrail(c, g, p);
      _paintPlane(c, g);
    }
    return recorder.endRecording();
  }

  /// The curve is drawn as a gradient along its own length — cool and dim where
  /// the flight started, white-hot at the plane — with a comet glow at the tip.
  /// Chromatic aberration separates as the multiplier climbs.
  void _paintCometCurve(Canvas canvas, _FlightGeometry g, double p) {
    final path = _pathFor(g);
    final base = crashed ? _flewAway : _curveRed;
    final cool = crashed ? _flewAway.withOpacity(0.35) : _curveCool;
    final hot = crashed ? Colors.white : _curveHot;

    // Violet where the flight began, magenta through the body, gold at the
    // plane — the curve itself carries the heat rather than being one flat red.
    final gradient = ui.Gradient.linear(
      g.origin,
      g.tip,
      [cool.withOpacity(0.30), base, hot],
      const [0.0, 0.55, 1.0],
    );

    void gradientPass(double width, double blur, double opacity) {
      canvas.drawPath(
        path,
        Paint()
          ..shader = gradient
          ..color = Colors.white.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..maskFilter =
              blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
      );
    }

    void flatPass(Color color, double width, double opacity) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    // Chromatic split — the red and blue fringes separate with speed.
    final split = math.max(0.0, p - 0.45) * 1.6;
    if (split > 0.25) {
      canvas.save();
      canvas.translate(-split, 0);
      flatPass(const Color(0xFFFF2D55), 2, 0.22);
      canvas.restore();
      canvas.save();
      canvas.translate(split, 0);
      flatPass(const Color(0xFF2D7BFF), 2, 0.22);
      canvas.restore();
    }

    gradientPass(16, 18, 0.28); // outer haze
    gradientPass(8, 7, 0.55); // mid glow
    gradientPass(3, 0, 1.0); // hot core

    // Comet head.
    canvas.drawCircle(
      g.tip,
      10 + p * 10,
      Paint()
        ..color = hot.withOpacity(0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + p * 12),
    );
  }

  /// Puffs sampled back along the curve, spreading and fading with age. Derived
  /// from the curve itself rather than a particle list, so there is no state to
  /// keep in sync and nothing to allocate per frame.
  void _paintTrail(Canvas canvas, _FlightGeometry g, double p) {
    const puffs = 16;
    final drift = elapsedMs / 900.0;

    for (var i = 1; i <= puffs; i++) {
      final age = i / puffs;
      final t = (1.0 - age * 0.34).clamp(0.0, 1.0);
      final at = _quadAt(g.origin, g.control, g.tip, t);

      final wobble = math.sin(drift + i * 1.7) * age * 7;
      final radius = 2.0 + age * 9.0;
      final opacity = ((1.0 - age) * 0.16 * (0.35 + p)).clamp(0.0, 1.0);

      canvas.drawCircle(
        Offset(at.dx - age * 10, at.dy + age * 5 + wobble),
        radius,
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  /// Draws [image] to fill [dst] without distorting it — the source is centre
  /// cropped to the destination's aspect ratio, like BoxFit.cover.
  void _drawCover(Canvas canvas, ui.Image image, Rect dst, double opacity) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = math.max(dst.width / iw, dst.height / ih);
    final cw = dst.width / scale;
    final ch = dst.height / scale;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH((iw - cw) / 2, (ih - ch) / 2, cw, ch),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withOpacity(opacity.clamp(0.0, 1.0)),
    );
  }

  static Offset _quadAt(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  // ── Plane ─────────────────────────────────────────────────
  /// Banks to the curve's real tangent (the derivative of a quadratic bezier at
  /// t=1 is 2*(p2-p1)), so the nose always points where the plane is going.
  void _paintPlane(Canvas canvas, _FlightGeometry g) {
    canvas.save();
    canvas.translate(g.tip.dx, g.tip.dy);
    canvas.rotate(_planeAngle(g));
    _paintPlaneBody(canvas);
    canvas.restore();
  }

  /// Pitch of the plane sprite.
  ///
  /// The exact bezier tangent at t=1 is `tip - control`, but early in a round
  /// that endpoint derivative is near-vertical even though the drawn curve is
  /// still shallow — which stood the plane on its tail. Using the chord over
  /// the last quarter of the curve gives the heading the player actually sees,
  /// and the clamp keeps it from ever exceeding a believable climb angle.
  double _planeAngle(_FlightGeometry g) {
    final back = _quadAt(g.origin, g.control, g.tip, 0.75);
    final dir = g.tip - back;
    if (dir.distance < 0.5) return 0;

    const maxClimb = -0.72; // ~41 degrees nose-up
    return math.atan2(dir.dy, dir.dx).clamp(maxClimb, 0.35);
  }

  void _paintPlaneBody(Canvas canvas, {bool idle = false}) {
    final a = art;
    if (a != null) {
      const width = 74.0;
      final src = _CrashArt.planeSrc;
      final height = width * src.height / src.width;
      final paint = Paint()..filterQuality = FilterQuality.medium;

      canvas.drawImageRect(
        a.plane,
        src,
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        paint,
      );

      // The illustrated propeller spins on the nose. The sprite already has a
      // faint blur baked in, so this sits lightly on top rather than replacing
      // it.
      final pSrc = _CrashArt.propellerSrc;
      final pw = width * 0.30;
      final ph = pw * pSrc.height / pSrc.width;
      canvas.save();
      canvas.translate(width * 0.46, -height * 0.04);
      canvas.rotate(elapsedMs / (idle ? 260.0 : 30.0));
      canvas.drawImageRect(
        a.propeller,
        pSrc,
        Rect.fromCenter(center: Offset.zero, width: pw, height: ph),
        paint..color = Colors.white.withOpacity(idle ? 0.95 : 0.55),
      );
      canvas.restore();
      return;
    }

    const red = Color(0xFFE53935);
    const dark = Color(0xFF8E1B1B);
    final body = Paint()..color = red;

    canvas.drawPath(
      Path()
        ..moveTo(16, 0)
        ..quadraticBezierTo(6, -5, -10, -4)
        ..lineTo(-13, 0)
        ..lineTo(-10, 4)
        ..quadraticBezierTo(6, 5, 16, 0)
        ..close(),
      body,
    );
    canvas.drawPath(
      Path()
        ..moveTo(2, 0)
        ..lineTo(-6, -11)
        ..lineTo(-1, -11)
        ..lineTo(6, 0)
        ..close(),
      Paint()..color = dark,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-9, 0)
        ..lineTo(-14, -7)
        ..lineTo(-10, -7)
        ..lineTo(-6, 0)
        ..close(),
      Paint()..color = dark,
    );
    canvas.drawCircle(const Offset(4, -2), 1.8, Paint()..color = Colors.white70);
    _paintPropeller(canvas, idle: idle);
  }

  /// A spinning disc: two blurred blades plus a faint swept circle. In flight
  /// the blades turn fast enough to blur into the disc; idling on the runway
  /// they tick over slowly and stay sharp.
  void _paintPropeller(Canvas canvas, {bool idle = false}) {
    final spin = elapsedMs / (idle ? 140.0 : 22.0);
    canvas.save();
    canvas.translate(17, 0);

    canvas.drawCircle(
      Offset.zero,
      9,
      Paint()
        ..color = Colors.white.withOpacity(idle ? 0.05 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    final blade = Paint()
      ..color = Colors.white.withOpacity(idle ? 0.6 : 0.45)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..maskFilter = idle ? null : const MaskFilter.blur(BlurStyle.normal, 1.2);

    for (var i = 0; i < 2; i++) {
      final a = spin + i * math.pi;
      final d = Offset(math.cos(a) * (idle ? 8 : 1.6), math.sin(a) * 9);
      canvas.drawLine(-d, d, blade);
    }
    canvas.restore();
  }

  // ── Bloom ─────────────────────────────────────────────────
  /// Renders the glowable art to a half-res texture, runs the bloom shader over
  /// it and composites additively. Skipped when the shader could not be loaded
  /// — the layered blur passes already look reasonable on their own.
  void _compositeBloom(Canvas canvas, Size size, ui.Picture art, double p) {
    final shader = bloom;
    if (shader == null) return;

    const scale = 0.5;
    final w = (size.width * scale).round();
    final h = (size.height * scale).round();
    if (w < 2 || h < 2) return;

    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(scale)
      ..drawPicture(art);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);

    try {
      shader
        ..setFloat(0, w.toDouble())
        ..setFloat(1, h.toDouble())
        ..setFloat(2, 0.40 + p * 0.30) // intensity grows with the round
        ..setFloat(3, 0.62) // luminance threshold — only real highlights bloom
        ..setFloat(4, 3.0) // blur radius, in texels
        ..setImageSampler(0, image);

      canvas.save();
      canvas.scale(1 / scale);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.plus,
      );
      canvas.restore();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  // ── Crash ─────────────────────────────────────────────────
  /// Fireball, debris, smoke and a red vignette; the plane spirals away out of
  /// frame rather than simply vanishing.
  void _paintCrashFx(Canvas canvas, Size size, _FlightGeometry g) {
    final t = crashT.clamp(0.0, 1.0);
    final at = g.tip;
    final rect = Offset.zero & size;

    // Vignette flash centred on the blast.
    final flash = (1 - t * 2.6).clamp(0.0, 1.0);
    if (flash > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(
              (at.dx / size.width) * 2 - 1,
              (at.dy / size.height) * 2 - 1,
            ),
            radius: 0.45,
            colors: [_flewAway.withOpacity(0.16 * flash), Colors.transparent],
          ).createShader(rect),
      );
    }

    final a = art;
    if (a != null) {
      // Four illustrated frames stepped through over the first 60% of the
      // animation, growing as they go.
      final ft = (t / 0.6).clamp(0.0, 1.0);
      final frame = (ft * (_CrashArt.frames - 1)).round();
      final src = _CrashArt.explosionFrame(frame);
      final w = 150.0 + ft * 130.0;
      final h = w * src.height / src.width;
      canvas.drawImageRect(
        a.explosion,
        src,
        Rect.fromCenter(center: at, width: w, height: h),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withOpacity((1 - ft * 0.85).clamp(0.0, 1.0)),
      );
    }

    // Fireball: expands fast, cooling from white through gold to red.
    if (a == null && t < 0.5) {
      final ft = t / 0.5;
      final color = Color.lerp(
        Colors.white,
        Color.lerp(_CrashGameScreenState._cashGold, _flewAway, ft)!,
        ft,
      )!;
      canvas.drawCircle(
        at,
        10 + ft * 34,
        Paint()
          ..color = color.withOpacity((1 - ft) * 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + ft * 12),
      );
    }

    // Debris thrown outward and pulled down.
    if (a == null) for (final r in _debris) {
      final angle = r * math.pi * 2;
      final speed = 90 + r * 220;
      final x = at.dx + math.cos(angle) * speed * t;
      final y = at.dy + math.sin(angle) * speed * t + 300 * t * t;
      final opacity = (1 - t * 1.2).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      canvas.drawCircle(
        Offset(x, y),
        1.4 + r * 2.2,
        Paint()
          ..color = Color.lerp(_CrashGameScreenState._cashGold, _flewAway, r)!
              .withOpacity(opacity),
      );
    }

    // Smoke lingering after the fire dies.
    if (a == null) for (var i = 0; i < 8; i++) {
      final r = _debris[i];
      final drift = Offset(math.cos(r * 6.28) * 40, -30 - r * 40);
      canvas.drawCircle(
        at + drift * t,
        6 + t * 26 + r * 8,
        Paint()
          ..color = Colors.white.withOpacity((0.09 * (1 - t)).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }

    // The plane spirals out of frame, fading as it goes.
    if (t < 0.85) {
      final fade = ((1 - t / 0.85) * 255).clamp(0.0, 255.0).toInt();
      canvas.save();
      canvas.translate(at.dx + 180 * t, at.dy - 40 * t + 260 * t * t);
      canvas.rotate(t * 9);
      canvas.scale((1 - t * 0.6).clamp(0.2, 1.0));
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: 40),
        Paint()..color = Color.fromARGB(fade, 255, 255, 255),
      );
      _paintPlaneBody(canvas);
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FlightPainter old) =>
      old.multiplier != multiplier ||
      old.flying != flying ||
      old.crashed != crashed ||
      old.betting != betting ||
      old.elapsedMs != elapsedMs ||
      old.crashT != crashT ||
      old.bloom != bloom ||
      old.art != art ||
      old.ghosts.length != ghosts.length;
}

/// The illustrated artwork, decoded once and shared by every painter.
///
/// Each generated PNG has a large transparent margin, so the source rectangles
/// below are the measured content bounds — drawing the full image would scale
/// the empty space along with the art and shrink it to nothing.
class _CrashArt {
  const _CrashArt({
    required this.plane,
    required this.propeller,
    required this.explosion,
    required this.clouds,
    required this.coin,
    required this.skyLow,
    required this.skyMid,
    required this.skyHigh,
  });

  final ui.Image plane;
  final ui.Image propeller;
  final ui.Image explosion;
  final ui.Image clouds;
  final ui.Image coin;
  final ui.Image skyLow;
  final ui.Image skyMid;
  final ui.Image skyHigh;

  // Measured content bounds within each sheet.
  static const planeSrc = Rect.fromLTRB(249, 172, 1292, 780);
  static const propellerSrc = Rect.fromLTRB(401, 104, 1063, 703);
  static const coinSrc = Rect.fromLTRB(591, 344, 932, 659);

  // Both of these came back as a single row of four, not the 4x4 grid the brief
  // asked for, so they are sliced as four columns.
  static const explosionSrc = Rect.fromLTRB(55, 383, 1521, 625);
  static const cloudsSrc = Rect.fromLTRB(35, 356, 1518, 681);
  static const frames = 4;

  static Rect explosionFrame(int i) {
    final w = explosionSrc.width / frames;
    return Rect.fromLTWH(
        explosionSrc.left + w * i, explosionSrc.top, w, explosionSrc.height);
  }

  static Rect cloudFrame(int i) {
    final w = cloudsSrc.width / frames;
    return Rect.fromLTWH(
        cloudsSrc.left + w * i, cloudsSrc.top, w, cloudsSrc.height);
  }

  static Future<ui.Image> _decode(String name) async {
    final data = await rootBundle.load('assets/images/crash/$name');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  static Future<_CrashArt> load() async {
    // runway.png is deliberately absent: the generated file came back fully
    // transparent (max alpha 5), so the runway stays procedural.
    final images = await Future.wait([
      _decode('plane.png'),
      _decode('propeller.png'),
      _decode('explosion.png'),
      _decode('clouds.png'),
      _decode('coin.png'),
      _decode('sky_low.png'),
      _decode('sky_mid.png'),
      _decode('sky_high.png'),
    ]);
    return _CrashArt(
      plane: images[0],
      propeller: images[1],
      explosion: images[2],
      clouds: images[3],
      coin: images[4],
      skyLow: images[5],
      skyMid: images[6],
      skyHigh: images[7],
    );
  }
}

/// The three control points of the flight curve for one frame.
class _FlightGeometry {
  const _FlightGeometry(this.origin, this.control, this.tip);
  final Offset origin;
  final Offset control;
  final Offset tip;
}

/// The successful-cash-out flourish: an expanding green ring, a burst of coins
/// arcing outward under gravity, and the payout floating up and fading.
class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({required this.t, required this.amount, this.art});

  /// 0 → 1 over the life of the celebration.
  final double t;
  final int amount;
  final _CrashArt? art;

  static const _coins = 18;
  static const _green = _CrashGameScreenState._win;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.58);

    // Ring — fast out, gone by the time the coins peak.
    if (t < 0.55) {
      final rt = t / 0.55;
      canvas.drawCircle(
        origin,
        30 + rt * 150,
        Paint()
          ..color = _green.withOpacity((1 - rt) * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // Coins: launched on an even fan, then pulled down by gravity.
    for (var i = 0; i < _coins; i++) {
      final rand = math.Random(i * 613);
      final angle = -math.pi / 2 + (i / (_coins - 1) - 0.5) * 2.4;
      final speed = 150 + rand.nextDouble() * 140;

      final x = origin.dx + math.cos(angle) * speed * t;
      final y = origin.dy + math.sin(angle) * speed * t + 420 * t * t;
      final opacity = (1 - t * 1.15).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      // Spin flattens each coin as it turns — a squashed circle reads as a disc.
      final spin = (t * 9 + i).remainder(math.pi * 2);
      final squash = math.cos(spin).abs().clamp(0.18, 1.0);

      canvas.save();
      canvas.translate(x, y);
      canvas.scale(squash, 1.0);

      final a = art;
      if (a != null) {
        final src = _CrashArt.coinSrc;
        const cw = 16.0;
        canvas.drawImageRect(
          a.coin,
          src,
          Rect.fromCenter(
              center: Offset.zero, width: cw, height: cw * src.height / src.width),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Colors.white.withOpacity(opacity),
        );
      } else {
        canvas.drawCircle(
          Offset.zero,
          5,
          Paint()..color = _CrashGameScreenState._cashGold.withOpacity(opacity),
        );
        canvas.drawCircle(
          Offset.zero,
          5,
          Paint()
            ..color = Colors.white.withOpacity(opacity * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      canvas.restore();
    }

    // Floating payout.
    final textOpacity = (1 - math.max(0, t - 0.55) / 0.45).clamp(0.0, 1.0);
    if (textOpacity > 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: '+$amount',
          style: TextStyle(
            color: _green.withOpacity(textOpacity),
            fontSize: 34,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: _green.withOpacity(textOpacity * 0.6), blurRadius: 16),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(origin.dx - tp.width / 2, origin.dy - 40 - t * 90),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter old) =>
      old.t != t || old.amount != amount || old.art != art;
}

/// Colour-coded strip of the last rounds' crash points; each is tappable for
/// its provably-fair detail.
class _HistoryBar extends StatelessWidget {
  const _HistoryBar({required this.ticks, required this.onTap});

  final List<CrashHistoryTick> ticks;
  final void Function(int roundId) onTap;

  static Color _colorFor(double m) {
    if (m >= 10) return const Color(0xFFE91E63); // pink/red
    if (m >= 2) return const Color(0xFF9C27B0); // purple
    return const Color(0xFF2196F3); // blue
  }

  /// Three or more consecutive rounds at 2x+ — worth calling out, since a run
  /// of high multipliers is the thing players watch this bar for.
  bool get _hotStreak =>
      ticks.length >= 3 && ticks.take(3).every((t) => t.crashPoint >= 2);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: Row(children: [
          if (_hotStreak)
            Container(
              margin: const EdgeInsets.only(right: 6, left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE91E63).withOpacity(0.20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE91E63).withOpacity(0.6)),
              ),
              child: const Text('🔥',
                  style: TextStyle(fontSize: 13)),
            ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: ticks.length,
              itemBuilder: (context, i) {
                final t = ticks[i];
                final color = _colorFor(t.crashPoint);
                // Glow scales with the multiplier, so a big round is visible at
                // a glance rather than needing to be read.
                final heat = ((t.crashPoint - 1) / 9).clamp(0.0, 1.0);

                final chip = GestureDetector(
                  onTap: () => onTap(t.roundId),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.18 + heat * 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.5 + heat * 0.4)),
                      boxShadow: heat > 0.05
                          ? [
                              BoxShadow(
                                color: color.withOpacity(heat * 0.55),
                                blurRadius: 4 + heat * 14,
                              ),
                            ]
                          : null,
                    ),
                    child: Text('${t.crashPoint.toStringAsFixed(2)}x',
                        style: TextStyle(
                            color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                );

                // Only the newest chip animates in; the rest are already settled.
                if (i != 0) return chip;
                return TweenAnimationBuilder<double>(
                  key: ValueKey(t.roundId),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Opacity(
                    opacity: v.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset((1 - v) * 34, 0),
                      child: Transform.scale(scale: 0.85 + v * 0.15, child: child),
                    ),
                  ),
                  child: chip,
                );
              },
            ),
          ),
        ]),
      );
}

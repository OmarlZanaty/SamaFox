import 'dart:async';
import 'dart:math' as math;

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

  static const _bg = Color(0xFF1B1B1B);
  static const _bgGlow = Color(0xFF2A2A2A);
  static const _curveRed = Color(0xFF9B1C31);
  static const _flewAway = Color(0xFFFF0000);
  static const _betGreen = Color(0xFF28A745);
  static const _cancelRed = Color(0xFFDC3545);
  static const _cashGold = Color(0xFFD68E00);

  final CrashRepository _repo = CrashRepository();
  final SocketService _socket = SocketService();
  final AudioPlayer _sfx = AudioPlayer();
  final AudioPlayer _engine = AudioPlayer();

  late final Ticker _ticker = Ticker(_onTick);
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  CrashState? _state;
  int _balance = 0;
  String? _clientSeed;
  String? _notice;

  /// Local epoch-ms the current flight started at, derived from the server's
  /// `elapsedMs` so our own clock offset never matters.
  int? _flightAnchor;
  double _multiplier = 1.0;
  double _lastCrashPoint = 0;

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
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shake.dispose();
    _countdown?.cancel();
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
    setState(() => _multiplier = 1.0);
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

    setState(() {
      _multiplier = point;
      _lastCrashPoint = point;
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
    if ((data['userId'] as num?)?.toInt() != _myId) return;

    // Our own auto-cash-out fired server-side — reflect the payout locally.
    final slot = (data['slot'] as num?)?.toInt() ?? 0;
    final payout = (data['payout'] as num?)?.toInt() ?? 0;
    final m = (data['multiplier'] as num?)?.toDouble() ?? 1.0;
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
    if ((m - _multiplier).abs() < 0.0005) return;
    setState(() => _multiplier = m);
    _updateEnginePitch(m);
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
              if (_chatOpen)
                Positioned(left: 0, top: 0, bottom: 0, width: 240, child: _chatPanel()),
              Positioned(
                left: 8,
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
            const Text('🌧️', style: TextStyle(fontSize: 18)),
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
            child: CustomPaint(
              painter: _FlightPainter(
                multiplier: _multiplier,
                flying: s?.isFlying == true,
                crashed: crashed,
              ),
            ),
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (betting) ...[
                const Text('في انتظار الجولة القادمة',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
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
                if (crashed)
                  const Text('FLEW AWAY!',
                      style: TextStyle(
                          color: _flewAway,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2)),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(
                    color: crashed ? _flewAway : Colors.white,
                    fontSize: _multiplier >= 10 ? 64 : (_multiplier >= 2 ? 58 : 52),
                    fontWeight: FontWeight.w900,
                  ),
                  child: Text('${_multiplier.toStringAsFixed(2)}x'),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _liveBetsPanel() {
    final bets = _state?.bets ?? const <CrashBet>[];
    return Container(
      width: 150,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('الرهانات المباشرة (${bets.length})',
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const Divider(color: Colors.white12, height: 10),
        Expanded(
          child: bets.isEmpty
              ? const Center(
                  child: Text('لا رهانات بعد',
                      style: TextStyle(color: Colors.white30, fontSize: 11)))
              : ListView.builder(
                  itemCount: bets.length,
                  itemBuilder: (context, i) {
                    final b = bets[i];
                    final color = b.isWin
                        ? const Color(0xFF7CE38B)
                        : (b.isLoss ? Colors.white24 : Colors.white70);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                          child: Text(b.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: color, fontSize: 10)),
                        ),
                        Text(
                          b.isWin ? '${b.cashOutMultiplier!.toStringAsFixed(2)}x' : '${b.amount}',
                          style: TextStyle(color: color, fontSize: 10),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _chatPanel() => Container(
        color: Colors.black.withOpacity(0.55),
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          const Text('الدردشة', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
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
            child: _toggleRow('سحب تلقائي', panel.autoCashOutOn,
                (v) => setState(() => panel.autoCashOutOn = v)),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              controller: panel.autoController,
              enabled: panel.autoCashOutOn,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(isDense: true, suffixText: 'x'),
              onChanged: (v) => panel.autoCashOut = double.tryParse(v) ?? panel.autoCashOut,
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
                color: panel.settled == 'win' ? const Color(0xFF7CE38B) : Colors.white38,
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

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) => Row(children: [
        Transform.scale(
          scale: 0.7,
          child: Switch(value: value, onChanged: onChanged, activeColor: _betGreen),
        ),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 10)),
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
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        trailing: Text(
                          win ? '+${b.payout} (${b.cashOutMultiplier?.toStringAsFixed(2)}x)' : '-${b.amount}',
                          style: TextStyle(
                              color: win ? const Color(0xFF7CE38B) : Colors.white30,
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
                      color: f.verified ? const Color(0xFF7CE38B) : Colors.orangeAccent,
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
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
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

/// Draws the starfield, the parabolic flight curve, its filled area and the
/// plane riding the tip of it.
class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.multiplier,
    required this.flying,
    required this.crashed,
  });

  final double multiplier;
  final bool flying;
  final bool crashed;

  static final List<Offset> _stars = List.generate(
    60,
    (i) {
      final r = math.Random(i * 7919);
      return Offset(r.nextDouble(), r.nextDouble());
    },
  );

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint()..color = Colors.white.withOpacity(0.10);
    for (final s in _stars) {
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), 1.1, starPaint);
    }

    if (!flying && !crashed) return;

    // The curve fills the canvas as the multiplier grows: progress is capped so
    // a 100x round still draws inside the box, just flatter.
    final progress = (math.log(math.max(1, multiplier)) / math.log(10)).clamp(0.0, 1.0);
    final endX = size.width * (0.12 + 0.78 * progress);
    final endY = size.height * (0.9 - 0.75 * progress);

    final path = Path()..moveTo(size.width * 0.06, size.height * 0.92);
    path.quadraticBezierTo(
      size.width * 0.06 + (endX - size.width * 0.06) * 0.65,
      size.height * 0.92,
      endX,
      endY,
    );

    final fill = Path.from(path)
      ..lineTo(endX, size.height * 0.92)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_CrashGameScreenState._curveRed.withOpacity(0.45), Colors.transparent],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = crashed ? _CrashGameScreenState._flewAway : _CrashGameScreenState._curveRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
    );

    if (!crashed) _drawPlane(canvas, Offset(endX, endY), progress);
  }

  /// A simple red propeller-plane silhouette, tilted up as it climbs.
  void _drawPlane(Canvas canvas, Offset at, double progress) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(-0.5 + progress * 0.35);

    final body = Paint()..color = const Color(0xFFE53935);
    final path = Path()
      ..moveTo(14, 0)
      ..lineTo(-8, -6)
      ..lineTo(-4, 0)
      ..lineTo(-8, 6)
      ..close();
    canvas.drawPath(path, body);
    canvas.drawRect(const Rect.fromLTWH(-2, -9, 3, 18), body);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlightPainter old) =>
      old.multiplier != multiplier || old.flying != flying || old.crashed != crashed;
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

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: ticks.length,
          itemBuilder: (context, i) {
            final t = ticks[i];
            final color = _colorFor(t.crashPoint);
            return GestureDetector(
              onTap: () => onTap(t.roundId),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: Text('${t.crashPoint.toStringAsFixed(2)}x',
                    style: TextStyle(
                        color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            );
          },
        ),
      );
}

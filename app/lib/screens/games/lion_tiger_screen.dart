import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../repositories/boxing_repository.dart';
import '../../services/socket_service.dart';

/// حلبة الأسد والنمر — Lion & Tiger Arena.
///
/// This is the halal replacement for the classic "Lion or Tiger" casino table.
/// The original wagers coins on Lion / Tie / Tiger at 2x/30x odds while the
/// player just watches a fight animation, which is قمار: you stake money on an
/// uncertain outcome you cannot influence, and either multiply it or lose it.
///
/// Here there is no wager and no spectating. You pay a fixed, known ticket
/// price for one play — like paying for an arcade round — pick which fighter
/// you play as (الأسد or النمر, purely cosmetic, no odds attached), and then
/// you are the one in the ring: a timing marker sweeps across the power bar and
/// you tap to throw each punch. The server announces the round's corner
/// instruction (e.g. "كومبو ٤ لكمات متتالية") and your reward comes from how
/// well you performed it. Every fighter is guaranteed a reward, so nobody ever
/// walks away with nothing, and nobody wins another player's coins — the podium
/// is bragging rights only.
///
/// The server owns the mission, the score and the reward table
/// (backend/src/services/boxing.service.ts); this screen only runs the timing
/// bar and reports the accuracy of the punches that were thrown.
class LionTigerScreen extends ConsumerStatefulWidget {
  const LionTigerScreen({super.key});

  @override
  ConsumerState<LionTigerScreen> createState() => _LionTigerScreenState();
}

class _LionTigerScreenState extends ConsumerState<LionTigerScreen>
    with SingleTickerProviderStateMixin {
  /// One full sweep of the timing marker. This is the game's difficulty dial:
  /// the shorter it is, the harder it is to land a punch in the sweet spot, so
  /// scores — and therefore payouts — drop with it.
  static const _sweep = Duration(milliseconds: 800);

  /// Half-width of the sweet spot for the first punch, as a fraction of the
  /// bar. It shrinks by [_zoneShrink] with every punch so a full combo asks
  /// for real precision, not luck.
  ///
  /// These three, the sweep and [_accuracyFalloff] are calibrated together
  /// against a simulated human timing error: they hold an elite player at
  /// ~0.82x and a casual one at ~0.45x. Widening the zone or slowing the sweep
  /// flips the game player-positive and the platform loses coins.
  static const _zoneStart = 0.11;
  static const _zoneShrink = 0.015;
  static const _zoneMin = 0.05;

  /// How fast accuracy falls off with distance from the sweet spot centre.
  static const _accuracyFalloff = 75;

  static const _bgTop = Color(0xFF1A0E3E);
  static const _bgBottom = Color(0xFF0D0620);
  static const _canvas = Color(0xFF2B1055);
  static const _gold = Color(0xFFFFD54F);
  static const _lionColor = Color(0xFFFF8F00);
  static const _tigerColor = Color(0xFF7B1FA2);

  final BoxingRepository _repo = BoxingRepository();
  final SocketService _socket = SocketService();

  late final AnimationController _marker;

  BoxingRound? _round;
  List<BoxingPodiumEntry> _podium = const [];
  int _resultRoundId = 0;

  // Local play state for the round we paid into.
  int _joinedRoundId = 0;
  int _entry = 1000;
  String _corner = 'lion';
  int _balance = 0;
  final List<int> _punches = [];
  bool _submitted = false;
  int _lastScore = 0;
  int _lastReward = 0;
  String? _notice;

  /// Accuracy of the punch just thrown, for the hit flash.
  int? _flash;
  Timer? _flashTimer;

  /// My own last few scores. Deliberately NOT a table of past winners — the
  /// original's history bar exists so players can hunt for streaks to bet on.
  final List<int> _myHistory = [];

  Timer? _countdown;
  int _msLeft = 0;

  bool get _joinedCurrentRound =>
      _round != null && _joinedRoundId == _round!.roundId;
  int get _punchCount => _round?.punches ?? 6;
  bool get _punchesLeft => _punches.length < _punchCount;
  bool get _canPunch =>
      _round?.isPlaying == true &&
      _joinedCurrentRound &&
      !_submitted &&
      _punchesLeft;

  /// Half-width of the sweet spot for the punch about to be thrown.
  double get _zoneHalf =>
      max(_zoneMin, _zoneStart - _punches.length * _zoneShrink);

  @override
  void initState() {
    super.initState();
    _balance = ref.read(authStateProvider).user?.coinsBalance ?? 0;
    _marker = AnimationController(vsync: this, duration: _sweep);

    _socket.on('boxing_round_state', _onRoundState);
    _socket.on('boxing_round_result', _onRoundResult);
    _socket.emit('boxing_join_table', {});

    _repo.fetchRound().then((r) {
      if (mounted && r != null) _applyRound(r);
    }).catchError((_) {});

    _countdown = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _msLeft <= 0) return; // idle between rounds: no rebuild
      setState(() => _msLeft = max(0, _msLeft - 200));
    });
  }

  @override
  void dispose() {
    _marker.dispose();
    _flashTimer?.cancel();
    _countdown?.cancel();
    _socket.off('boxing_round_state');
    _socket.off('boxing_round_result');
    _socket.emit('boxing_leave_table', {});
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────
  void _onRoundState(dynamic data) {
    if (data is! Map) return;
    _applyRound(BoxingRound.fromJson(Map<String, dynamic>.from(data)));
  }

  void _applyRound(BoxingRound r) {
    if (!mounted) return;
    final previous = _round;
    setState(() {
      _round = r;
      _msLeft = r.msLeft;
      // A new round started — clear the previous play.
      if (previous != null && previous.roundId != r.roundId) {
        _resetPlay();
      }
    });
    _syncMarker();
  }

  void _onRoundResult(dynamic data) {
    if (data is! Map || !mounted) return;
    final map = Map<String, dynamic>.from(data);
    final rows = (map['podium'] as List?) ?? const [];
    setState(() {
      _resultRoundId = (map['roundId'] as num?)?.toInt() ?? 0;
      _podium = rows
          .whereType<Map>()
          .map((e) => BoxingPodiumEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });

    // Our own payout landed server-side — pull the authoritative balance in.
    final myId = ref.read(authStateProvider).user?.id;
    final results = (map['results'] as List?) ?? const [];
    for (final raw in results.whereType<Map>()) {
      if ((raw['userId'] as num?)?.toInt() == myId) {
        final reward = (raw['reward'] as num?)?.toInt() ?? 0;
        final score = (raw['score'] as num?)?.toInt() ?? 0;
        setState(() {
          _lastScore = score;
          _lastReward = reward;
          _balance += reward;
          _myHistory.insert(0, score);
          if (_myHistory.length > 8) _myHistory.removeLast();
        });
        ref.read(authStateProvider.notifier).updateCoinsBalance(_balance);
        break;
      }
    }
  }

  void _resetPlay() {
    _joinedRoundId = 0;
    _punches.clear();
    _submitted = false;
    _lastScore = 0;
    _lastReward = 0;
    _notice = null;
    _flash = null;
  }

  // ── Timing bar ────────────────────────────────────────────
  /// The marker repaints at 60fps, so it only sweeps while we actually have a
  /// punch to throw. Between rounds, while watching someone else's round, or
  /// once all punches are spent, it is stopped outright.
  void _syncMarker() {
    if (_canPunch) {
      if (!_marker.isAnimating) _marker.repeat(reverse: true);
    } else if (_marker.isAnimating) {
      _marker.stop();
    }
  }

  void _throwPunch() {
    if (!_canPunch) return;
    // Distance from the sweet spot centre, in bar fractions.
    final distance = (_marker.value - 0.5).abs();
    // 100 dead centre, ~25 at the edge of the zone, fading to 0 well outside —
    // a near miss still scores something, so effort always counts.
    final accuracy =
        (100 - (distance / _zoneHalf) * _accuracyFalloff).round().clamp(0, 100);

    setState(() {
      _punches.add(accuracy);
      _flash = accuracy;
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _flash = null);
    });

    if (!_punchesLeft) {
      _syncMarker(); // out of punches — stop the sweep
      _submit();
    }
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _join() async {
    final r = _round;
    if (r == null || !r.isJoining || _joinedCurrentRound) return;
    if (_balance < _entry) {
      setState(() => _notice = 'رصيدك لا يكفي');
      return;
    }
    try {
      final result = await _repo.join(entry: _entry, corner: _corner);
      if (!mounted) return;
      setState(() {
        _joinedRoundId = result.roundId;
        _balance = result.balance;
        _punches.clear();
        _submitted = false;
        _notice = 'دخلت الحلبة — مكافأتك المضمونة ${_fmt(result.minReward)} '
            'وتصل إلى ${_fmt(result.maxReward)}';
      });
      ref.read(authStateProvider.notifier).updateCoinsBalance(result.balance);
    } on BoxingException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _submit() async {
    final r = _round;
    if (r == null || !r.isPlaying || !_joinedCurrentRound || _submitted) return;
    // Punches never thrown count as misses, not as a forfeit — the guaranteed
    // floor still applies.
    final thrown = List<int>.from(_punches);
    while (thrown.length < _punchCount) {
      thrown.add(0);
    }
    setState(() => _submitted = true);
    _syncMarker();
    try {
      final result = await _repo.submit(roundId: r.roundId, punches: thrown);
      if (!mounted) return;
      setState(() {
        _lastScore = result.score;
        _lastReward = result.reward;
        _notice = 'أداؤك ${result.score}/100 — مكافأتك ${_fmt(result.reward)}';
      });
    } on BoxingException catch (e) {
      if (mounted) {
        setState(() {
          _submitted = false;
          _notice = e.message;
        });
        _syncMarker(); // submit failed — let the player keep punching
      }
    }
  }

  String _fmt(int v) {
    if (v >= 1000000)
      return '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
    if (v >= 1000)
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    return '$v';
  }

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = _round;
    return Scaffold(
      backgroundColor: _bgBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('حلبة الأسد والنمر',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _balanceBar(),
                const SizedBox(height: 12),
                _phaseHeader(r),
                const SizedBox(height: 12),
                _ring(),
                const SizedBox(height: 12),
                if (_notice != null) _noticeBar(_notice!),
                const SizedBox(height: 8),
                _controls(r),
                const SizedBox(height: 16),
                if (_myHistory.isNotEmpty) ...[
                  _historyStrip(),
                  const SizedBox(height: 16),
                ],
                _playersStrip(r),
                if (_podium.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _podiumCard(),
                ],
                const SizedBox(height: 16),
                _fairnessNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('رصيدك', style: TextStyle(color: Colors.white70)),
          Text('🪙 ${_fmt(_balance)}',
              style: const TextStyle(
                  color: _gold, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _phaseHeader(BoxingRound? r) {
    final String title;
    final String subtitle;
    if (r == null) {
      title = 'جارٍ الاتصال…';
      subtitle = '';
    } else if (r.isJoining) {
      title = 'وقت الدخول';
      subtitle = _joinedCurrentRound
          ? 'أنت في الحلبة، استعد'
          : 'ادفع رسوم الدخول واختر شخصيتك';
    } else if (r.isPlaying) {
      title = r.missionLabel ?? 'تعليمات المدرب';
      subtitle = _joinedCurrentRound
          ? 'سدّد لكماتك عندما يصل المؤشر للمنطقة الذهبية'
          : 'الجولة جارية — انتظر الجولة القادمة';
    } else {
      title = 'النتائج';
      subtitle = 'الجولة القادمة تبدأ الآن';
    }

    final seconds = (_msLeft / 1000).ceil();
    return Column(
      children: [
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle,
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('⏱ $seconds',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  /// The ring: your fighter, the timing bar, and the punches you have left.
  Widget _ring() {
    final playing = _round?.isPlaying == true && _joinedCurrentRound;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A148C), _canvas],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold.withOpacity(0.35), width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _fighterFace('lion', '🦁', 'الأسد'),
              _hitFlash(),
              _fighterFace('tiger', '🐯', 'النمر'),
            ],
          ),
          const SizedBox(height: 18),
          _timingBar(playing),
          const SizedBox(height: 14),
          _punchPips(),
        ],
      ),
    );
  }

  Widget _fighterFace(String id, String emoji, String label) {
    final mine = _corner == id;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.25),
            border: Border.all(
              color: mine ? _gold : Colors.white.withOpacity(0.15),
              width: mine ? 3 : 1,
            ),
            boxShadow: [
              if (mine)
                BoxShadow(color: _gold.withOpacity(0.5), blurRadius: 14),
            ],
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 34)),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
              color: mine ? _gold : Colors.white60,
              fontSize: 12,
              fontWeight: mine ? FontWeight.bold : FontWeight.normal,
            )),
      ],
    );
  }

  /// Feedback for the punch just thrown — the only "fight animation" here, and
  /// it reflects the player's own timing rather than a random winner.
  Widget _hitFlash() {
    final acc = _flash;
    final String text;
    final Color color;
    if (acc == null) {
      text = '🥊';
      color = Colors.white24;
    } else if (acc >= 88) {
      text = 'قاضية!';
      color = _gold;
    } else if (acc >= 70) {
      text = 'لكمة قوية';
      color = const Color(0xFF4CAF50);
    } else if (acc >= 40) {
      text = 'لمسة';
      color = Colors.white70;
    } else {
      text = 'أخطأت';
      color = Colors.white38;
    }
    return SizedBox(
      width: 96,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Text(
          text,
          key: ValueKey(text),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color,
              fontSize: acc == null ? 28 : 16,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _timingBar(bool playing) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final half = _zoneHalf;
        return SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Track
              Container(
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              // Sweet spot
              Positioned(
                left: width * (0.5 - half),
                width: width * half * 2,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      _gold.withOpacity(0.25),
                      _gold.withOpacity(0.75),
                      _gold.withOpacity(0.25),
                    ]),
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
              // Marker
              AnimatedBuilder(
                animation: _marker,
                builder: (context, _) {
                  final value = playing ? _marker.value : 0.5;
                  return Positioned(
                    left: (width * value - 3).clamp(0.0, width - 6),
                    child: Container(
                      width: 6,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.white.withOpacity(0.6),
                              blurRadius: 8)
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _punchPips() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_punchCount, (i) {
        final thrown = i < _punches.length;
        final acc = thrown ? _punches[i] : 0;
        final Color color;
        if (!thrown) {
          color = Colors.white24;
        } else if (acc >= 88) {
          color = _gold;
        } else if (acc >= 70) {
          color = const Color(0xFF4CAF50);
        } else if (acc >= 40) {
          color = Colors.white54;
        } else {
          color = Colors.red.withOpacity(0.5);
        }
        return Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          alignment: Alignment.center,
          child: thrown
              ? Text('$acc',
                  style: const TextStyle(
                      fontSize: 9,
                      color: Colors.black87,
                      fontWeight: FontWeight.bold))
              : null,
        );
      }),
    );
  }

  Widget _noticeBar(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }

  Widget _controls(BoxingRound? r) {
    if (r == null) return const SizedBox.shrink();

    if (r.isJoining && !_joinedCurrentRound) {
      final tiers = r.entryTiers.isEmpty
          ? const [1000, 5000, 10000, 50000]
          : r.entryTiers;
      return Column(
        children: [
          Text('اختر شخصيتك',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7), fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              _cornerButton('lion', '🦁 الأسد', _lionColor),
              const SizedBox(width: 10),
              _cornerButton('tiger', '🐯 النمر', _tigerColor),
            ],
          ),
          const SizedBox(height: 6),
          Text('الاختيار للمظهر فقط ولا يغيّر مكافأتك',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 11)),
          const SizedBox(height: 14),
          Text('اختر رسوم الدخول',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7), fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: tiers.map((t) {
              final selected = t == _entry;
              return ChoiceChip(
                label: Text(_fmt(t)),
                selected: selected,
                onSelected: (_) => setState(() => _entry = t),
                backgroundColor: Colors.white.withOpacity(0.08),
                selectedColor: _gold,
                labelStyle: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _join,
              child: Text('ادخل الحلبة — ${_fmt(_entry)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      );
    }

    if (r.isPlaying && _joinedCurrentRound && !_submitted) {
      return Column(
        children: [
          Text(
              'باقي ${_punchCount - _punches.length} لكمات — كل لكمة تضيّق المنطقة الذهبية',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6), fontSize: 12)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _throwPunch,
              child: const Text('🥊 لكمة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ),
        ],
      );
    }

    if (_submitted && _lastScore > 0) {
      return _noticeBar('أداؤك $_lastScore/100 — مكافأتك ${_fmt(_lastReward)}');
    }

    return const SizedBox.shrink();
  }

  Widget _cornerButton(String id, String label, Color color) {
    final selected = _corner == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _corner = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(selected ? 0.35 : 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _gold : Colors.white.withOpacity(0.1),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  /// My own recent performances — progress tracking, not a streak table to bet
  /// against.
  Widget _historyStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('آخر نتائجك',
            style:
                TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: _myHistory
              .map((s) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$s',
                        style: TextStyle(
                            color: s >= 80 ? _gold : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _playersStrip(BoxingRound? r) {
    final players = r?.players ?? const <BoxingPlayer>[];
    if (players.isEmpty) {
      return Text('لا يوجد لاعبون في هذه الجولة بعد',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('في الحلبة (${players.length})',
            style:
                TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: players.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = players[i];
              return Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.submitted
                            ? const Color(0xFF4CAF50)
                            : Colors.white24,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white10,
                      backgroundImage:
                          (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
                              ? NetworkImage(p.avatarUrl!)
                              : null,
                      child: (p.avatarUrl == null || p.avatarUrl!.isEmpty)
                          ? const Icon(Icons.person,
                              size: 18, color: Colors.white54)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 52,
                    child: Text('${p.corner == 'lion' ? '🦁' : '🐯'} ${p.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 10)),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _podiumCard() {
    const medals = ['🥇', '🥈', '🥉'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('أفضل أداء — جولة $_resultRoundId',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ..._podium.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(medals[(e.rank - 1).clamp(0, 2)],
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(e.corner == 'lion' ? '🦁' : '🐯'),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white)),
                    ),
                    Text('${e.score}/100  •  🪙 ${_fmt(e.reward)}',
                        style: const TextStyle(color: _gold, fontSize: 12)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _fairnessNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.25)),
      ),
      child: const Text(
        'لعبة مهارة وليست مراهنة: رسوم الدخول ثابتة ومعروفة قبل الدفع، '
        'ولا توجد مضاعفات ولا رهان على فائز، وكل مشترك يحصل على مكافأة مضمونة. '
        'اختيار الأسد أو النمر للمظهر فقط، والمكافأة تعتمد على دقة لكماتك '
        'ولا أحد يربح من خسارة لاعب آخر.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.6),
      ),
    );
  }
}

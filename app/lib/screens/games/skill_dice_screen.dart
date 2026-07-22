import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../repositories/skill_dice_repository.dart';
import '../../services/socket_service.dart';

/// نرد المهارة — Skill Dice.
///
/// This is the halal replacement for the classic "Greedy Dice" casino table.
/// The original wagers coins on Small/Big/Tiger at 2x/35x odds, which is قمار:
/// you stake money on an uncertain outcome and either multiply it or lose it.
///
/// Here there is no wager at all. You pay a fixed, known entry price for one
/// play — like paying for an arcade round — and the server announces a mission
/// (e.g. "اجمع ١١ بالضبط"). Three dice spin; you tap to stop each one on the
/// face you want, and you get one re-roll to fix your worst die. Your reward
/// comes from how well you performed the mission, and every entrant is
/// guaranteed a reward, so nobody ever walks away with nothing. Nobody wins
/// another player's coins either — the podium is bragging rights only.
///
/// The server owns the mission, the score and the reward table
/// (backend/src/services/skillDice.service.ts); this screen only animates and
/// reports the faces the player landed on.
class SkillDiceScreen extends ConsumerStatefulWidget {
  const SkillDiceScreen({super.key});

  @override
  ConsumerState<SkillDiceScreen> createState() => _SkillDiceScreenState();
}

class _SkillDiceScreenState extends ConsumerState<SkillDiceScreen> {
  static const _spinTick = Duration(milliseconds: 110);
  static const _bgTop = Color(0xFF1A0E3E);
  static const _bgBottom = Color(0xFF0D0620);
  static const _felt = Color(0xFF0E5138);

  final SkillDiceRepository _repo = SkillDiceRepository();
  final SocketService _socket = SocketService();

  DiceRound? _round;
  List<DicePodiumEntry> _podium = const [];
  int _resultRoundId = 0;

  // Local play state for the round we paid into.
  int _joinedRoundId = 0;
  int _entry = 1000;
  int _balance = 0;
  final List<int> _faces = [1, 1, 1];
  final List<bool> _locked = [false, false, false];
  bool _rerollUsed = false;
  bool _submitted = false;
  int _lastScore = 0;
  int _lastReward = 0;
  String? _notice;

  Timer? _spinTimer;
  Timer? _countdown;
  int _msLeft = 0;

  bool get _joinedCurrentRound => _round != null && _joinedRoundId == _round!.roundId;
  bool get _allLocked => _locked.every((l) => l);

  @override
  void initState() {
    super.initState();
    _balance = ref.read(authStateProvider).user?.coinsBalance ?? 0;

    _socket.on('dice_round_state', _onRoundState);
    _socket.on('dice_round_result', _onRoundResult);
    _socket.emit('dice_join_table', {});

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
    _spinTimer?.cancel();
    _countdown?.cancel();
    _socket.off('dice_round_state');
    _socket.off('dice_round_result');
    _socket.emit('dice_leave_table', {});
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────
  void _onRoundState(dynamic data) {
    if (data is! Map) return;
    _applyRound(DiceRound.fromJson(Map<String, dynamic>.from(data)));
  }

  void _applyRound(DiceRound r) {
    if (!mounted) return;
    final previous = _round;
    setState(() {
      _round = r;
      _msLeft = r.msLeft;
      // A new round started — clear the previous play.
      if (previous != null && previous.roundId != r.roundId) {
        _resetPlay();
      }
      // The play phase just opened for a round we paid into: start the dice.
      if (r.isPlaying && _joinedRoundId == r.roundId && !_submitted) {
        for (var i = 0; i < 3; i++) {
          _locked[i] = false;
        }
      }
    });
    _syncSpinTimer();
  }

  void _onRoundResult(dynamic data) {
    if (data is! Map || !mounted) return;
    final map = Map<String, dynamic>.from(data);
    final rows = (map['podium'] as List?) ?? const [];
    setState(() {
      _resultRoundId = (map['roundId'] as num?)?.toInt() ?? 0;
      _podium = rows
          .whereType<Map>()
          .map((e) => DicePodiumEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });

    // Our own payout landed server-side — pull the authoritative balance in.
    final myId = ref.read(authStateProvider).user?.id;
    final results = (map['results'] as List?) ?? const [];
    for (final raw in results.whereType<Map>()) {
      if ((raw['userId'] as num?)?.toInt() == myId) {
        final reward = (raw['reward'] as num?)?.toInt() ?? 0;
        setState(() {
          _lastReward = reward;
          _balance += reward;
        });
        ref.read(authStateProvider.notifier).updateCoinsBalance(_balance);
        break;
      }
    }
  }

  void _resetPlay() {
    _joinedRoundId = 0;
    _rerollUsed = false;
    _submitted = false;
    _lastScore = 0;
    _lastReward = 0;
    _notice = null;
    for (var i = 0; i < 3; i++) {
      _locked[i] = false;
    }
  }

  // ── Dice spin / stop ──────────────────────────────────────
  /// The spin timer rebuilds this screen ~9x a second, so it only runs while
  /// there is actually a die in motion — during our own play phase, with at
  /// least one die still unlocked. Between rounds, while watching someone
  /// else's round, or once all three are stopped, it is cancelled outright
  /// rather than left ticking against a static table.
  bool get _shouldSpin =>
      _round?.isPlaying == true &&
      _joinedCurrentRound &&
      !_submitted &&
      _locked.any((l) => !l);

  void _syncSpinTimer() {
    if (_shouldSpin) {
      _spinTimer ??= Timer.periodic(_spinTick, (_) => _tickSpin());
    } else {
      _spinTimer?.cancel();
      _spinTimer = null;
    }
  }

  void _tickSpin() {
    if (!mounted || !_shouldSpin) {
      _syncSpinTimer();
      return;
    }
    setState(() {
      for (var i = 0; i < 3; i++) {
        if (!_locked[i]) _faces[i] = _faces[i] % 6 + 1;
      }
    });
  }

  void _tapDie(int index) {
    if (_round?.isPlaying != true || !_joinedCurrentRound || _submitted) return;
    setState(() {
      if (!_locked[index]) {
        _locked[index] = true; // stop it on the face showing right now
      } else if (!_rerollUsed) {
        // Spend the single re-roll on this die.
        _locked[index] = false;
        _rerollUsed = true;
        _notice = 'استخدمت إعادة الرمي';
      }
    });
    _syncSpinTimer(); // stops once all three are locked, restarts on a re-roll
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
      final result = await _repo.join(_entry);
      if (!mounted) return;
      setState(() {
        _joinedRoundId = result.roundId;
        _balance = result.balance;
        _rerollUsed = false;
        _submitted = false;
        _notice = 'دخلت الجولة — مكافأتك المضمونة ${_fmt(result.minReward)} '
            'وتصل إلى ${_fmt(result.maxReward)}';
        for (var i = 0; i < 3; i++) {
          _locked[i] = false;
        }
      });
      _syncSpinTimer();
      ref.read(authStateProvider.notifier).updateCoinsBalance(result.balance);
    } on SkillDiceException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _submit() async {
    final r = _round;
    if (r == null || !r.isPlaying || !_joinedCurrentRound || _submitted) return;
    setState(() => _submitted = true);
    _syncSpinTimer();
    try {
      final result = await _repo.submit(roundId: r.roundId, dice: List<int>.from(_faces));
      if (!mounted) return;
      setState(() {
        _lastScore = result.score;
        _lastReward = result.reward;
        _notice = 'نتيجتك ${result.score}/100 — مكافأتك ${_fmt(result.reward)}';
      });
    } on SkillDiceException catch (e) {
      if (mounted) {
        setState(() {
          _submitted = false;
          _notice = e.message;
        });
        _syncSpinTimer(); // submit failed — let the player stop the dice again
      }
    }
  }

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
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
        title: const Text('نرد المهارة',
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
                _table(),
                const SizedBox(height: 12),
                if (_notice != null) _noticeBar(_notice!),
                const SizedBox(height: 8),
                _controls(r),
                const SizedBox(height: 16),
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
                  color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _phaseHeader(DiceRound? r) {
    final String title;
    final String subtitle;
    if (r == null) {
      title = 'جارٍ الاتصال…';
      subtitle = '';
    } else if (r.isJoining) {
      title = 'وقت الدخول';
      subtitle = _joinedCurrentRound ? 'أنت داخل الجولة، استعد' : 'ادفع رسوم الدخول للمشاركة';
    } else if (r.isPlaying) {
      title = r.missionLabel ?? 'المهمة';
      subtitle = _joinedCurrentRound
          ? 'أوقف كل نردة على الرقم المناسب'
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
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('⏱ $seconds',
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _table() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF146A48), _felt],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.35), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (i) => _die(i)),
      ),
    );
  }

  Widget _die(int index) {
    final locked = _locked[index];
    final active = _round?.isPlaying == true && _joinedCurrentRound && !_submitted;
    return GestureDetector(
      onTap: () => _tapDie(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: locked ? const Color(0xFFFFD54F) : Colors.white.withOpacity(0.4),
            width: locked ? 3 : 1,
          ),
          boxShadow: [
            if (locked)
              BoxShadow(color: const Color(0xFFFFD54F).withOpacity(0.6), blurRadius: 14),
            if (!locked && active)
              BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8),
          ],
        ),
        child: CustomPaint(painter: _DiePainter(_faces[index])),
      ),
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

  Widget _controls(DiceRound? r) {
    if (r == null) return const SizedBox.shrink();

    if (r.isJoining && !_joinedCurrentRound) {
      final tiers = r.entryTiers.isEmpty ? const [1000, 5000, 10000, 50000] : r.entryTiers;
      return Column(
        children: [
          Text('اختر رسوم الدخول',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
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
                selectedColor: const Color(0xFFFFD54F),
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
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _join,
              child: Text('ادخل الجولة — ${_fmt(_entry)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      );
    }

    if (r.isPlaying && _joinedCurrentRound && !_submitted) {
      return Column(
        children: [
          Text(
            _rerollUsed
                ? 'اضغط على النردة لإيقافها'
                : 'اضغط على النردة لإيقافها — واضغط على نردة متوقفة لإعادة رميها (مرة واحدة)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _allLocked ? const Color(0xFF4CAF50) : Colors.white24,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _allLocked ? _submit : null,
              child: const Text('سجّل النتيجة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      );
    }

    if (_submitted && _lastScore > 0) {
      return _noticeBar('نتيجتك $_lastScore/100 — مكافأتك ${_fmt(_lastReward)}');
    }

    return const SizedBox.shrink();
  }

  Widget _playersStrip(DiceRound? r) {
    final players = r?.players ?? const <DicePlayer>[];
    if (players.isEmpty) {
      return Text('لا يوجد لاعبون في هذه الجولة بعد',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('اللاعبون (${players.length})',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
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
                        color: p.submitted ? const Color(0xFF4CAF50) : Colors.white24,
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
                          ? const Icon(Icons.person, size: 18, color: Colors.white54)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 52,
                    child: Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, fontSize: 10)),
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ..._podium.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(medals[(e.rank - 1).clamp(0, 2)],
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white)),
                    ),
                    Text('${e.score}/100  •  🪙 ${_fmt(e.reward)}',
                        style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 12)),
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
        'وكل مشترك يحصل على مكافأة مضمونة، والمكافأة تعتمد على أدائك في المهمة '
        'ولا أحد يربح من خسارة لاعب آخر.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.6),
      ),
    );
  }
}

/// Draws the pips for a die face.
class _DiePainter extends CustomPainter {
  final int face;
  const _DiePainter(this.face);

  static const _layouts = <int, List<Offset>>{
    1: [Offset(0.5, 0.5)],
    2: [Offset(0.28, 0.28), Offset(0.72, 0.72)],
    3: [Offset(0.26, 0.26), Offset(0.5, 0.5), Offset(0.74, 0.74)],
    4: [Offset(0.3, 0.3), Offset(0.7, 0.3), Offset(0.3, 0.7), Offset(0.7, 0.7)],
    5: [
      Offset(0.28, 0.28),
      Offset(0.72, 0.28),
      Offset(0.5, 0.5),
      Offset(0.28, 0.72),
      Offset(0.72, 0.72),
    ],
    6: [
      Offset(0.3, 0.24),
      Offset(0.7, 0.24),
      Offset(0.3, 0.5),
      Offset(0.7, 0.5),
      Offset(0.3, 0.76),
      Offset(0.7, 0.76),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1A0E3E);
    final radius = size.shortestSide * 0.09;
    for (final p in _layouts[face] ?? const <Offset>[]) {
      canvas.drawCircle(Offset(p.dx * size.width, p.dy * size.height), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DiePainter oldDelegate) => oldDelegate.face != face;
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../repositories/skill_wheel_repository.dart';
import '../../services/socket_service.dart';

/// عجلة المهارة — Skill Wheel.
///
/// This is the halal replacement for the casino roulette table. The original
/// stakes coins on a number / colour / dozen at 36x / 3x / 2x odds, which is
/// قمار: you wager money on an uncertain outcome and either multiply it or lose
/// it entirely.
///
/// Here there is no wager and no betting zone at all. You pay a fixed, known
/// entry price for one play — like paying for an arcade round — and the server
/// announces the target pocket BEFORE the wheel starts. The wheel then spins at
/// a fixed, known speed and you tap to stop it: the closer the pointer lands to
/// the announced pocket, the bigger the reward. Every entrant is guaranteed a
/// reward, so nobody ever walks away with nothing, and nobody wins another
/// player's coins — the podium is bragging rights only.
///
/// The server owns the target, the score and the reward table
/// (backend/src/services/skillWheel.service.ts); this screen only animates the
/// wheel and reports the pocket the player stopped on.
class SkillWheelScreen extends ConsumerStatefulWidget {
  const SkillWheelScreen({super.key});

  @override
  ConsumerState<SkillWheelScreen> createState() => _SkillWheelScreenState();
}

class _SkillWheelScreenState extends ConsumerState<SkillWheelScreen>
    with SingleTickerProviderStateMixin {
  /// Pocket order on the physical wheel — must match WHEEL_SEQUENCE in
  /// backend/src/services/skillWheel.service.ts, since the server scores by
  /// distance along this ring.
  static const List<int> _sequence = [
    0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5,
    24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
  ];

  /// One full revolution. This is the game's difficulty dial: the faster it
  /// spins, the harder it is to stop on the announced pocket, so scores — and
  /// therefore payouts — drop with it. 2s over 37 pockets ≈ 54ms per pocket,
  /// which is what the server's DISTANCE_SCORE table is calibrated against —
  /// slowing it down makes the game player-positive and the platform loses
  /// coins to skilled players.
  static const _revolution = Duration(milliseconds: 2000);

  static const _bgTop = Color(0xFF1A0E3E);
  static const _bgBottom = Color(0xFF0D0620);
  static const _gold = Color(0xFFFFD54F);

  final SkillWheelRepository _repo = SkillWheelRepository();
  final SocketService _socket = SocketService();

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _revolution,
  );

  WheelRound? _round;
  List<WheelPodiumEntry> _podium = const [];
  int _resultRoundId = 0;

  // Local play state for the round we paid into.
  int _joinedRoundId = 0;
  int _entry = 1000;
  int _balance = 0;
  int? _landed; // pocket we stopped on, once stopped
  bool _submitted = false;
  int _lastScore = 0;
  int _lastReward = 0;
  String? _notice;

  Timer? _countdown;
  int _msLeft = 0;

  bool get _joinedCurrentRound => _round != null && _joinedRoundId == _round!.roundId;

  /// The wheel should only turn while we are actually playing our own round.
  bool get _shouldSpin =>
      _round?.isPlaying == true && _joinedCurrentRound && _landed == null && !_submitted;

  @override
  void initState() {
    super.initState();
    _balance = ref.read(authStateProvider).user?.coinsBalance ?? 0;

    _socket.on('wheel_round_state', _onRoundState);
    _socket.on('wheel_round_result', _onRoundResult);
    _socket.emit('wheel_join_table', {});

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
    _spin.dispose();
    _countdown?.cancel();
    _socket.off('wheel_round_state');
    _socket.off('wheel_round_result');
    _socket.emit('wheel_leave_table', {});
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────
  void _onRoundState(dynamic data) {
    if (data is! Map) return;
    _applyRound(WheelRound.fromJson(Map<String, dynamic>.from(data)));
  }

  void _applyRound(WheelRound r) {
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
    _syncSpin();
  }

  void _onRoundResult(dynamic data) {
    if (data is! Map || !mounted) return;
    final map = Map<String, dynamic>.from(data);
    final rows = (map['podium'] as List?) ?? const [];
    setState(() {
      _resultRoundId = (map['roundId'] as num?)?.toInt() ?? 0;
      _podium = rows
          .whereType<Map>()
          .map((e) => WheelPodiumEntry.fromJson(Map<String, dynamic>.from(e)))
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
    _landed = null;
    _submitted = false;
    _lastScore = 0;
    _lastReward = 0;
    _notice = null;
  }

  // ── Wheel ─────────────────────────────────────────────────
  void _syncSpin() {
    if (_shouldSpin) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
  }

  /// The pocket sitting under the pointer (top of the wheel) right now.
  int _pocketUnderPointer() {
    final sector = 2 * pi / _sequence.length;
    final theta = (_spin.value * 2 * pi) % (2 * pi);
    final index = ((_sequence.length - theta / sector).round()) % _sequence.length;
    return _sequence[index];
  }

  void _stopWheel() {
    if (!_shouldSpin) return;
    _spin.stop();
    setState(() {
      _landed = _pocketUnderPointer();
      _notice = null;
    });
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
        _landed = null;
        _submitted = false;
        _notice = 'دخلت الجولة — مكافأتك المضمونة ${_fmt(result.minReward)} '
            'وتصل إلى ${_fmt(result.maxReward)}';
      });
      _syncSpin();
      ref.read(authStateProvider.notifier).updateCoinsBalance(result.balance);
    } on SkillWheelException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _submit() async {
    final r = _round;
    final landed = _landed;
    if (r == null || !r.isPlaying || !_joinedCurrentRound || _submitted || landed == null) {
      return;
    }
    setState(() => _submitted = true);
    try {
      final result = await _repo.submit(roundId: r.roundId, landed: landed);
      if (!mounted) return;
      setState(() {
        _lastScore = result.score;
        _lastReward = result.reward;
        _notice = 'نتيجتك ${result.score}/100 — مكافأتك ${_fmt(result.reward)}';
      });
    } on SkillWheelException catch (e) {
      if (mounted) {
        setState(() {
          _submitted = false;
          _notice = e.message;
        });
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
        title: const Text('عجلة المهارة',
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
                _wheel(r),
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
                  color: _gold, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _phaseHeader(WheelRound? r) {
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
          ? 'العجلة تدور بسرعة ثابتة — أوقفها على الرقم المطلوب'
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

  Widget _wheel(WheelRound? r) {
    final target = r?.isPlaying == true ? r?.target : null;
    return GestureDetector(
      onTap: _stopWheel,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3B1170), Color(0xFF1a0533)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _gold.withOpacity(0.35), width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _spin,
                builder: (_, child) =>
                    Transform.rotate(angle: _spin.value * 2 * pi, child: child),
                // Painted once and rotated, rather than repainted every frame.
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _WheelPainter(sequence: _sequence, target: target),
                ),
              ),
              // Pointer: fixed at the top, the wheel turns underneath it.
              const Align(
                alignment: Alignment.topCenter,
                child: Icon(Icons.arrow_drop_down, color: _gold, size: 46),
              ),
              _hubLabel(r, target),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hubLabel(WheelRound? r, int? target) {
    final String big;
    final String small;
    if (_landed != null) {
      big = '$_landed';
      small = target != null ? 'المطلوب $target' : '';
    } else if (target != null) {
      big = '$target';
      small = 'الهدف';
    } else {
      big = '★';
      small = '';
    }
    return Container(
      width: 96,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1a0533),
        border: Border.all(color: _gold.withOpacity(0.6), width: 2),
        boxShadow: [BoxShadow(color: _gold.withOpacity(0.25), blurRadius: 18)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(big,
              style: const TextStyle(color: _gold, fontSize: 30, fontWeight: FontWeight.bold)),
          if (small.isNotEmpty)
            Text(small, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
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

  Widget _controls(WheelRound? r) {
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
      final stopped = _landed != null;
      return Column(
        children: [
          Text(
            stopped
                ? 'وقفت على $_landed — سجّل نتيجتك'
                : 'اضغط على العجلة أو على الزر لإيقافها',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: stopped ? const Color(0xFF4CAF50) : _gold,
                foregroundColor: stopped ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: stopped ? _submit : _stopWheel,
              child: Text(stopped ? 'سجّل النتيجة' : 'أوقف العجلة',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      );
    }

    if (_submitted && _lastReward > 0) {
      return _noticeBar('نتيجتك $_lastScore/100 — مكافأتك ${_fmt(_lastReward)}');
    }

    return const SizedBox.shrink();
  }

  Widget _playersStrip(WheelRound? r) {
    final players = r?.players ?? const <WheelPlayer>[];
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
                      backgroundImage: (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
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
        'لعبة مهارة وليست مراهنة: لا توجد رهانات ولا مضاعفات، رسوم الدخول ثابتة '
        'ومعروفة قبل الدفع، والرقم المطلوب يُعلن قبل بدء الدوران، وكل مشترك يحصل '
        'على مكافأة مضمونة تعتمد على دقة إيقافه للعجلة، ولا أحد يربح من خسارة '
        'لاعب آخر.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.6),
      ),
    );
  }
}

/// Draws the wheel: one coloured sector per pocket, its number along the rim,
/// and a gold ring around the announced target so the player can see what they
/// are aiming at.
class _WheelPainter extends CustomPainter {
  final List<int> sequence;
  final int? target;

  const _WheelPainter({required this.sequence, required this.target});

  static const Set<int> _red = {
    1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36,
  };

  Color _colorFor(int n) {
    if (n == 0) return const Color(0xFF1B7A3E);
    return _red.contains(n) ? const Color(0xFFB3172B) : const Color(0xFF16121F);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final sector = 2 * pi / sequence.length;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < sequence.length; i++) {
      final n = sequence[i];
      // Sector i is centred at the top when the wheel is unrotated.
      final start = -pi / 2 + (i - 0.5) * sector;
      canvas.drawArc(rect, start, sector, true, Paint()..color = _colorFor(n));

      if (n == target) {
        canvas.drawArc(
          rect.deflate(2),
          start,
          sector,
          true,
          Paint()
            ..color = const Color(0xFFFFD54F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }

      final label = TextPainter(
        text: TextSpan(
          text: '$n',
          style: TextStyle(
            color: n == target ? const Color(0xFFFFD54F) : Colors.white,
            fontSize: radius * 0.11,
            fontWeight: n == target ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Place the number along the rim, rotated to face outwards.
      final angle = -pi / 2 + i * sector;
      canvas.save();
      canvas.translate(
        center.dx + cos(angle) * radius * 0.82,
        center.dy + sin(angle) * radius * 0.82,
      );
      canvas.rotate(angle + pi / 2);
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
    }

    // Gold rim + hub ring.
    final rim = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius - 2, rim);
    canvas.drawCircle(center, radius * 0.32, rim..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.target != target;
}

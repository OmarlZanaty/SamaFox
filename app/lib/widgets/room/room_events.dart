import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../main.dart' show navigatorKey;
import '../../services/active_room.dart';
import '../../services/dio_client.dart';
import '../../services/socket_service.dart';
import '../app_network_image.dart';
import 'room_jump.dart';
import 'room_left_rail.dart';

/// SPEC52 #28 / #29 — the room's gift Rocket and PK.
///
/// Everything here only DISPLAYS what the server decides: rocket progress and
/// launch, who may claim and what they won, PK scores, the countdown (from the
/// server's endsAt) and the result. Server events: rocket_state,
/// rocket_launched (global), pk_state, pk_result, pk_invite.
class RoomEventsBus {
  RoomEventsBus._();
  static final RoomEventsBus instance = RoomEventsBus._();

  final _rocket = StreamController<Map<String, dynamic>>.broadcast();
  final _launch = StreamController<Map<String, dynamic>>.broadcast();
  final _pk = StreamController<Map<String, dynamic>>.broadcast();
  final _pkResult = StreamController<Map<String, dynamic>>.broadcast();
  bool _wired = false;

  Stream<Map<String, dynamic>> get rocket => _rocket.stream;
  Stream<Map<String, dynamic>> get launch => _launch.stream;
  Stream<Map<String, dynamic>> get pk => _pk.stream;
  Stream<Map<String, dynamic>> get pkResult => _pkResult.stream;

  void wire() {
    if (_wired) return;
    _wired = true;
    final s = SocketService();
    void pipe(String ev, StreamController<Map<String, dynamic>> c) => s.on(ev, (d) {
          if (d is Map) c.add(Map<String, dynamic>.from(d));
        });
    pipe('rocket_state', _rocket);
    pipe('rocket_launched', _launch);
    pipe('pk_state', _pk);
    pipe('pk_result', _pkResult);
    s.on('pk_invite', (d) {
      if (d is Map) _showPkInvite(Map<String, dynamic>.from(d));
    });
    // A rocket launched in ANOTHER room: a small banner, tap → go there.
    _launch.stream.listen((d) {
      final rid = (d['roomId'] as num?)?.toInt();
      if (rid == null || rid == ActiveRoom.instance.roomId) return;
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF4A148C),
        duration: const Duration(seconds: 6),
        content: Text('🚀 انطلق صاروخ في غرفة ${d['roomName'] ?? rid}', textDirection: TextDirection.rtl),
        action: SnackBarAction(
          label: 'انتقال',
          textColor: const Color(0xFFFFD54F),
          onPressed: () => confirmAndJumpToRoom(rid, roomName: d['roomName']?.toString()),
        ),
      ));
    });
  }

  void _showPkInvite(Map<String, dynamic> d) {
    final ctx = navigatorKey.currentContext;
    final id = d['pkId']?.toString() ?? d['id']?.toString();
    if (ctx == null || id == null) return;
    showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1655),
        title: const Text('دعوة PK', style: TextStyle(color: Colors.white)),
        content: Text('غرفة #${d['roomId']} تتحداك في PK لمدة ${((d['durationSec'] as num?)?.toInt() ?? 300) ~/ 60} دقائق',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('رفض')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dctx);
              try {
                await DioClient.dio.post('/pk/$id/accept');
              } catch (e) {
                _toast(_err(e));
              }
            },
            child: const Text('قبول'),
          ),
        ],
      ),
    );
  }
}

String _err(Object e) {
  try {
    final d = (e as dynamic).response?.data;
    if (d is Map && d['message'] != null) return d['message'].toString();
  } catch (_) {}
  return 'تعذر تنفيذ العملية';
}

void _toast(String m) {
  final ctx = navigatorKey.currentContext;
  if (ctx != null) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(m)));
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
  return '$n';
}

// ─────────────────────────────── Rocket ───────────────────────────────

class RoomRocketButton extends StatefulWidget {
  const RoomRocketButton({super.key, required this.roomId});
  final int roomId;

  @override
  State<RoomRocketButton> createState() => _RoomRocketButtonState();
}

class _RoomRocketButtonState extends State<RoomRocketButton> {
  Map<String, dynamic>? _rocket;
  final _subs = <StreamSubscription>[];
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    RoomEventsBus.instance.wire();
    _subs.add(RoomEventsBus.instance.rocket.listen((d) {
      if ((d['roomId'] as num?)?.toInt() == widget.roomId && mounted) setState(() => _rocket = d);
    }));
    _subs.add(RoomEventsBus.instance.launch.listen((d) {
      if ((d['roomId'] as num?)?.toInt() != widget.roomId || !mounted) return;
      setState(() => _rocket = d);
      RocketLaunchOverlay.show(context, d);
    }));
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.dio.get('/room-events/${widget.roomId}');
      final d = (res.data is Map ? res.data['data'] : null) as Map?;
      if (!mounted || d == null) return;
      setState(() {
        _enabled = d['rocketConfig'] != null || d['rocket'] != null;
        final r = d['rocket'];
        _rocket = r is Map ? Map<String, dynamic>.from(r) : null;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled && _rocket == null) return const SizedBox.shrink();
    final active = _rocket?['status'] == 'ACTIVE';
    final cur = active ? ((_rocket?['current'] ?? _rocket?['currentCoins']) as num?)?.toInt() ?? 0 : 0;
    final target = ((_rocket?['target'] ?? _rocket?['targetCoins']) as num?)?.toInt() ?? 0;
    final p = target > 0 ? (cur / target).clamp(0.0, 1.0) : 0.0;
    return GestureDetector(
      onTap: () => _openSheet(cur, target),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: p,
                  strokeWidth: 3,
                  color: const Color(0xFFFFB300),
                  backgroundColor: Colors.white12,
                ),
                Image.asset('assets/images/spec52/rocket.png',
                    width: 22, height: 22, errorBuilder: (_, __, ___) => const Text('🚀', style: TextStyle(fontSize: 16))),
              ],
            ),
          ),
          Text(target > 0 ? '${_compact(cur)}/${_compact(target)}' : 'صاروخ',
              style: const TextStyle(
                  color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 3)])),
        ],
      ),
    );
  }

  void _openSheet(int cur, int target) {
    final r = _rocket;
    final rewards = (r?['rewards'] as List?) ?? const [];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF160C33),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚀 صاروخ الهدايا', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: target > 0 ? (cur / target).clamp(0.0, 1.0) : 0,
                minHeight: 10,
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFFFFB300),
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 6),
              Text('$cur / $target كوينز', textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              const Text('كل هدية في الغرفة تملأ الصاروخ. عند اكتماله ينطلق ويستلم المتواجدون جوائز من الصندوق.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
              if (rewards.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final rw in rewards.whereType<Map>())
                      Chip(
                        backgroundColor: Colors.white10,
                        label: Text(rw['type'] == 'coins' ? '${rw['coins']} كوينز' : (rw['name'] ?? 'منتج').toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                  ],
                ),
              ],
              if (r?['status'] == 'LAUNCHED') ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    RocketLaunchOverlay.claim(r!);
                  },
                  child: const Text('استلم الجائزة'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The launch: a rocket flies up with a flame trail (~2.5 s, light painter),
/// then «استلم الجائزة».
class RocketLaunchOverlay {
  static void show(BuildContext context, Map<String, dynamic> event) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RocketFlight(onDone: () {
        entry.remove();
        _offerClaim(event);
      }),
    );
    overlay.insert(entry);
  }

  static void _offerClaim(Map<String, dynamic> event) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1655),
        title: const Text('🚀 انطلق الصاروخ!', style: TextStyle(color: Colors.white)),
        content: const Text('استلم جائزتك قبل انتهاء الوقت', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('لاحقاً')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dctx);
              claim(event);
            },
            child: const Text('استلم الجائزة'),
          ),
        ],
      ),
    );
  }

  static Future<void> claim(Map<String, dynamic> event) async {
    final id = (event['eventId'] ?? event['id'])?.toString();
    if (id == null) return;
    try {
      final res = await DioClient.dio.post('/rockets/$id/claim');
      final r = (res.data is Map ? res.data['data'] : null) as Map?;
      if (r == null) return;
      _toast(r['type'] == 'coins'
          ? '🎉 ربحت ${r['coins']} كوينز من الصاروخ'
          : '🎉 ربحت ${r['name'] ?? 'منتج'} من الصاروخ');
    } catch (e) {
      _toast(_err(e));
    }
  }
}

class _RocketFlight extends StatefulWidget {
  const _RocketFlight({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_RocketFlight> createState() => _RocketFlightState();
}

class _RocketFlightState extends State<_RocketFlight> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = Curves.easeIn.transform(_c.value);
          final y = size.height * (0.85 - 1.1 * t);
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _SparkPainter(_c.value))),
            Positioned(
              left: size.width / 2 - 40,
              top: y,
              child: Column(children: [
                Image.asset('assets/images/spec52/rocket.png',
                    width: 80, height: 80, errorBuilder: (_, __, ___) => const Text('🚀', style: TextStyle(fontSize: 64, decoration: TextDecoration.none))),
                Opacity(
                  opacity: 0.9,
                  child: Image.asset('assets/images/spec52/rocket_flame.png',
                      width: 46, height: 60, errorBuilder: (_, __, ___) => const Text('🔥', style: TextStyle(fontSize: 36, decoration: TextDecoration.none))),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final p = Paint();
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final y0 = size.height * (0.4 + rnd.nextDouble() * 0.6);
      final y = y0 - t * size.height * (0.3 + rnd.nextDouble() * 0.4);
      p.color = [const Color(0xFFFFD54F), const Color(0xFFFF4081), Colors.white][i % 3].withOpacity((1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 2 + rnd.nextDouble() * 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.t != t;
}

// ─────────────────────────────── PK ───────────────────────────────

class RoomPkButton extends StatelessWidget {
  const RoomPkButton({super.key, required this.roomId, required this.canStart, required this.seated});
  final int roomId;
  final bool canStart;

  /// Seated users {id: name} for a room PK.
  final Map<int, String> seated;

  @override
  Widget build(BuildContext context) {
    return RoomRailButton(
      icon: Icons.sports_mma_rounded,
      color: const Color(0xFFFF5252),
      label: 'PK',
      onTap: () {
        if (!canStart) {
          _toast('بدء PK لصاحب الغرفة والمشرفين');
          return;
        }
        _openStart(context);
      },
    );
  }

  void _openStart(BuildContext context) {
    String type = 'ROOM';
    int duration = 300;
    int? a;
    int? b;
    final opp = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF160C33),
      builder: (sctx) => StatefulBuilder(
        builder: (sctx, set) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(sctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('بدء PK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ROOM', label: Text('داخل الغرفة')),
                    ButtonSegment(value: 'GLOBAL', label: Text('غرفة ضد غرفة')),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => set(() => type = v.first),
                ),
                const SizedBox(height: 10),
                if (type == 'ROOM') ...[
                  _pick('اللاعب A', a, (v) => set(() => a = v)),
                  _pick('اللاعب B', b, (v) => set(() => b = v)),
                ] else
                  TextField(
                    controller: opp,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'رقم الغرفة المنافسة', labelStyle: TextStyle(color: Colors.white54)),
                  ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, children: [
                  for (final d in const [180, 300, 600])
                    ChoiceChip(
                      label: Text('${d ~/ 60} دقائق'),
                      selected: duration == d,
                      onSelected: (_) => set(() => duration = d),
                    ),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await DioClient.dio.post('/pk/start', data: {
                        'roomId': roomId,
                        'type': type,
                        'durationSec': duration,
                        if (type == 'ROOM') 'sideAUserId': a,
                        if (type == 'ROOM') 'sideBUserId': b,
                        if (type == 'GLOBAL') 'opponentRoomId': int.tryParse(opp.text.trim()),
                      });
                      if (sctx.mounted) Navigator.pop(sctx);
                    } catch (e) {
                      _toast(_err(e));
                    }
                  },
                  child: const Text('ابدأ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pick(String label, int? value, ValueChanged<int?> onChanged) => DropdownButtonFormField<int>(
        value: value,
        dropdownColor: const Color(0xFF2A1655),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white54)),
        items: [
          for (final e in seated.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.white))),
        ],
        onChanged: onChanged,
      );
}

/// A VS B, scores, split progress bar, server countdown — under the header
/// while a PK runs in this room.
class RoomPkBar extends StatefulWidget {
  const RoomPkBar({super.key, required this.roomId});
  final int roomId;

  @override
  State<RoomPkBar> createState() => _RoomPkBarState();
}

class _RoomPkBarState extends State<RoomPkBar> {
  Map<String, dynamic>? _pk;
  Map<int, Map> _people = {};
  final _subs = <StreamSubscription>[];
  Timer? _tick;

  bool _mine(Map d) =>
      (d['roomId'] as num?)?.toInt() == widget.roomId ||
      (d['opponentRoomId'] as num?)?.toInt() == widget.roomId ||
      (d['room1Id'] as num?)?.toInt() == widget.roomId ||
      (d['room2Id'] as num?)?.toInt() == widget.roomId;

  @override
  void initState() {
    super.initState();
    RoomEventsBus.instance.wire();
    _subs.add(RoomEventsBus.instance.pk.listen((d) {
      if (_mine(d) && mounted) {
        setState(() => _pk = d);
        _loadPeople();
      }
    }));
    _subs.add(RoomEventsBus.instance.pkResult.listen((d) {
      if (!_mine(d) || !mounted) return;
      setState(() => _pk = null);
      _showResult(d);
    }));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _pk != null) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.dio.get('/room-events/${widget.roomId}');
      final d = (res.data is Map ? res.data['data'] : null) as Map?;
      final pk = d?['pk'];
      if (!mounted || pk is! Map) return;
      if (pk['status'] == 'ACTIVE' || pk['status'] == 'PENDING') {
        setState(() {
          _pk = Map<String, dynamic>.from(pk);
          _people = {
            for (final p in (d?['participants'] as List? ?? const []).whereType<Map>()) (p['id'] as num).toInt(): p,
          };
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPeople() async {
    try {
      final res = await DioClient.dio.get('/room-events/${widget.roomId}');
      final d = (res.data is Map ? res.data['data'] : null) as Map?;
      if (!mounted || d == null) return;
      setState(() => _people = {
            for (final p in (d['participants'] as List? ?? const []).whereType<Map>()) (p['id'] as num).toInt(): p,
          });
    } catch (_) {}
  }

  void _showResult(Map d) {
    final w = d['winner']?.toString();
    final a = (d['scoreA'] as num?)?.toInt() ?? 0;
    final b = (d['scoreB'] as num?)?.toInt() ?? 0;
    _toast(w == 'TIE' ? '🤝 تعادل في PK ($a : $b)' : '🏆 انتهى PK — الفائز ${w == 'A' ? 'A' : 'B'} ($a : $b)');
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Widget _side(int? uid, String fallback, Color c) {
    final p = uid == null ? null : _people[uid];
    final url = p?['avatarUrl']?.toString();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
        radius: 11,
        backgroundColor: c,
        backgroundImage: (url ?? '').isNotEmpty ? appImage(url!, 22) : null,
      ),
      const SizedBox(width: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 70),
        child: Text((p?['name'] ?? fallback).toString(),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pk = _pk;
    if (pk == null) return const SizedBox.shrink();
    final a = (pk['scoreA'] as num?)?.toInt() ?? 0;
    final b = (pk['scoreB'] as num?)?.toInt() ?? 0;
    final total = a + b;
    final share = total == 0 ? 0.5 : a / total;
    final ends = DateTime.tryParse('${pk['endsAt'] ?? ''}')?.toLocal();
    final left = ends == null ? Duration.zero : ends.difference(DateTime.now());
    final secs = left.isNegative ? 0 : left.inSeconds;
    final pending = pk['status'] == 'PENDING';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _side((pk['sideAUserId'] as num?)?.toInt(), 'A', const Color(0xFFFF4081)),
          const Spacer(),
          Text(pending ? 'بانتظار القبول' : 'VS  ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontSize: 11)),
          const Spacer(),
          _side((pk['sideBUserId'] as num?)?.toInt(), 'B', const Color(0xFF448AFF)),
        ]),
        const SizedBox(height: 3),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            Text('$a', style: const TextStyle(color: Color(0xFFFF80AB), fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Row(children: [
                  Expanded(flex: math.max(1, (share * 1000).round()), child: Container(height: 6, color: const Color(0xFFFF4081))),
                  Expanded(flex: math.max(1, ((1 - share) * 1000).round()), child: Container(height: 6, color: const Color(0xFF448AFF))),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            Text('$b', style: const TextStyle(color: Color(0xFF82B1FF), fontSize: 10, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }
}

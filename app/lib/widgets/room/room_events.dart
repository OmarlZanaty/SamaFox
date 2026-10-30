import '../../l10n/tr.dart';
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
        content: Text(tr('🚀 انطلق صاروخ في غرفة ${d['roomName'] ?? rid}', "🚀 A rocket launched in room ${d['roomName'] ?? rid}"), textDirection: TextDirection.rtl),
        action: SnackBarAction(
          label: tr('انتقال', "Go"),
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
        title: Text(tr('دعوة PK', "PK invitation"), style: TextStyle(color: Colors.white)),
        content: Text(tr('غرفة #${d['roomId']} تتحداك في PK لمدة ${((d['durationSec'] as num?)?.toInt() ?? 300) ~/ 60} دقائق', "Room #${d['roomId']} challenges you to PK for ${((d['durationSec'] as num?)?.toInt() ?? 300) ~/ 60} minutes"),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('رفض', "Decline"))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dctx);
              try {
                await DioClient.dio.post('/pk/$id/accept');
              } catch (e) {
                _toast(_err(e));
              }
            },
            child: Text(tr('قبول', "Accept")),
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
  return tr('تعذر تنفيذ العملية', "Could not complete action");
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
          Text(target > 0 ? '${_compact(cur)}/${_compact(target)}' : tr('صاروخ', "Rocket"),
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
              Text(tr('🚀 صاروخ الهدايا', "🚀 Gift rocket"), style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: target > 0 ? (cur / target).clamp(0.0, 1.0) : 0,
                minHeight: 10,
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFFFFB300),
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 6),
              Text(tr('$cur / $target كوينز', "$cur / $target coins"), textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              Text(tr('كل هدية في الغرفة تملأ الصاروخ. عند اكتماله ينطلق ويستلم المتواجدون جوائز من الصندوق.', "Every gift in the room fills the rocket. When full, it launches and everyone present can claim a prize from the chest."),
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
                        label: Text(rw['type'] == 'coins' ? tr('${rw['coins']} كوينز', "${rw['coins']} coins") : (rw['name'] ?? tr('منتج', "Item")).toString(),
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
                  child: Text(tr('استلم الجائزة', "Claim prize")),
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
        title: Text(tr('🚀 انطلق الصاروخ!', "🚀 Rocket launched!"), style: TextStyle(color: Colors.white)),
        content: Text(tr('استلم جائزتك قبل انتهاء الوقت', "Claim your prize before time runs out"), style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('لاحقاً', "Later"))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dctx);
              claim(event);
            },
            child: Text(tr('استلم الجائزة', "Claim prize")),
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
          ? tr('🎉 ربحت ${r['coins']} كوينز من الصاروخ', "🎉 You won ${r['coins']} coins from the rocket")
          : tr('🎉 ربحت ${r['name'] ?? 'منتج'} من الصاروخ', "🎉 You won ${r['name'] ?? 'an item'} from the rocket"));
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

/// Rooms searching for a random PK opponent (client @383), shown on the PK
/// card until a match arrives.
final ValueNotifier<Set<int>> pkSearchingRooms = ValueNotifier<Set<int>>(<int>{});

/// The server keeps a waiting room for two minutes; re-join while searching.
final Map<int, Timer> _pkSearchTimers = {};

Future<void> _joinRandomPk(int roomId, int durationSec) async {
  final res = await DioClient.dio.post('/pk/random', data: {'roomId': roomId, 'durationSec': durationSec});
  final d = res.data is Map ? res.data['data'] : null;
  if (d is Map && d['status'] == 'WAITING') {
    pkSearchingRooms.value = {...pkSearchingRooms.value, roomId};
    _pkSearchTimers[roomId]?.cancel();
    _pkSearchTimers[roomId] = Timer(const Duration(seconds: 100), () {
      if (pkSearchingRooms.value.contains(roomId)) {
        _joinRandomPk(roomId, durationSec).catchError((Object e) {
          _stopPkSearch(roomId);
          _toast(_err(e));
        });
      }
    });
  } else {
    _stopPkSearch(roomId);
  }
}

void _stopPkSearch(int roomId) {
  _pkSearchTimers.remove(roomId)?.cancel();
  if (pkSearchingRooms.value.contains(roomId)) {
    pkSearchingRooms.value = {...pkSearchingRooms.value}..remove(roomId);
  }
}

Future<void> cancelRandomPk(int roomId) async {
  _stopPkSearch(roomId);
  try {
    await DioClient.dio.post('/pk/random/cancel', data: {'roomId': roomId});
  } catch (_) {}
}

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
          _toast(tr('بدء PK لصاحب الغرفة والمشرفين', "Only room owners and moderators can start PK"));
          return;
        }
        _openStart(context);
      },
    );
  }

  void _openStart(BuildContext context) {
    String type = 'ROOM';
    int? a;
    int? b;
    final opp = TextEditingController();
    final minutes = TextEditingController(text: '5');
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
                Text(tr('بدء PK', "Start PK"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'ROOM', label: Text(tr('داخل الغرفة', "Within room"))),
                    ButtonSegment(value: 'GLOBAL', label: Text(tr('غرفة ضد غرفة', "Room vs room"))),
                    ButtonSegment(value: 'RANDOM', label: Text(tr('عشوائي', "Random"))),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => set(() => type = v.first),
                ),
                const SizedBox(height: 10),
                if (type == 'ROOM') ...[
                  _pick(tr('اللاعب A', "Player A"), a, (v) => set(() => a = v)),
                  _pick(tr('اللاعب B', "Player B"), b, (v) => set(() => b = v)),
                ] else if (type == 'GLOBAL')
                  TextField(
                    controller: opp,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(labelText: tr('رقم الغرفة المنافسة', "Opponent room ID"), labelStyle: const TextStyle(color: Colors.white54)),
                  )
                else
                  Text(
                    tr('هنقابلك بغرفة تانية مفعّلة PK عشوائي، وكل واحد يفضل في غرفته.',
                        'You will be matched with another room that turned on random PK; each side stays in its own room.'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                const SizedBox(height: 12),
                // Client @199: «المطلوب مربع كمان احط فيه المده».
                Row(children: [
                  Text(tr('المدة (دقائق)', 'Duration (minutes)'), style: const TextStyle(color: Colors.white70)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      key: const Key('pk_minutes'),
                      controller: minutes,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (final m in const [3, 5, 10, 15, 30])
                    ActionChip(label: Text('$m'), onPressed: () => set(() => minutes.text = '$m')),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final m = int.tryParse(minutes.text.trim());
                    if (m == null || m < 1 || m > 60) {
                      _toast(tr('المدة من 1 إلى 60 دقيقة', 'Duration must be 1–60 minutes'));
                      return;
                    }
                    try {
                      if (type == 'RANDOM') {
                        await _joinRandomPk(roomId, m * 60);
                      } else {
                        await DioClient.dio.post('/pk/start', data: {
                          'roomId': roomId,
                          'type': type,
                          'durationSec': m * 60,
                          if (type == 'ROOM') 'sideAUserId': a,
                          if (type == 'ROOM') 'sideBUserId': b,
                          if (type == 'GLOBAL') 'opponentRoomId': int.tryParse(opp.text.trim()),
                        });
                      }
                      if (sctx.mounted) Navigator.pop(sctx);
                    } catch (e) {
                      _toast(_err(e));
                    }
                  },
                  child: Text(type == 'RANDOM' ? tr('ابحث عن منافس', 'Find an opponent') : tr('ابدأ', "Start")),
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

/// The PK card (design the client sent, image 1025_0102): fire ring vs ice
/// ring, VS, gifts and a gold/blue bar, the server countdown, a support button
/// that gifts the side's player, and a button at its edge that hides it to a
/// small pill and brings it back. The winner is shown mid-screen at the end.
class RoomPkBar extends StatefulWidget {
  const RoomPkBar({
    super.key, required this.roomId, this.onSupport, this.initialPk,
    this.initialPeople, this.onGift, this.onToggleMute, this.muted = false,
    this.isOnMic,
  });
  final VoidCallback? onGift;
  final VoidCallback? onToggleMute;
  final bool muted;
  final bool Function(int userId)? isOnMic;
  final int roomId;

  /// Opens the gift sheet on that player (client @377: «كل دعم يوصل للمضيف»).
  final void Function(int userId, String name, String? avatarUrl)? onSupport;

  /// Preview/testing only: a PK to show without the server.
  final Map<String, dynamic>? initialPk;
  final Map<int, Map>? initialPeople;

  @override
  State<RoomPkBar> createState() => _RoomPkBarState();
}

class _RoomPkBarState extends State<RoomPkBar> {
  Map<String, dynamic>? _pk;
  Map<int, Map> _people = {};
  final _subs = <StreamSubscription>[];
  Timer? _tick;
  bool _hidden = false;

  bool _mine(Map d) =>
      (d['roomId'] as num?)?.toInt() == widget.roomId ||
      (d['opponentRoomId'] as num?)?.toInt() == widget.roomId ||
      (d['room1Id'] as num?)?.toInt() == widget.roomId ||
      (d['room2Id'] as num?)?.toInt() == widget.roomId;

  @override
  void initState() {
    super.initState();
    _pk = widget.initialPk;
    _people = {...?widget.initialPeople};
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _pk != null) setState(() {});
    });
    pkSearchingRooms.addListener(_onSearching);
    if (widget.initialPk != null) return;
    RoomEventsBus.instance.wire();
    _subs.add(RoomEventsBus.instance.pk.listen((d) {
      if (_mine(d) && mounted) {
        _stopPkSearch(widget.roomId);
        setState(() => _pk = d);
        _loadPeople();
      }
    }));
    _subs.add(RoomEventsBus.instance.pkResult.listen((d) {
      if (!_mine(d) || !mounted) return;
      final people = _people;
      setState(() => _pk = null);
      showPkWinner(context, d, people);
    }));
    _load();
  }

  void _onSearching() {
    if (mounted) setState(() {});
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

  @override
  void dispose() {
    _tick?.cancel();
    pkSearchingRooms.removeListener(_onSearching);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pk = _pk;
    if (pk == null) {
      if (!pkSearchingRooms.value.contains(widget.roomId)) return const SizedBox.shrink();
      return _searching();
    }
    final a = (pk['scoreA'] as num?)?.toInt() ?? 0;
    final b = (pk['scoreB'] as num?)?.toInt() ?? 0;
    final ends = DateTime.tryParse('${pk['endsAt'] ?? ''}')?.toLocal();
    final left = ends == null ? Duration.zero : ends.difference(DateTime.now());
    final secs = left.isNegative ? 0 : left.inSeconds;
    final clock = '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
    final pending = pk['status'] == 'PENDING';
    if (_hidden) return _pill(pending ? '…' : clock);
    final total = a + b;
    final share = total == 0 ? 0.5 : a / total;
    final aId = (pk['sideAUserId'] as num?)?.toInt();
    final bId = (pk['sideBUserId'] as num?)?.toInt();
    // Room vs room: you can only gift your own room's player from here.
    final global = pk['type'] == 'GLOBAL';
    final mySide = (pk['room1Id'] as num?)?.toInt() == widget.roomId ? 'A' : 'B';
    final supportId = global && mySide == 'B' ? bId : aId;
    final supportPerson = _people[supportId];
    final actions = <Widget>[
      if (widget.onGift != null)
        _action(Icons.card_giftcard, tr('هدية', 'Gift'), const Color(0xFFFFD778), widget.onGift!),
      if (widget.onToggleMute != null)
        _action(Icons.mic, tr('كتم', 'Mute'), const Color(0xFFFFDDA0), widget.onToggleMute!, dot: widget.muted),
      if (widget.onSupport != null && supportId != null)
        _action(Icons.star_rounded, tr('دعم', 'Support'), const Color(0xFF65B4FF),
          () => widget.onSupport!(supportId,
            (supportPerson?['name'] ?? (global && mySide == 'B' ? tr('لاعب ب', 'Player B') : tr('لاعب أ', 'Player A'))).toString(),
            supportPerson?['avatarUrl']?.toString())),
    ];
    final roundLabel = pk['round'] != null || pk['rounds'] != null
        ? " · ${tr('جولة', 'ROUND')} ${pk['round'] ?? 1}/${pk['rounds'] ?? pk['round']}"
        : '';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [const Color(0xFF191C27).withValues(alpha: .93), const Color(0xFF0B1420).withValues(alpha: .91)]),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: .25)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .4), blurRadius: 14)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .07), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.circle, size: 6, color: Color(0xFFFF565F)),
                  const SizedBox(width: 4),
                  Text(tr('مباشر', 'LIVE'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(fit: BoxFit.scaleDown, child: Text('${tr('تحدي صوتي', 'Voice PK')}$roundLabel',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                  )),
                  Text(clock, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.timer_outlined, size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                  _hideButton(Icons.close_rounded),
                ]),
              ),
              const SizedBox(height: 12),
              Text(tr('صندوق PK', 'PK box'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              if (pending)
                Text(tr('بانتظار القبول', 'Awaiting acceptance'), style: const TextStyle(color: Colors.white60, fontSize: 10)),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final avatarSize = math.min(72.0, ((constraints.maxWidth - 44) / 2) * .62);
                final frameSize = avatarSize / .62;
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _player(aId, tr('لاعب أ', 'Player A'), fire: true, score: a, avatarSize: avatarSize, canSupport: !global || mySide == 'A')),
                  SizedBox(width: 44, height: frameSize, child: const Center(child: _VsMark())),
                  Expanded(child: _player(bId, tr('لاعب ب', 'Player B'), fire: false, score: b, avatarSize: avatarSize, canSupport: !global || mySide == 'B')),
                ]);
              }),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _gifts(a, fire: true),
                _gifts(b, fire: false),
              ]),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 8,
                  child: Row(children: [
                    Expanded(
                      flex: math.max(1, (share * 1000).round()),
                      child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFFE082)]))),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, ((1 - share) * 1000).round()),
                      child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4FC3F7), Color(0xFF1565C0)]))),
                    ),
                  ]),
                ),
              ),
              if (!pending) ...[
                const SizedBox(height: 5),
                Text(tr('ادعم لاعبك بالهدايا عشان يكسب · PK ينتهي خلال $clock', 'Support your player with gifts to help them win · PK ends in $clock'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 9.5)),
              ],
              ]),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF10141F).withValues(alpha: .94),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: .18)),
              ),
              child: Row(children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) Container(width: 1, height: 38, color: Colors.white12),
                  Expanded(child: actions[i]),
                ],
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _action(IconData icon, String label, Color color, VoidCallback onTap, {bool dot = false}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (dot) ...[
                const Icon(Icons.circle, size: 5, color: Color(0xFFFF5252)),
                const SizedBox(width: 4),
              ],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
      );

  Widget _gifts(int score, {required bool fire}) {
    final color = fire ? const Color(0xFFFFD778) : const Color(0xFF79CBFF);
    final contents = <Widget>[
      Icon(Icons.card_giftcard, color: color, size: 24),
      const SizedBox(width: 5),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('هدايا', 'Gifts'), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        Row(children: [
          Text(_compact(score), style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(width: 5),
          Icon(fire ? Icons.monetization_on : Icons.diamond, color: color, size: 18),
        ]),
      ]),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: contents);
  }

  Widget _hideButton(IconData icon) => InkWell(
        key: const Key('pk_hide'),
        onTap: () => setState(() => _hidden = !_hidden),
        customBorder: const CircleBorder(),
        child: Padding(padding: const EdgeInsets.all(2), child: Icon(icon, size: 18, color: Colors.white70)),
      );

  Widget _pill(String clock) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: GestureDetector(
          key: const Key('pk_show'),
          onTap: () => setState(() => _hidden = false),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF7A18), Color(0xFF2F80ED)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('PK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              const SizedBox(width: 6),
              Text(clock, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
            ]),
          ),
        ),
      );

  Widget _searching() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: .5)),
        ),
        child: Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD54F))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('جاري البحث عن منافس PK عشوائي…', 'Looking for a random PK opponent…'),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => cancelRandomPk(widget.roomId),
            child: Text(tr('إلغاء', 'Cancel')),
          ),
        ]),
      );

  Widget _player(int? uid, String fallback, {required bool fire, required int score, required double avatarSize, required bool canSupport}) {
    final p = uid == null ? null : _people[uid];
    final name = (p?['name'] ?? fallback).toString().toUpperCase();
    final onMic = widget.isOnMic == null || (uid != null && widget.isOnMic!(uid));
    final color = fire ? const Color(0xFFFFD78B) : const Color(0xFF9EDFFF);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canSupport && uid != null && widget.onSupport != null
            ? () => widget.onSupport!(uid, (p?['name'] ?? fallback).toString(), p?['avatarUrl']?.toString())
            : null,
        child: _RingAvatar(url: p?['avatarUrl']?.toString(), fire: fire, size: avatarSize, framed: true),
      ),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .25), const Color(0xFF151925).withValues(alpha: .9)]),
          border: Border.all(color: Colors.white.withValues(alpha: .15)),
        ),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800))),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .25), borderRadius: BorderRadius.circular(9)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(onMic ? Icons.mic : Icons.mic_off, size: 15, color: color),
              const SizedBox(width: 3),
              Text(onMic ? tr('مفتوح', 'ON') : tr('مغلق', 'OFF'), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(width: 9),
              const Icon(Icons.headphones, size: 15, color: Colors.white),
              const SizedBox(width: 3),
              Text(_compact(score), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ])),
          ),
        ]),
      ),
    ]);
  }
}

class _VsMark extends StatelessWidget {
  const _VsMark();
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Color(0xFFFF98D5), Color(0xFFB783F5), Color(0xFF64CFFF)],
        ).createShader(r),
        child: Text('VS',
            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, height: 1)),
      );
}

/// A photo in a glowing ring: fire (orange/red) for side A, ice (cyan/blue) for B.
class _RingAvatar extends StatelessWidget {
  const _RingAvatar({required this.url, required this.fire, required this.size, this.framed = false});
  final String? url;
  final bool fire;
  final double size;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    if (framed) {
      final frameSize = size / .62;
      return SizedBox(
        width: frameSize,
        height: frameSize,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(width: size, height: size, child: CircleAvatar(
            backgroundColor: const Color(0xFF2A2F45),
            backgroundImage: (url ?? '').isNotEmpty ? appImage(url!, size) : null,
            child: (url ?? '').isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
          )),
          Image.asset(
            fire ? 'assets/images/pk/pk_ring_fire.png' : 'assets/images/pk/pk_ring_ice.png',
            width: frameSize, height: frameSize, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _RingAvatar(url: url, fire: fire, size: size),
          ),
        ]),
      );
    }
    final colors = fire
        ? const [Color(0xFFFFE082), Color(0xFFFF7A18), Color(0xFFE53935), Color(0xFFFF7A18), Color(0xFFFFE082)]
        : const [Color(0xFFE1F5FE), Color(0xFF4FC3F7), Color(0xFF1565C0), Color(0xFF4FC3F7), Color(0xFFE1F5FE)];
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: colors),
        boxShadow: [BoxShadow(color: colors[1].withValues(alpha: .7), blurRadius: 12, spreadRadius: 1)],
      ),
      child: CircleAvatar(
        backgroundColor: const Color(0xFF2A2F45),
        backgroundImage: (url ?? '').isNotEmpty ? appImage(url!, size) : null,
        child: (url ?? '').isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
      ),
    );
  }
}

/// The winner's photo in the middle of the screen with the coins under it
/// (client @376). A draw shows both players.
Future<void> showPkWinner(BuildContext context, Map d, Map<int, Map> people) {
  final w = d['winner']?.toString();
  final a = (d['scoreA'] as num?)?.toInt() ?? 0;
  final b = (d['scoreB'] as num?)?.toInt() ?? 0;
  int? id(String k) => (d[k] as num?)?.toInt();
  Map? person(int? uid) => uid == null ? null : people[uid];
  Widget winner(int? uid, int coins, bool fire) {
    final p = person(uid);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _RingAvatar(url: p?['avatarUrl']?.toString(), fire: fire, size: 120),
      const SizedBox(height: 10),
      Text((p?['name'] ?? '').toString(),
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, decoration: TextDecoration.none)),
      const SizedBox(height: 4),
      Text('🪙 ${_compact(coins)}',
          style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 20, fontWeight: FontWeight.w900, decoration: TextDecoration.none)),
    ]);
  }

  final dialog = showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'pk_winner',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 350),
    transitionBuilder: (_, anim, __, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
      child: child,
    ),
    pageBuilder: (dctx, _, __) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(w == 'TIE' ? tr('🤝 تعادل', '🤝 Draw') : tr('🏆 الفائز في PK', '🏆 PK winner'),
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          if (w == 'TIE')
            Row(mainAxisSize: MainAxisSize.min, children: [
              winner(id('sideAUserId'), a, true),
              const SizedBox(width: 24),
              winner(id('sideBUserId'), b, false),
            ])
          else
            winner(id(w == 'A' ? 'sideAUserId' : 'sideBUserId'), w == 'A' ? a : b, w == 'A'),
        ]),
      ),
    ),
  );
  // Closes itself after 5 s unless the viewer already tapped it away.
  var open = true;
  dialog.whenComplete(() => open = false);
  Timer(const Duration(seconds: 5), () {
    if (open && context.mounted) Navigator.of(context, rootNavigator: true).pop();
  });
  return dialog;
}

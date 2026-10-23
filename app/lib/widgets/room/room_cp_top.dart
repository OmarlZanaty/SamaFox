import 'dart:async';

import 'package:flutter/material.dart';

import '../../main.dart' show navigatorKey;
import '../../services/active_room.dart';
import '../../services/dio_client.dart';
import '../../services/socket_service.dart';
import '../app_network_image.dart';
import '../user_name_text.dart';
import '../../l10n/tr.dart';

/// One couple in the CP ranking (server-ordered: level, then coins, then who
/// reached the level first).
class CpTopEntry {
  CpTopEntry({
    required this.rank,
    required this.level,
    required this.levelName,
    required this.a,
    required this.b,
  });

  final int rank;
  final int level;
  final String? levelName;
  final CpTopUser a;
  final CpTopUser b;

  factory CpTopEntry.fromJson(Map<String, dynamic> j) => CpTopEntry(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 0,
        levelName: j['levelName']?.toString(),
        a: CpTopUser.fromJson(Map<String, dynamic>.from(j['userA'] as Map? ?? const {})),
        b: CpTopUser.fromJson(Map<String, dynamic>.from(j['userB'] as Map? ?? const {})),
      );
}

class CpTopUser {
  CpTopUser({required this.id, required this.name, this.avatarUrl, this.nameColor});
  final int id;
  final String name;
  final String? avatarUrl;
  final String? nameColor;
  factory CpTopUser.fromJson(Map<String, dynamic> j) => CpTopUser(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        avatarUrl: j['avatarUrl']?.toString(),
        nameColor: j['nameColor']?.toString(),
      );
}

/// SPEC52 #8 — the CP ranking at the top of the room.
///
/// Collapsed: Top 1–3 (both pictures, names, CP level) in one slim row with
/// «عرض المزيد». Tapped: the full Top 30 drops down OVER the room (it never
/// pushes the mics), and a second tap folds it back to Top 3.
class RoomCpTopStrip extends StatefulWidget {
  const RoomCpTopStrip({super.key, this.onUserTap});

  final void Function(int userId, String name, String? avatarUrl)? onUserTap;

  static const double height = 40;

  @override
  State<RoomCpTopStrip> createState() => _RoomCpTopStripState();
}

class _RoomCpTopStripState extends State<RoomCpTopStrip> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  List<CpTopEntry> _top = const [];
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.dio.get('/cp/top', queryParameters: {'limit': 30});
      final list = (res.data is Map ? res.data['data'] : null) as List? ?? const [];
      if (!mounted) return;
      setState(() => _top = list.whereType<Map>().map((e) => CpTopEntry.fromJson(Map<String, dynamic>.from(e))).toList());
    } catch (_) {/* keep the last list */}
  }

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_top.isEmpty) return const SizedBox.shrink();
    final top3 = _top.take(3).toList();
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (ctx) => _expanded(ctx),
        child: SizedBox(
          height: RoomCpTopStrip.height,
          child: Row(
            children: [
              const SizedBox(width: 6),
              const Text('CP', style: TextStyle(color: Color(0xFFFF4FA3), fontWeight: FontWeight.w900, fontSize: 12)),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    for (final e in top3) Expanded(child: _compact(e)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  margin: const EdgeInsetsDirectional.only(start: 4, end: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(_portal.isShowing ? tr('إخفاء', 'Hide') : tr('عرض المزيد', 'Show more'),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _rankColors = [Color(0xFFFFD54F), Color(0xFFCFD8DC), Color(0xFFFFAB91)];

  Widget _pairAvatars(CpTopEntry e, double r) => SizedBox(
        width: r * 3.4,
        height: r * 2,
        child: Stack(
          children: [
            Positioned(right: 0, child: _avatar(e.a, r)),
            Positioned(left: 0, child: _avatar(e.b, r)),
            Positioned(
              left: r * 1.2,
              top: r * 0.55,
              child: Text('💞', style: TextStyle(fontSize: r * 0.8)),
            ),
          ],
        ),
      );

  Widget _avatar(CpTopUser u, double r) => GestureDetector(
        onTap: widget.onUserTap == null ? null : () => widget.onUserTap!(u.id, u.name, u.avatarUrl),
        child: CircleAvatar(
          radius: r,
          backgroundColor: const Color(0xFF5E35B1),
          backgroundImage: (u.avatarUrl ?? '').isNotEmpty ? appImage(u.avatarUrl!, r * 2) : null,
          child: (u.avatarUrl ?? '').isNotEmpty ? null : Icon(Icons.person, size: r, color: Colors.white),
        ),
      );

  Widget _compact(CpTopEntry e) {
    final c = e.rank <= 3 ? _rankColors[e.rank - 1] : Colors.white70;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Text('${e.rank}', style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 11)),
          const SizedBox(width: 3),
          _pairAvatars(e, 10),
          const SizedBox(width: 3),
          Expanded(
            child: Text('LV.${e.level}',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(color: Color(0xFFFF80AB), fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext ctx) {
    final h = MediaQuery.of(ctx).size.height;
    final w = MediaQuery.of(ctx).size.width;
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomCenter,
      followerAnchor: Alignment.topCenter,
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: w - 16,
            constraints: BoxConstraints(maxHeight: h * 0.5),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: const Color(0xF0160C33),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF4FA3).withOpacity(0.4)),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                itemCount: _top.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final e = _top[i];
                  final c = e.rank <= 3 ? _rankColors[e.rank - 1] : Colors.white54;
                  return Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text('${e.rank}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c, fontWeight: FontWeight.w900)),
                      ),
                      _pairAvatars(e, 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserNameText(e.a.name,
                                nameColor: e.a.nameColor,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                            UserNameText(e.b.name,
                                nameColor: e.b.nameColor,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFF4FA3), Color(0xFF7C4DFF)]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('CP LV.${e.level}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// SPEC52 #10 — when a CP relationship is activated: only the two pictures,
/// a handshake between them and the CP level. Nothing else.
class CpActivatedPopup {
  static bool _wired = false;

  /// Listen once for `cp_activated` (server → the room and both partners).
  static void wireOnce() {
    if (_wired) return;
    _wired = true;
    SocketService().on('cp_activated', (data) {
      if (data is! Map) return;
      final roomId = (data['roomId'] as num?)?.toInt();
      final current = ActiveRoom.instance.roomId;
      final a = data['userA'] is Map ? data['userA'] as Map : const {};
      final b = data['userB'] is Map ? data['userB'] as Map : const {};
      // Shown in the room where it happened (and to the two partners).
      if (roomId != null && current != null && roomId != current) return;
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      show(ctx,
          avatarA: a['avatarUrl']?.toString(),
          avatarB: b['avatarUrl']?.toString(),
          level: (data['level'] as num?)?.toInt() ?? 1);
    });
  }

  static Future<void> show(
    BuildContext context, {
    required String? avatarA,
    required String? avatarB,
    required int level,
  }) async {
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.elasticOut,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: [Color(0xCCFF4FA3), Color(0xCC7C4DFF)]),
                boxShadow: const [BoxShadow(color: Color(0x88FF4FA3), blurRadius: 30)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _round(avatarA),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: _handshake(),
                      ),
                      _round(avatarB),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('CP LV.$level',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        decoration: TextDecoration.none,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    entry.remove();
  }

  static Widget _handshake() => Image.asset(
        'assets/images/spec52/handshake.png',
        width: 54,
        height: 54,
        errorBuilder: (_, __, ___) => const Text('🤝', style: TextStyle(fontSize: 40, decoration: TextDecoration.none)),
      );

  static Widget _round(String? url) => Container(
        width: 74,
        height: 74,
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        child: CircleAvatar(
          backgroundColor: const Color(0xFF5E35B1),
          backgroundImage: (url ?? '').isNotEmpty ? appImage(url!, 68) : null,
          child: (url ?? '').isNotEmpty ? null : const Icon(Icons.person, color: Colors.white, size: 34),
        ),
      );
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/dio_client.dart';
import '../widgets/FramedAvatar.dart';
import 'profile_screen.dart';

/// كأس الدعم — the supporters board behind the 🏆 button.
///
/// Two scopes, one screen:
///   • [roomId] null  → the whole app, top 30 supporters
///   • [roomId] set   → that room only, top 20
///
/// Layout follows the client's sketch: #1 alone on top, #2 and #3 side by side
/// under it, then #4 downwards as a ranked list.
class SupportersBoardScreen extends StatefulWidget {
  const SupportersBoardScreen({super.key, this.roomId});

  /// Room-scoped board when set; app-wide board when null.
  final int? roomId;

  @override
  State<SupportersBoardScreen> createState() => _SupportersBoardScreenState();
}

class _Supporter {
  _Supporter({
    required this.rank,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.displayId,
    required this.coins,
  });

  final int rank;
  final int userId;
  final String name;
  final String? avatarUrl;
  final int? displayId;
  final int coins;

  static _Supporter? fromJson(Map<String, dynamic> j, int fallbackRank) {
    final u = (j['user'] as Map?) ?? const {};
    final id = (u['id'] as num?)?.toInt();
    if (id == null) return null;
    return _Supporter(
      rank: (j['rank'] as num?)?.toInt() ?? fallbackRank,
      userId: id,
      name: (u['name'] ?? 'مستخدم').toString(),
      avatarUrl: (u['avatarUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : (u['avatarUrl'] as String),
      displayId: (u['displayId'] as num?)?.toInt(),
      coins: (j['coins'] as num?)?.toInt() ?? 0,
    );
  }
}

class _SupportersBoardScreenState extends State<SupportersBoardScreen> {
  static const _gold = Color(0xFFFFD700);
  static const _silver = Color(0xFFCFD8DC);
  static const _bronze = Color(0xFFCD7F32);

  late Future<List<_Supporter>> _future;

  bool get _isRoom => widget.roomId != null;
  int get _limit => _isRoom ? 20 : 30;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Supporter>> _load() async {
    final path = _isRoom ? '/gifts/leaderboard/${widget.roomId}' : '/gifts/supporters';
    final resp = await DioClient.dio.get(path, queryParameters: {'limit': _limit});
    final raw = (resp.data is Map) ? (resp.data['board'] as List? ?? const []) : const [];
    final out = <_Supporter>[];
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is! Map) continue;
      final s = _Supporter.fromJson(Map<String, dynamic>.from(e), i + 1);
      if (s != null) out.add(s);
    }
    return out;
  }

  Color _medal(int rank) => switch (rank) {
        1 => _gold,
        2 => _silver,
        3 => _bronze,
        _ => const Color(0xFF8E7CC3),
      };

  void _openProfile(int userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId, roomId: widget.roomId)),
    );
  }

  String _coins(int v) {
    // Long numbers wreck the podium, so thin them out with separators.
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0620),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A0E3E),
          elevation: 0,
          centerTitle: true,
          title: Text(
            // #28/#45 - the client asked twice for this label to read
            // "أعلى المستويات" instead of "أكبر الداعمين في البرنامج".
            // The board itself is unchanged - it is still ranked by support.
            _isRoom ? 'أعلى المستويات في الغرفة' : 'أعلى المستويات',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: () => setState(() => _future = _load()),
            ),
          ],
        ),
        body: FutureBuilder<List<_Supporter>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _gold));
            }
            if (snap.hasError) {
              final msg = snap.error is DioException
                  ? 'تعذّر تحميل الكأس — تحقق من الاتصال'
                  : 'تعذّر تحميل الكأس';
              return _message(msg, retry: true);
            }
            final board = snap.data ?? const <_Supporter>[];
            if (board.isEmpty) {
              return _message(
                _isRoom
                    ? 'لا يوجد داعمون في هذه الغرفة بعد'
                    : 'لا يوجد داعمون بعد — أول هدية تضع صاحبها على الكأس',
              );
            }

            final first = board.first;
            final second = board.length > 1 ? board[1] : null;
            final third = board.length > 2 ? board[2] : null;
            final rest = board.length > 3 ? board.sublist(3) : const <_Supporter>[];

            return RefreshIndicator(
              onRefresh: () async {
                final f = _load();
                setState(() => _future = f);
                await f;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  // ── الأول ──
                  Center(child: _podium(first, size: 108, crown: true)),
                  const SizedBox(height: 18),

                  // ── الثاني / الثالث ──
                  if (second != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Center(child: _podium(second, size: 80))),
                        Expanded(
                          child: third == null
                              ? const SizedBox.shrink()
                              : Center(child: _podium(third, size: 80)),
                        ),
                      ],
                    ),

                  if (rest.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Divider(color: Colors.white.withOpacity(0.10)),
                    const SizedBox(height: 8),
                    for (final s in rest) _row(s),
                  ],

                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      'أعلى $_limit داعم${_isRoom ? ' في الغرفة' : ''} حسب إجمالي الهدايا',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_outlined, color: Colors.white24, size: 56),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
            ),
            if (retry) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => setState(() => _future = _load()),
                child: const Text('إعادة المحاولة', style: TextStyle(color: _gold)),
              ),
            ],
          ],
        ),
      );

  Widget _podium(_Supporter s, {required double size, bool crown = false}) {
    final color = _medal(s.rank);
    return GestureDetector(
      onTap: () => _openProfile(s.userId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (crown) const Text('🏆', style: TextStyle(fontSize: 30)),
          if (crown) const SizedBox(height: 4),
          Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [color, color.withOpacity(0.55)]),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.45), blurRadius: 16)],
                ),
                child: FramedAvatar(
                  size: size,
                  avatarSize: size * 0.82,
                  imageUrl: s.avatarUrl,
                  fallbackText: s.name,
                  frame: AvatarFrame.fromType(AvatarFrameType.samafoxDefault),
                ),
              ),
              Positioned(
                bottom: -10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF0D0620), width: 2),
                  ),
                  child: Text(
                    '${s.rank}',
                    style: const TextStyle(
                        color: Color(0xFF23103F), fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: size + 40,
            child: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: crown ? 16 : 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🪙', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                _coins(s.coins),
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: crown ? 15 : 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(_Supporter s) {
    return GestureDetector(
      onTap: () => _openProfile(s.userId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0E3E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '${s.rank}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFFB9A6FF), fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(width: 8),
            FramedAvatar(
              size: 40,
              avatarSize: 34,
              imageUrl: s.avatarUrl,
              fallbackText: s.name,
              frame: AvatarFrame.fromType(AvatarFrameType.samafoxDefault),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  if (s.displayId != null)
                    Text('#${s.displayId}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Text(
              _coins(s.coins),
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

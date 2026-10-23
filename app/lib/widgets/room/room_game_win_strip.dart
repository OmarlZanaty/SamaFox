import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/dio_client.dart';
import '../../services/socket_service.dart';
import '../../l10n/tr.dart';

/// SPEC52 #39 — «🎮 محمد فاز في بوابات أوليمبوس بـ 20,000 كوينز».
///
/// Only real, committed game payouts (the server reads them from the game
/// ledger after the round is paid) of players in THIS room. Nothing is shown
/// when there is nothing real to show. A light slide, one line high.
class RoomGameWinStrip extends StatefulWidget {
  const RoomGameWinStrip({super.key, required this.roomId});
  final int roomId;

  static const double height = 22;

  @override
  State<RoomGameWinStrip> createState() => _RoomGameWinStripState();
}

class _Win {
  _Win(this.name, this.game, this.coins) : seq = ++_seqCounter;
  static int _seqCounter = 0;
  final int seq;
  final String name;
  final String game;
  final int coins;
}

class _RoomGameWinStripState extends State<RoomGameWinStrip> {
  final List<_Win> _queue = [];
  _Win? _current;
  Timer? _rotate;
  static bool _wired = false;
  static final StreamController<Map<String, dynamic>> _events = StreamController.broadcast();
  StreamSubscription<Map<String, dynamic>>? _sub;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    SocketService().on('game_win', (d) {
      if (d is Map) _events.add(Map<String, dynamic>.from(d));
    });
  }

  @override
  void initState() {
    super.initState();
    _wire();
    _sub = _events.stream.listen((d) {
      if ((d['roomId'] as num?)?.toInt() != widget.roomId) return;
      _push(_parse(d));
    });
    _loadRecent();
  }

  _Win _parse(Map d) => _Win(
        (d['name'] ?? tr('لاعب', 'Player')).toString(),
        (d['gameName'] ?? d['gameId'] ?? '').toString(),
        (d['winCoins'] as num?)?.toInt() ?? 0,
      );

  Future<void> _loadRecent() async {
    try {
      final res = await DioClient.dio.get('/games/wins/recent', queryParameters: {'roomId': widget.roomId, 'limit': 3});
      final list = (res.data is Map ? res.data['data'] : null) as List? ?? const [];
      for (final d in list.reversed) {
        if (d is Map) _push(_parse(d));
      }
    } catch (_) {}
  }

  void _push(_Win w) {
    if (!mounted || w.coins <= 0) return;
    _queue.add(w);
    while (_queue.length > 5) {
      _queue.removeAt(0);
    }
    if (_current == null) _next();
  }

  void _next() {
    _rotate?.cancel();
    if (!mounted) return;
    setState(() => _current = _queue.isEmpty ? _current : _queue.removeAt(0));
    _rotate = Timer(const Duration(seconds: 5), () {
      if (_queue.isNotEmpty) _next();
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final w = _current;
    if (w == null) return const SizedBox.shrink();
    return SizedBox(
      height: RoomGameWinStrip.height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (child, anim) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Container(
          key: ValueKey(w.seq),
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: LinearGradient(colors: [
              const Color(0xFF00C853).withOpacity(0.28),
              Colors.black.withOpacity(0.15),
            ]),
          ),
          child: Text(
            tr('🎮 ${w.name} فاز في ${w.game} بـ ${_fmt(w.coins)} كوينز', '🎮 ${w.name} won ${_fmt(w.coins)} coins in ${w.game}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

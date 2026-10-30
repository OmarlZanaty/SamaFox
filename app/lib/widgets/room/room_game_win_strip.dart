import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/dio_client.dart';
import '../../l10n/tr.dart';
import '../app_network_image.dart';
import 'room_win_announcement.dart';

class RoomGameWinStrip extends StatefulWidget {
  const RoomGameWinStrip({super.key, required this.roomId});
  final int roomId;
  static const double height = 22;
  @override
  State<RoomGameWinStrip> createState() => _RoomGameWinStripState();
}

class _RoomGameWinStripState extends State<RoomGameWinStrip>
    with SingleTickerProviderStateMixin {
  final _queue = <GameWinAnnouncement>[];
  final _seen = <String>{};
  GameWinAnnouncement? _current;
  Timer? _rotate;
  StreamSubscription<GameWinAnnouncement>? _sub;
  late final _shine =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();
  @override
  void initState() {
    super.initState();
    _sub = RoomGameWins.stream.listen((w) {
      if (w.roomId == widget.roomId) _push(w);
    });
    _loadRecent();
  }

  @override
  void didUpdateWidget(covariant RoomGameWinStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _rotate?.cancel();
      _queue.clear();
      _seen.clear();
      _current = null;
      _loadRecent();
    }
  }

  Future<void> _loadRecent() async {
    final room = widget.roomId;
    try {
      final res = await DioClient.dio.get('/games/wins/recent',
          queryParameters: {'roomId': room, 'limit': 3});
      if (!mounted || widget.roomId != room) return;
      final list =
          (res.data is Map ? res.data['data'] : null) as List? ?? const [];
      for (final d in list.reversed) {
        if (d is Map) _push(GameWinAnnouncement.fromMap(d));
      }
    } catch (_) {}
  }

  void _push(GameWinAnnouncement w) {
    if (!mounted || w.coins <= 0 || !_seen.add(w.key)) return;
    if (_seen.length > 100) _seen.remove(_seen.first);
    _queue.add(w);
    if (_queue.length > 5) _queue.removeAt(0);
    if (_current == null) _next();
  }

  void _next() {
    _rotate?.cancel();
    if (!mounted) return;
    setState(() => _current = _queue.isEmpty ? null : _queue.removeAt(0));
    if (_current != null) _rotate = Timer(const Duration(seconds: 5), _next);
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _sub?.cancel();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = _current;
    return SizedBox(
        height: RoomGameWinStrip.height,
        child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: w == null
                ? const SizedBox.shrink()
                : GestureDetector(
                    key: ValueKey(w.key),
                    onTap: () => showGameWinnerCard(context, w),
                    child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: const Color(0xFFFFDB81)),
                            gradient: const LinearGradient(colors: [
                              Color(0xFF080909),
                              Color(0xFF584015),
                              Color(0xFF171006)
                            ]),
                            boxShadow: const [
                              BoxShadow(color: Color(0x665B410B), blurRadius: 6)
                            ]),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedBuilder(
                              animation: _shine,
                              builder: (context, child) => CustomPaint(
                                  foregroundPainter: _RoyalShine(_shine.value),
                                  child: child),
                              child: Container(
                                  margin: const EdgeInsets.all(2),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 5),
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0xFF977237),
                                          width: .5)),
                                  child: Row(
                                      textDirection: TextDirection.rtl,
                                      children: [
                                        SizedBox(
                                            width: 21,
                                            child: Stack(
                                                clipBehavior: Clip.none,
                                                alignment:
                                                    Alignment.bottomCenter,
                                                children: [
                                                  ClipOval(
                                                      child: w.avatar
                                                                  ?.isNotEmpty ==
                                                              true
                                                          ? AppNetworkImage(
                                                              w.avatar!,
                                                              width: 12,
                                                              height: 12,
                                                              fit: BoxFit.cover)
                                                          : const Icon(
                                                              Icons.person,
                                                              color: Color(
                                                                  0xFFFFDB81),
                                                              size: 12)),
                                                  const Positioned(
                                                      top: -5,
                                                      child: Text('♛',
                                                          style: TextStyle(
                                                              color: Color(
                                                                  0xFFFFDE86),
                                                              fontSize: 12,
                                                              height: 1))),
                                                ])),
                                        const SizedBox(width: 3),
                                        Expanded(
                                            child: Text(
                                                tr('${w.name} ربح في ${w.game}',
                                                    '${w.name} won in ${w.game}'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Color(0xFFFFEBC4),
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w700))),
                                        const SizedBox(width: 4),
                                        if (w.icon?.isNotEmpty == true)
                                          AppNetworkImage(w.icon!,
                                              width: 13, height: 13)
                                        else
                                          const Icon(Icons.casino,
                                              size: 13,
                                              color: Color(0xFFFFD67A)),
                                        const SizedBox(width: 5),
                                        Flexible(
                                            child: FittedBox(
                                                child: ShaderMask(
                                                    blendMode: BlendMode.srcIn,
                                                    shaderCallback: (r) =>
                                                        const LinearGradient(
                                                            colors: [
                                                              Color(0xFFFFF5CA),
                                                              Color(0xFFE9B344),
                                                              Color(0xFFFFE6A3)
                                                            ]).createShader(r),
                                                    child: Text(
                                                        '🪙 +${w.coins}',
                                                        textDirection:
                                                            TextDirection.ltr,
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w900))))),
                                      ])),
                            ))))));
  }
}

class _RoyalShine extends CustomPainter {
  _RoyalShine(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final x = (size.width + 70) * progress - 70;
    final rect = Rect.fromLTWH(x, 0, 50, size.height);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(colors: [
            Colors.transparent,
            Color(0x44FFF0B6),
            Colors.transparent
          ]).createShader(rect));
    for (var i = 0; i < 9; i++) {
      final opacity = (.15 + .25 * math.sin(progress * math.pi * 2 + i).abs());
      final p = Offset(size.width * ((i * .137 + .08) % 1),
          3 + (i % 3) * (size.height - 6) / 3);
      final paint = Paint()
        ..color = const Color(0xFFFFE1A0).withOpacity(opacity)
        ..strokeWidth = .7;
      canvas.drawLine(
          p - const Offset(1.5, 0), p + const Offset(1.5, 0), paint);
      canvas.drawLine(
          p - const Offset(0, 1.5), p + const Offset(0, 1.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoyalShine oldDelegate) =>
      oldDelegate.progress != progress;
}

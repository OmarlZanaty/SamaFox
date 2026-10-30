import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../widgets/app_network_image.dart';
import '../models/gift.dart';
import '../services/gift_socket_service.dart';

class LuckyWinBanner extends StatefulWidget {
  const LuckyWinBanner(
      {super.key,
      required this.socket,
      required this.roomId,
      required this.myUserId,
      this.onMyWin});
  final GiftSocketService socket;
  final int roomId;
  final int? myUserId;
  final VoidCallback? onMyWin;
  @override
  State<LuckyWinBanner> createState() => _LuckyWinBannerState();
}

class _Streak {
  LuckyRollEvent? win;
  int sends = 0, rolls = 0, coins = 0, revision = 0;
  DateTime touched = DateTime.now();
  int get count => math.max(sends, rolls);
}

class _LuckyWinBannerState extends State<LuckyWinBanner> {
  final _streaks = <String, _Streak>{};
  final _seen = <String>{};
  StreamSubscription<LuckyRollEvent>? _wins;
  StreamSubscription<GiftSendEvent>? _sends;
  Timer? _expiry;
  String _key(int sender, String? name, String? icon) =>
      '$sender:${name ?? icon ?? "lucky"}';
  bool _first(String id) {
    if (!_seen.add(id)) return false;
    if (_seen.length > 500) _seen.remove(_seen.first);
    return true;
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _wins = widget.socket.luckyWinStream.listen(_onWin);
    _sends = widget.socket.sentStream.listen(_onSend);
    _expiry = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_streaks.values.any(
          (s) => DateTime.now().difference(s.touched).inMilliseconds >= 4000)) {
        setState(() => _streaks.removeWhere((_, s) =>
            DateTime.now().difference(s.touched).inMilliseconds >= 4000));
      }
    });
  }

  @override
  void didUpdateWidget(covariant LuckyWinBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.socket != widget.socket ||
        oldWidget.roomId != widget.roomId) {
      _wins?.cancel();
      _sends?.cancel();
      _expiry?.cancel();
      _streaks.clear();
      _seen.clear();
      _listen();
    }
  }

  _Streak _touch(String key) {
    final old = _streaks[key];
    final s = old == null ||
            DateTime.now().difference(old.touched).inMilliseconds >= 4000
        ? (_streaks[key] = _Streak())
        : old;
    s.touched = DateTime.now();
    s.revision++;
    // Bound even non-winning send bookkeeping.
    if (_streaks.length > 100) {
      final oldest = _streaks.keys.firstWhere(
          (k) => k != key && _streaks[k]!.coins == 0,
          orElse: () => _streaks.keys.first);
      _streaks.remove(oldest);
    }
    return s;
  }

  void _onSend(GiftSendEvent e) {
    if (!mounted ||
        e.roomId != widget.roomId ||
        !e.gift.isLucky ||
        !_first('send:${e.transactionId}')) return;
    setState(() {
      final s = _touch(
          _key(e.senderId, e.gift.nameAr ?? e.gift.name, e.gift.iconUrl));
      s.sends += math.max(1, e.quantity);
    });
  }

  void _onWin(LuckyRollEvent e) {
    if (!mounted ||
        !_first(e.rollId > 0
            ? 'roll:${e.rollId}'
            : 'roll:${e.senderId}:${e.ts.millisecondsSinceEpoch}:${e.payoutCoins}'))
      return;
    if (e.payoutCoins > 0 && e.senderId == widget.myUserId)
      widget.onMyWin?.call();
    if (e.roomId != null && e.roomId != widget.roomId) return;
    setState(() {
      final s = _touch(_key(e.senderId, e.giftName, e.giftIconUrl));
      s.rolls++;
      if (e.payoutCoins > 0) {
        s.win = e;
        s.coins += e.payoutCoins;
      }
    });
  }

  @override
  void dispose() {
    _wins?.cancel();
    _sends?.cancel();
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _streaks.entries.where((e) => e.value.coins > 0).toList()
      ..sort((a, b) => b.value.coins.compareTo(a.value.coins));
    return IgnorePointer(
        child: Align(
            alignment: const Alignment(0, -.18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 2; i++)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: i >= visible.length
                      ? SizedBox.shrink(key: ValueKey('empty$i'))
                      : _LuckyBar(
                          key: ValueKey(visible[i].key),
                          streak: visible[i].value),
                ),
            ])));
  }
}

class _LuckyBar extends StatelessWidget {
  const _LuckyBar({super.key, required this.streak});
  final _Streak streak;
  @override
  Widget build(BuildContext context) {
    final e = streak.win!;
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        constraints: const BoxConstraints(maxWidth: 420),
        child: CustomPaint(
            painter: _GoldWings(),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xFF390817),
                    Color(0xFFA31535),
                    Color(0xFF4B091B)
                  ]),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFFFD678), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x996B001A), blurRadius: 9),
                    BoxShadow(color: Color(0xFF9C631C), offset: Offset(0, 2))
                  ]),
              child: Row(textDirection: TextDirection.rtl, children: [
                Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFD678))),
                    child: ClipOval(
                        child: e.senderAvatarUrl?.isNotEmpty == true
                            ? AppNetworkImage(e.senderAvatarUrl!,
                                width: 34, height: 34, fit: BoxFit.cover)
                            : const Icon(Icons.person,
                                size: 34, color: Colors.white70))),
                const SizedBox(width: 6),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(e.senderName ?? tr('مستخدم', 'User'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      Text(e.giftName ?? tr('الهدية المحظوظة', 'Lucky gift'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFFFD6DD), fontSize: 10)),
                    ])),
                const SizedBox(width: 6),
                Flexible(
                    child: FittedBox(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, a) => ScaleTransition(
                          scale: Tween<double>(begin: .8, end: 1).animate(a),
                          child: FadeTransition(opacity: a, child: child)),
                      child: ShaderMask(
                          key: ValueKey(streak.count),
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFFFFFCD),
                                    Color(0xFFFFCB43),
                                    Color(0xFFB36C12)
                                  ]).createShader(r),
                          child: Text('${streak.count}x',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic)))),
                  if (e.giftIconUrl?.isNotEmpty == true)
                    AppNetworkImage(e.giftIconUrl!, width: 26, height: 26),
                ]))),
                const SizedBox(width: 6),
                Flexible(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 7),
                        decoration: BoxDecoration(
                            color: const Color(0xFF60279C),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE5B45F))),
                        child: FittedBox(
                            child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Text('🪙 +${streak.coins}',
                                    key: ValueKey(streak.coins),
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                        color: Color(0xFFFFE59B),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15)))))),
              ]),
            )));
  }
}

class _GoldWings extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader =
          const LinearGradient(colors: [Color(0xFFFFEAAA), Color(0xFFAA6518)])
              .createShader(Offset.zero & size);
    for (final flip in [false, true]) {
      canvas.save();
      if (flip) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }
      for (var i = 0; i < 3; i++) {
        final y = size.height / 2 - 12 + i * 7;
        canvas.drawPath(
            Path()
              ..moveTo(15, y + 5)
              ..lineTo(0, y - 4)
              ..lineTo(5, y + 8)
              ..lineTo(16, y + 12)
              ..close(),
            paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GoldWings oldDelegate) => false;
}

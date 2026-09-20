import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/app_network_image.dart';
import '../models/gift.dart';
import '../services/gift_repository.dart';
import '../services/gift_socket_service.dart';
import 'lucky_winner_card.dart';

/// هدايا الحظ — the app-wide ticker along the bottom of the room.
///
/// Client spec: *"شريط تحت … بالشخص اللي كسب وعدد أضعاف مكسبه، وده شريط لكل
/// الناس اللي بتلعب حظ في البرنامج، ولو ضغطت عليه يظهر صفحة صاحب الشريط"*.
///
/// Fed by `lucky_broadcast` (every win at or above the admin's threshold,
/// from any room) and primed from `/gifts/lucky/recent` so a room that has
/// just opened is not blank. Cycles through the most recent wins; a tap opens
/// [showLuckyWinnerCard]. Hidden entirely when there is nothing to show.
class LuckyTicker extends StatefulWidget {
  const LuckyTicker({
    super.key,
    required this.socket,
    required this.repository,
    this.myUserId,
  });

  final GiftSocketService socket;
  final GiftRepository repository;
  final int? myUserId;

  @override
  State<LuckyTicker> createState() => _LuckyTickerState();
}

const int _kKeep = 12;
const Duration _kRotate = Duration(seconds: 4);

class _LuckyTickerState extends State<LuckyTicker> {
  final List<LuckyRollEvent> _items = [];
  StreamSubscription<LuckyRollEvent>? _sub;
  Timer? _rotate;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.luckyBroadcastStream.listen(_push);
    _prime();
    _rotate = Timer.periodic(_kRotate, (_) {
      if (!mounted || _items.length < 2) return;
      setState(() => _index = (_index + 1) % _items.length);
    });
  }

  Future<void> _prime() async {
    final recent = await widget.repository.luckyRecent();
    if (!mounted || recent.isEmpty) return;
    setState(() {
      for (final e in recent.reversed) {
        if (_items.any((x) => x.rollId == e.rollId)) continue;
        _items.insert(0, e);
      }
      while (_items.length > _kKeep) _items.removeLast();
      _index = 0;
    });
  }

  void _push(LuckyRollEvent e) {
    if (!mounted || !e.won) return;
    setState(() {
      _items.removeWhere((x) => x.rollId == e.rollId);
      _items.insert(0, e);
      while (_items.length > _kKeep) _items.removeLast();
      _index = 0; // a fresh win jumps to the front
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rotate?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final e = _items[_index.clamp(0, _items.length - 1)];
    final tint = e.multiplier >= 100
        ? const Color(0xFFFF3D71)
        : e.multiplier >= 20
            ? const Color(0xFFFFB300)
            : const Color(0xFF7C4DFF);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GestureDetector(
        onTap: () => showLuckyWinnerCard(context, e, myUserId: widget.myUserId),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.15, 0), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey(e.rollId),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: tint.withOpacity(0.7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎲', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                ClipOval(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: (e.senderAvatarUrl == null || e.senderAvatarUrl!.isEmpty)
                        ? Container(color: Colors.white24)
                        : AppNetworkImage(e.senderAvatarUrl!, width: 20, height: 20, fit: BoxFit.cover, cacheWidth: 48),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${e.senderName ?? 'مستخدم'} كسب ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '×${e.multiplier}',
                  style: TextStyle(color: tint, fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 6),
                Text(
                  '${e.payoutCoins} 🪙',
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

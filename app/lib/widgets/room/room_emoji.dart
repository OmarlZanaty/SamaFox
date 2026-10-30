import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../services/socket_service.dart';
import 'emoji/game_emoji.dart';

class RoomEmojiDef {
  const RoomEmojiDef(this.id, this.label, this.glyph);
  final String id;
  final String label;
  final String glyph;
  bool get isGame => id == 'dice' || id == 'slot';
  String get asset => 'assets/images/emoji/$id.webp';
}

class RoomEmojiCategory {
  const RoomEmojiCategory(this.id, this.icon, this.label, this.emojis);
  final String id;
  final String icon;
  final String label;
  final List<RoomEmojiDef> emojis;
}

/// SPEC52 #20 — seat emoji. Stickers ship with the app
/// (`assets/images/emoji/<id>.webp`); ids must match the server allow-list.
List<RoomEmojiCategory> get kRoomEmojis {
  final stickers = <RoomEmojiDef>[
  RoomEmojiDef('kiss_right', tr('قبلة يمين', "Kiss right"), '😘'),
  RoomEmojiDef('kiss_left', tr('قبلة شمال', "Kiss left"), '😘'),
  RoomEmojiDef('magnifier', tr('نظارة مكبرة', "Magnifying glasses"), '🧐'),
  RoomEmojiDef('yawn_sleep', tr('تثاؤب ونوم', "Yawn and sleep"), '🥱'),
  RoomEmojiDef('heartbroken', tr('قلب مكسور', "Broken heart"), '💔'),
  RoomEmojiDef('clap', tr('تصفيق', "Clap"), '👏'),
  RoomEmojiDef('cry', tr('بكاء', "Cry"), '😭'),
  RoomEmojiDef('laugh', tr('ضحك', "Laugh"), '😂'),
  RoomEmojiDef('hello_sign', tr('لافتة مرحبا', "Hello sign"), '👋'),
  RoomEmojiDef('heart', tr('قلب', "Heart"), '❤️'),
  RoomEmojiDef('dance', tr('رقص', "Dance"), '💃'),
  RoomEmojiDef('bride_groom', tr('عروس وعريس', "Bride and groom"), '👰'),
  RoomEmojiDef('hug', tr('حضن', "Hug"), '🤗'),
  RoomEmojiDef('couple_kiss', tr('قبلة', "Kiss"), '💏'),
  RoomEmojiDef('spit_right', tr('بصق يمين', "Spit right"), '💦'),
  RoomEmojiDef('spit_left', tr('بصق شمال', "Spit left"), '💦'),
  RoomEmojiDef('wow', tr('واو', 'Wow'), '😮'),
  RoomEmojiDef('angry', tr('غضب', "Angry"), '😡'),
  RoomEmojiDef('shock', tr('صدمة', "Shocked"), '😱'),
  RoomEmojiDef('fire_heart', tr('قلب مشتعل', "Heart on fire"), '❤️‍🔥'),
  RoomEmojiDef('lol', tr('ضحك قوي', "Big laugh"), '🤣'),
  RoomEmojiDef('sleep', tr('نوم', "Sleep"), '😴'),
  RoomEmojiDef('party', tr('احتفال', "Party"), '🥳'),
  RoomEmojiDef('fire_clap', tr('تصفيق ناري', "Fiery clap"), '🔥'),
  RoomEmojiDef('stars', tr('نجوم', "Stars"), '🤩'),
  RoomEmojiDef('crown', tr('تاج', "Crown"), '👑'),
  ];
  List<RoomEmojiDef> group(List<String> ids) =>
      [for (final id in ids) stickers.firstWhere((e) => e.id == id)];
  return [
    RoomEmojiCategory('faces', '😀', tr('وجوه', 'Faces'), group([
      'magnifier', 'yawn_sleep', 'cry', 'laugh', 'wow', 'angry', 'shock', 'lol', 'sleep', 'stars',
    ])),
    RoomEmojiCategory('love', '❤️', tr('حب', 'Love'), group([
      'kiss_right', 'kiss_left', 'heartbroken', 'heart', 'bride_groom', 'hug', 'couple_kiss', 'fire_heart',
    ])),
    RoomEmojiCategory('reactions', '👏', tr('تفاعل', 'Reactions'), group([
      'clap', 'hello_sign', 'dance', 'spit_right', 'spit_left', 'party', 'fire_clap', 'crown',
    ])),
    RoomEmojiCategory('games', '🎲', tr('ألعاب', 'Games'), [
      RoomEmojiDef('dice', tr('نرد', 'Dice'), '🎲'),
      RoomEmojiDef('slot', tr('اختارني', 'Pick me'), '🎰'),
    ]),
  ];
}

RoomEmojiDef? roomEmojiById(String id) {
  for (final category in kRoomEmojis) {
    for (final emoji in category.emojis) {
      if (emoji.id == id) return emoji;
    }
  }
  return null;
}

Widget roomEmojiArt(RoomEmojiDef e, double size, {int? result, double? rollPhase}) {
  if (e.isGame) return GameEmoji(id: e.id, size: size, result: result, rollPhase: rollPhase);
  return Image.asset(e.asset, width: size, height: size, fit: BoxFit.contain,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) => SizedBox(width: size, height: size,
      child: FittedBox(child: Text(e.glyph,
        style: const TextStyle(decoration: TextDecoration.none)))),
  );
}

class RoomEmojiPicker {
  static String _category = 'faces';
  static double? _keyboardHeight;
  static Future<void> show(BuildContext context, {required void Function(RoomEmojiDef) onPick}) {
    final media = MediaQuery.of(context);
    if (media.viewInsets.bottom > 0) _keyboardHeight = media.viewInsets.bottom;
    final height = (_keyboardHeight ?? 320.0).clamp(0.0, media.size.height * .65).toDouble();
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF160C33),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
        final categories = kRoomEmojis;
        final selected = categories.firstWhere((c) => c.id == _category);
        return SizedBox(height: height, child: SafeArea(top: false,
          child: Column(children: [
            Row(children: [for (final category in categories)
              Expanded(child: Semantics(selected: category.id == _category,
                child: InkWell(
                  onTap: () => update(() => _category = category.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(
                      color: category.id == _category ? Colors.amber : Colors.transparent, width: 3))),
                    child: Column(children: [
                      Text(category.icon, style: const TextStyle(fontSize: 25)),
                      Text(category.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ]),
                  ),
                ),
              )),
            ]),
            Expanded(child: GridView.builder(
              key: ValueKey(selected.id),
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .9),
              itemCount: selected.emojis.length,
              itemBuilder: (_, i) {
                final emoji = selected.emojis[i];
                return InkWell(borderRadius: BorderRadius.circular(12),
                  onTap: () => onPick(emoji),
                  child: Column(children: [
                    Expanded(child: FittedBox(child: roomEmojiArt(emoji, 76))),
                    Text(emoji.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                );
              },
            )),
          ]),
        ));
      }),
    );
  }
}

class RoomEmojiEvent {
  RoomEmojiEvent(this.def, this.seatId, this.senderId, this.result, this.route);
  final RoomEmojiDef def;
  final int seatId;
  final int senderId;
  final int? result;
  final ModalRoute<dynamic>? route;
}

final roomEmojiEvents = StreamController<RoomEmojiEvent>.broadcast();

/// Nonvisual compatibility bridge for the existing room-screen call site.
/// Rendering belongs to seats; resolveSeat is no longer used for placement.
class RoomEmojiLayer extends StatefulWidget {
  const RoomEmojiLayer({super.key, required this.roomId, required this.resolveSeat});
  final int roomId;
  final Offset Function(int seatNumber) resolveSeat;
  @override
  State<RoomEmojiLayer> createState() => _RoomEmojiLayerState();
}

class _RoomEmojiLayerState extends State<RoomEmojiLayer> {
  ModalRoute<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    SocketService().on('room_emoji', _receive);
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }
  void _receive(dynamic data) {
    if (!mounted || data is! Map || data['roomId'] != widget.roomId) return;
    final def = roomEmojiById('${data['emojiId']}');
    final seat = data['seatId'];
    final sender = data['senderId'];
    final result = data['result'];
    if (def == null || seat is! int || sender is! int) return;
    if (def.isGame && (result is! int ||
        (def.id == 'dice' ? result < 1 || result > 6 : result < 0 || result > 2))) return;
    roomEmojiEvents.add(RoomEmojiEvent(def, seat, sender, def.isGame ? result as int : null, _route));
  }
  @override
  void dispose() {
    SocketService().off('room_emoji', _receive);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

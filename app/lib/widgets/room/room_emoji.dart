import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../l10n/tr.dart';
import '../../services/dio_client.dart';
import '../../services/socket_service.dart';
import 'emoji/game_emoji.dart';

class RoomEmojiDef {
  const RoomEmojiDef(this.id, this.label, this.glyph, {this.imageUrl});
  final String id;
  final String label;
  final String glyph;
  /// Set for an emoji the admin uploaded from the dashboard (id `c:<n>`).
  final String? imageUrl;
  bool get isGame => id == 'dice' || id == 'slot';
  String get asset => 'assets/images/emoji/$id.webp';
}

/// Dashboard uploads may be site-relative; they are served from the server root.
String roomEmojiImageUrl(String raw) {
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  final base = AppConfig.socketUrl.replaceFirst(RegExp(r'/+$'), '');
  return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
}

/// Client 31/10 — the emoji lists the admin manages from the dashboard. The
/// server only returns the lists this user may open (public, his VIP level,
/// or his ID), and checks again on every send.
class RoomCustomEmoji {
  static List<RoomEmojiCategory> _lists = const [];
  static DateTime? _loadedAt;
  static Future<void>? _loading;

  static List<RoomEmojiCategory> get lists => _lists;

  static Future<void> load({bool force = false}) {
    final fresh = _loadedAt != null && DateTime.now().difference(_loadedAt!) < const Duration(minutes: 1);
    if (fresh && !force) return Future.value();
    return _loading ??= _fetch().whenComplete(() => _loading = null);
  }

  static Future<void> _fetch() async {
    try {
      final res = await DioClient.dio.get('/emoji/lists');
      final data = res.data is Map ? res.data['data'] : null;
      if (data is! List) return;
      _lists = parse(data);
      _loadedAt = DateTime.now();
    } catch (_) {
      // Offline or an older server: keep what we had; the built-ins still work.
    }
  }

  static List<RoomEmojiCategory> parse(List<dynamic> data) => [
        for (final l in data.whereType<Map>())
          RoomEmojiCategory(
            'c:list:${l['id']}',
            '',
            '${l['nameAr'] ?? ''}',
            [
              for (final e in (l['emojis'] as List? ?? const []).whereType<Map>())
                if (e['id'] is int && e['imageUrl'] is String)
                  RoomEmojiDef('c:${e['id']}', '${e['name'] ?? ''}', '', imageUrl: e['imageUrl'] as String),
            ],
            imageUrl: l['imageUrl'] as String?,
          ),
      ];

  @visibleForTesting
  static void debugSet(List<RoomEmojiCategory> lists) {
    _lists = lists;
    _loadedAt = DateTime.now();
  }
}

class RoomEmojiCategory {
  const RoomEmojiCategory(this.id, this.icon, this.label, this.emojis, {this.imageUrl});
  final String id;
  final String icon;
  final String label;
  final List<RoomEmojiDef> emojis;
  final String? imageUrl;
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
  final url = e.imageUrl;
  if (url != null) {
    // An animated GIF / WebP keeps playing.
    return Image(
      image: CachedNetworkImageProvider(roomEmojiImageUrl(url)),
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
  return Image.asset(e.asset, width: size, height: size, fit: BoxFit.contain,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) => SizedBox(width: size, height: size,
      child: FittedBox(child: Text(e.glyph,
        style: const TextStyle(decoration: TextDecoration.none)))),
  );
}

class RoomEmojiPicker {
  static String _category = ''; // '' = the first tab (a dashboard list when there is one)
  static double? _keyboardHeight;
  static Future<void> show(BuildContext context, {required void Function(RoomEmojiDef) onPick}) async {
    await RoomCustomEmoji.load().timeout(const Duration(seconds: 3), onTimeout: () {});
    if (!context.mounted) return;
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
        // Dashboard lists first, then the built-in stickers.
        final categories = [...RoomCustomEmoji.lists, ...kRoomEmojis];
        final selected = categories.firstWhere((c) => c.id == _category, orElse: () => categories.first);
        return SizedBox(height: height, child: SafeArea(top: false,
          child: Column(children: [
            // The tabs scroll sideways once the dashboard adds many lists.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final category in categories)
                Semantics(selected: category.id == selected.id,
                  child: InkWell(
                    onTap: () => update(() => _category = category.id),
                    child: Container(
                      width: media.size.width / categories.length.clamp(1, 5),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(
                        color: category.id == selected.id ? Colors.amber : Colors.transparent, width: 3))),
                      child: Column(children: [
                        SizedBox(height: 30, child: _tabIcon(category)),
                        Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
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

Widget _tabIcon(RoomEmojiCategory category) {
  final image = category.imageUrl;
  if (image != null && image.isNotEmpty) {
    return Image(image: CachedNetworkImageProvider(roomEmojiImageUrl(image)), width: 30, height: 30,
      fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions, color: Colors.amber));
  }
  if (category.icon.isNotEmpty) return Text(category.icon, style: const TextStyle(fontSize: 25));
  return category.emojis.isEmpty
      ? const Icon(Icons.emoji_emotions, color: Colors.amber)
      : roomEmojiArt(category.emojis.first, 30);
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
    final id = '${data['emojiId']}';
    final image = data['imageUrl'];
    // A dashboard emoji travels with its picture, so everyone in the room sees
    // it even when the list is closed to them.
    final def = id.startsWith('c:')
        ? (image is String && image.isNotEmpty ? RoomEmojiDef(id, '${data['name'] ?? ''}', '', imageUrl: image) : null)
        : roomEmojiById(id);
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

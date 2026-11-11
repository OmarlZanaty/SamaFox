import '../../gifts/models/gift.dart';
import '../../gifts/services/gift_socket_service.dart';
import '../../gifts/widgets/lucky_ticker.dart';
import 'room_win_announcement.dart';
import '../../l10n/tr.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../user_name_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/room_controller_provider.dart';
import '../../models/room_event.dart';
import '../../services/socket_service.dart';
import '../../services/dio_client.dart';
import '../../providers/auth_provider.dart';
import '../../screens/profile_screen.dart';
import '../../utils/image_intrinsic_size.dart';
import 'TopWaveClipper.dart';
import '../../widgets/app_network_image.dart';
import '../product_video_layer.dart';

// ==========================
// 🔥 NEW: merged feed model
// ==========================
class RoomFeedItem {
  final bool isMessage;
  final SocketMessage? message;
  final RoomEvent? event;
  final LuckyRollEvent? lucky;
  final GameWinAnnouncement? game;
  final DateTime? receivedAt;
  int get timestamp =>
      message?.timestamp ??
      event?.at.millisecondsSinceEpoch ??
      receivedAt!.millisecondsSinceEpoch;
  String get key => lucky != null
      ? 'lucky:${lucky!.rollId}:${lucky!.senderId}'
      : game?.key ??
          (isMessage
              ? 'message:${message!.userId}:${message!.timestamp}:${message!.message}'
              : 'event:${event!.at}:${event!.userId}:${event!.text}');
  RoomFeedItem.win({this.lucky, this.game})
      : isMessage = false,
        message = null,
        event = null,
        receivedAt = DateTime.now();

  RoomFeedItem.message(this.message)
      : isMessage = true,
        event = null,
        lucky = null,
        game = null,
        receivedAt = null;

  RoomFeedItem.event(this.event)
      : isMessage = false,
        message = null,
        lucky = null,
        game = null,
        receivedAt = null;
}

class RoomChatPanel extends ConsumerStatefulWidget {
  final int roomId;
  final GiftSocketService? giftSocket;

  /// Opens the room's own profile card for a chat writer. Supplied by
  /// RoomScreen — the card belongs to the room, so tapping a name must not
  /// navigate away from it.
  /// A20 — the writer's standing travels WITH the tap. The room's profile card
  /// used to synthesise a blank seat for anyone who was not sitting on one, so
  /// a chat-only user opened as "LV 0", no VIP chip, and the internal id. The
  /// message already carries all three.
  final void Function(
    int userId,
    String username, {
    int? level,
    int? vipLevel,
    int? displayId,
    String? avatarUrl,
  })? onUserTap;

  /// Shown between the tabs and the messages — the هدايا الحظ winners ticker.
  /// It used to float over the bottom bar and cover the message input
  /// ("شريط هدايا الحظ ... مغطى على ارسال الرسالة", 29/09).
  final Widget? header;
  final GlobalKey? effectsViewportKey;
  final VoidCallback? onEffectsLayout;

  /// SPEC52 #31 — sits at the far end of the tabs row, just above the
  /// messages: the agency notifications bell.
  final Widget? tabsTrailing;

  const RoomChatPanel({
    super.key,
    required this.roomId,
    this.onUserTap,
    this.header,
    this.effectsViewportKey,
    this.onEffectsLayout,
    this.tabsTrailing,
    this.giftSocket,
  });

  @override
  ConsumerState<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends ConsumerState<RoomChatPanel> {
  /// Default chat-bubble artwork and its 9-slice guides, in source pixels.
  /// Everything outside the slice rect is an end-cap and never stretches, so
  /// the bubble padding below has to clear those caps.
  static const String _bubbleAsset = 'assets/images/chat_bubble.png';
  static const Rect _bubbleSlice = Rect.fromLTRB(30, 13, 118, 23);

  final _text = TextEditingController();
  final _scroll = ScrollController();

  final _wins = <RoomFeedItem>[];
  StreamSubscription<LuckyRollEvent>? _luckySub;
  StreamSubscription<GameWinAnnouncement>? _gameSub;
  GiftSocketService? _ownedGiftSocket;
  bool _atNewest = true;
  int _unread = 0;
  Set<String> _knownFeed = {};
  final _rowKeys = <String, GlobalKey>{};
  final _viewportKey = GlobalKey();
  bool _restoring = false;
  GiftSocketService? get _providedSocket =>
      widget.giftSocket ??
      (widget.header is LuckyTicker
          ? (widget.header as LuckyTicker).socket
          : null);
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _subscribeWins();
  }

  void _subscribeWins() {
    final socket = _providedSocket ??
        (_ownedGiftSocket = GiftSocketService(SocketService())..bind());
    _luckySub = socket.luckyBroadcastStream.listen((e) {
      if (e.payoutCoins > 0) _addWin(RoomFeedItem.win(lucky: e));
    });
    _gameSub =
        RoomGameWins.stream.listen((e) => _addWin(RoomFeedItem.win(game: e)));
  }

  void _addWin(RoomFeedItem item) {
    if (!mounted || _wins.any((w) => w.key == item.key)) return;
    setState(() {
      _wins.add(item);
      if (_wins.length > 30) _wins.removeAt(0);
    });
  }

  @override
  void didUpdateWidget(covariant RoomChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSocket = oldWidget.giftSocket ??
        (oldWidget.header is LuckyTicker
            ? (oldWidget.header as LuckyTicker).socket
            : null);
    if (oldWidget.roomId != widget.roomId || oldSocket != _providedSocket) {
      _luckySub?.cancel();
      _gameSub?.cancel();
      _ownedGiftSocket?.dispose();
      _ownedGiftSocket = null;
      _wins.clear();
      _knownFeed.clear();
      _rowKeys.clear();
      _atNewest = true;
      _unread = 0;
      _subscribeWins();
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _restoring) return;
    final near = _scroll.position.extentAfter <= 40;
    if (near != _atNewest || (near && _unread > 0)) {
      setState(() {
        _atNewest = near;
        if (near) _unread = 0;
      });
    }
  }

  void _jumpToNewest() {
    setState(() {
      _atNewest = true;
      _unread = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients)
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Widget _roleIcon(int? id, int ownerId, List<int> admins) {
    final owner = id != null && id == ownerId;
    if (!owner && !admins.contains(id)) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: owner ? Colors.orange : Colors.green),
            child: Icon(owner ? Icons.home_rounded : Icons.person,
                size: 11, color: Colors.white)));
  }

  Timer? _typingTimer;
  bool _isTyping = false;

  // ✅ Filter index
  int _filterIndex = 0; // 0: الكل, 1: الهدايا, 2: الدردشة

  @override
  void dispose() {
    _luckySub?.cancel();
    _gameSub?.cancel();
    _ownedGiftSocket?.dispose();
    _scroll.removeListener(_onScroll);
    _typingTimer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sendTyping(bool typing) {
    ref
        .read(roomControllerProvider(widget.roomId).notifier)
        .sendTyping(isTyping: typing);
  }

  void _onTextChanged(String v) {
    final nowTyping = v.trim().isNotEmpty;
    if (nowTyping != _isTyping) {
      _isTyping = nowTyping;
      _sendTyping(_isTyping);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        _sendTyping(false);
      }
    });
  }

  void _send() {
    final msg = _text.text.trim();
    if (msg.isEmpty) return;

    ref
        .read(roomControllerProvider(widget.roomId).notifier)
        .sendRoomMessage(message: msg);

    _text.clear();
    _onTextChanged('');
  }

  /// The app's own padding for the bundled bubble — clears its gold end-caps.
  /// Also the floor for a custom design whose inner box the dashboard hasn't
  /// been told about yet, so nothing regresses for existing products.
  static const EdgeInsets _defaultBubblePadding =
      EdgeInsets.symmetric(horizontal: 26, vertical: 12);

  /// Group 12: chat-bubble styling. A custom design (store/dashboard item)
  /// wins; otherwise the bubble is tiered by the sender's level.
  ///
  /// 2026-08-23 — custom designs are 9-SLICED like the bundled one instead of
  /// being stretched whole (`BoxFit.fill`). A decorated bubble's border used to
  /// smear as the message grew, and the text sat on top of it; now only the
  /// slice centre stretches and the writing is confined to the inner box the
  /// dashboard configured. Nothing here decides how tall the bubble is — the
  /// Container wraps its child, so 1, 2 or 5 lines each get a bubble that grew
  /// to fit ("وكبر مع كبر الكلام بالطول والعرض").
  /// D5 — a bought VIDEO bubble used to be handed to NetworkImage, fail, and
  /// render as no decoration at all: the buyer wore nothing. A clip cannot be
  /// a DecorationImage and has no 9-slice — there is no flat middle to stretch
  /// — so it goes behind the text instead, clipped to the bubble's own radius
  /// and sized by the bubble, which is still sized by the message.
  Widget _bubbleSkin(SocketMessage m, Widget bubble) {
    final url = (m.bubbleUrl ?? '').trim();
    if (!isProductVideoUrl(url)) return bubble;
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ProductVideoLayer(url: url, fit: BoxFit.cover),
          ),
        ),
        bubble,
      ],
    );
  }

  BoxDecoration _bubbleDecoration(SocketMessage m) {
    final url = (m.bubbleUrl ?? '').trim();
    // Video is drawn by _bubbleSkin, behind this.
    if (isProductVideoUrl(url)) return const BoxDecoration();
    if (url.isNotEmpty) {
      // `centerSlice` is in the SOURCE image's pixels. This used to be handed
      // the BUNDLED artwork's 148x36, so an uploaded bubble of any other size
      // was sliced in the wrong place and its decoration smeared. The real
      // size is resolved once per URL and cached; until it arrives the slice
      // is skipped, which is exactly the pre-existing plain-stretch look.
      final intrinsic = _intrinsicBubbleSize(url);
      final slice =
          intrinsic == null ? null : m.bubbleLayout.centerSlice(intrinsic);
      return BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        image: DecorationImage(
          image: CachedNetworkImageProvider(url),
          // No slice configured → previous behaviour, so an un-migrated
          // product keeps rendering exactly as it did.
          centerSlice: slice,
          fit: BoxFit.fill,
          onError: (_, __) {},
        ),
      );
    }

    // Default bubble artwork. The source is 148x36 with its flat middle
    // between x 30..118 and y 13..23; 9-slicing there keeps the gold end-caps
    // undistorted no matter how long the message is.
    return const BoxDecoration(
      image: DecorationImage(
        image: AssetImage(_bubbleAsset),
        centerSlice: _bubbleSlice,
        fit: BoxFit.fill,
      ),
    );
  }

  /// Source-pixel size of a custom bubble's artwork, or null while it is still
  /// being resolved. Triggers exactly one resolve per URL and repaints when it
  /// lands.
  Size? _intrinsicBubbleSize(String url) {
    final known = ImageIntrinsicSize.peek(url);
    if (known != null) return known;
    ImageIntrinsicSize.resolve(url).then((size) {
      if (size != null && mounted) setState(() {});
    });
    return null;
  }

  static double _maxBubbleWidth(BuildContext context) =>
      MediaQuery.of(context).size.width * 0.85;

  /// Reference box the fractional inner insets resolve against.
  ///
  /// The bubble's real size depends on the padding, which depends on the
  /// bubble's size — so it is measured against the WIDEST a bubble may get
  /// instead. That errs towards a slightly roomier inner box on short
  /// messages, which is the safe direction: the text can only end up further
  /// inside the artwork, never spilling over its decoration.
  static Size _bubbleReference(BuildContext context) {
    final w = _maxBubbleWidth(context);
    return Size(w, w * 0.3);
  }

  /// Padding that keeps the writing inside the bubble's empty middle.
  EdgeInsets _bubblePadding(SocketMessage m, Size rendered) {
    if ((m.bubbleUrl ?? '').trim().isEmpty) return _defaultBubblePadding;
    final p = m.bubbleLayout.padding(rendered, _defaultBubblePadding);
    // Never tighter than the bundled padding: a mis-set 0.01 inset would put
    // the text hard against the edge.
    return EdgeInsets.only(
      left: p.left < _defaultBubblePadding.left
          ? _defaultBubblePadding.left
          : p.left,
      top:
          p.top < _defaultBubblePadding.top ? _defaultBubblePadding.top : p.top,
      right: p.right < _defaultBubblePadding.right
          ? _defaultBubblePadding.right
          : p.right,
      bottom: p.bottom < _defaultBubblePadding.bottom
          ? _defaultBubblePadding.bottom
          : p.bottom,
    );
  }

  /// Room-admin call shared by the chat user sheet. Sends both camelCase and
  /// snake_case ids because the older endpoints accept either spelling.
  Future<void> _roomAdminAction(
    String path,
    int userId,
    String okText, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await DioClient.dio.post(path, data: {
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'userId': userId,
        'user_id': userId,
        ...extra,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okText)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('فشلت العملية: $e', "Action failed: $e"))));
      }
    }
  }

  /// Opens the writer's card. Prefers the room's own profile dialog (same one
  /// the seats use, so the admin controls are right there); falls back to the
  /// full profile screen only if this panel was mounted without the callback.
  void _openImage(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: InteractiveViewer(
          child: Center(child: AppNetworkImage(url, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  void _openProfile(int userId, String username, {SocketMessage? from}) {
    if (userId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('تعذّر فتح الملف الشخصي لهذا المستخدم',
                "Could not open this user's profile"))),
      );
      return;
    }
    final open = widget.onUserTap;
    if (open != null) {
      open(
        userId,
        username,
        level: from?.level,
        vipLevel: from?.vipLevel,
        displayId: from?.displayId,
        avatarUrl: from?.avatar,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId, roomId: widget.roomId),
      ),
    );
  }

  /// #13: tap a chat message (anywhere on the bubble, not just the tiny name)
  /// → the writer's profile + admin moderation, even before they take a mic.
  void _showChatUserActions(int userId, String username) {
    final st = ref.read(roomControllerProvider(widget.roomId));
    final myId = ref.read(authStateProvider).user?.id;
    final isAdmin =
        myId != null && (myId == st.ownerId || st.adminIds.contains(myId));
    if (userId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('تعذّر فتح الملف الشخصي لهذا المستخدم',
                "Could not open this user's profile"))),
      );
      return;
    }
    final isSelf = myId == userId;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(username,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.person, color: Colors.white),
                title: Text(tr('الملف الشخصي', "Profile"),
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sctx);
                  _openProfile(userId, username);
                },
              ),
              if (isAdmin && !isSelf) ...[
                ListTile(
                  leading:
                      const Icon(Icons.mic_off, color: Colors.orangeAccent),
                  title: Text(tr('منع من صعود المايك', "Ban from mic"),
                      style: TextStyle(color: Colors.orangeAccent)),
                  onTap: () {
                    Navigator.pop(sctx);
                    _roomAdminAction(
                        'room-admin/seat-block',
                        userId,
                        tr('تم منع $username من صعود المايك',
                            "$username banned from mic"),
                        extra: {'blocked': true});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: Text(tr('طرد من الغرفة', "Kick from room"),
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(sctx);
                    _roomAdminAction(
                        'room-admin/kick',
                        userId,
                        tr('تم طرد $username من الغرفة',
                            "$username kicked from room"),
                        extra: {'minutes': 0});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: Text(tr('حظر من الغرفة', "Ban from room"),
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(sctx);
                    _roomAdminAction(
                        'room-admin/ban',
                        userId,
                        tr('تم حظر $username من الغرفة',
                            "$username banned from room"));
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Small VIP / LV pill next to a name.
  static Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.7)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w800),
        ),
      );

  /// One achievement icon. Never let a broken url punch a hole in a message.
  static Widget _badgeIcon(String url) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: AppNetworkImage(
          url,
          width: 18,
          height: 18,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEffectsLayout?.call();
    });
    final st = ref.watch(roomControllerProvider(widget.roomId));

    final messages = st.messages;
    final events = st.events
        .where((event) =>
            event.type == RoomEventType.gift ||
            event.type == RoomEventType.join)
        .toList();

    // ==========================
    // 🔥 MERGE CHAT + ACTIVITY
    // ==========================
    final allFeed = <RoomFeedItem>[
      ...messages.map((m) => RoomFeedItem.message(m)),
      ...events.map((e) => RoomFeedItem.event(e)),
      ..._wins,
    ];

    // ==========================
    // 🔥 SORT BY TIME
    // ==========================
    allFeed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // ✅ APPLY FILTERING
    final incomingFeed = allFeed.where((item) {
      if (_filterIndex == 0) return true; // الكل
      if (_filterIndex == 1)
        return !item.isMessage &&
            item.event?.type == RoomEventType.gift; // الهدايا
      if (_filterIndex == 2) return item.isMessage; // الدردشة
      return true;
    }).toList();

    final keys = incomingFeed.map((item) => item.key).toSet();
    final added = keys.difference(_knownFeed).length;
    final removed = _knownFeed.difference(keys).isNotEmpty;
    _knownFeed = keys;
    GlobalKey? anchor;
    double? anchorY;
    if (!_atNewest && (removed || added > 0)) {
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (viewport is RenderBox && viewport.hasSize) {
        final top = viewport.localToGlobal(Offset.zero).dy;
        for (final entry in _rowKeys.entries) {
          if (!keys.contains(entry.key)) continue;
          final box = entry.value.currentContext?.findRenderObject();
          if (box is RenderBox && box.hasSize) {
            final y = box.localToGlobal(Offset.zero).dy;
            if (y + box.size.height > top &&
                y < top + viewport.size.height &&
                (anchorY == null || y < anchorY)) {
              anchor = entry.value;
              anchorY = y;
            }
          }
        }
      }
    }
    _rowKeys.removeWhere((key, _) => !keys.contains(key));
    if (_atNewest) {
      _unread = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _atNewest && _scroll.hasClients)
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } else {
      _unread += added;
      if (anchor != null) {
        _restoring = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final box = anchor!.currentContext?.findRenderObject();
          if (!_atNewest &&
              _scroll.hasClients &&
              box is RenderBox &&
              box.hasSize) {
            final delta = box.localToGlobal(Offset.zero).dy - anchorY!;
            final position = _scroll.position;
            _scroll.jumpTo((position.pixels + delta)
                .clamp(position.minScrollExtent, position.maxScrollExtent)
                .toDouble());
          }
          _restoring = false;
        });
      }
    }
    final feed = incomingFeed;

    return Align(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: const BoxDecoration(
          color: Colors.transparent, // 🔥 important
        ),
        child: Column(
          children: [
            // Plain text filters directly below the microphone area.
            _buildFilterTabs(),

            const SizedBox(height: 4),

            if (widget.header != null &&
                (widget.header is! LuckyTicker || _filterIndex == 0))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: widget.header,
                ),
              ),

            // ==========================
            // 🔥 ONE LIST (CHAT + EVENTS)
            // ==========================
            Expanded(
              key: widget.effectsViewportKey,
              child: Stack(key: _viewportKey, children: [
                Positioned.fill(
                    child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: ListView.builder(
                          controller: _scroll,
                          reverse: false, // ✅ NORMAL TOP → DOWN
                          padding: const EdgeInsets.only(bottom: 20),
                          itemCount: feed.length,
                          findChildIndexCallback: (key) {
                            final index = feed.indexWhere(
                                (item) => _rowKeys[item.key] == key);
                            return index < 0 ? null : index;
                          },
                          itemBuilder: (_, i) {
                            final item = feed[i]; // ✅ NORMAL ORDER
                            return KeyedSubtree(
                                key: _rowKeys.putIfAbsent(
                                    item.key, () => GlobalKey()),
                                child: Builder(builder: (_) {
                                  if (item.lucky != null || item.game != null) {
                                    return RoomWinAnnouncement(
                                        key: ValueKey(item.key),
                                        lucky: item.lucky,
                                        game: item.game,
                                        myUserId: ref
                                            .read(authStateProvider)
                                            .user
                                            ?.id);
                                  }

                                  // ===== CHAT =====
                                  if (item.isMessage) {
                                    final m = item.message!;

                                    final time =
                                        DateTime.fromMillisecondsSinceEpoch(
                                            m.timestamp);
                                    final timeStr =
                                        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: TweenAnimationBuilder(
                                        duration:
                                            const Duration(milliseconds: 350),
                                        tween: Tween(
                                            begin: 60.0,
                                            end: 0.0), // 👈 slide from RIGHT
                                        builder: (context, value, child) {
                                          return Transform.translate(
                                            offset: Offset(value, 0),
                                            child: Opacity(
                                              opacity: 1 - (value / 60),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Align(
                                          alignment: Alignment
                                              .centerRight, // ✅ RIGHT SIDE
                                          child: Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            // #13: the whole bubble opens the writer's card —
                                            // the 11px name alone was too small to hit.
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              // Whole bubble opens the same card as the
                                              // name — one behaviour, and the 11px name was
                                              // too small a target on its own.
                                              onTap: () => _openProfile(
                                                  m.userId, m.username,
                                                  from: m),
                                              onLongPress: () =>
                                                  _showChatUserActions(
                                                      m.userId, m.username),
                                              child: Stack(
                                                children: [
                                                  // 💬 BUBBLE — custom design if the sender
                                                  // activated one, otherwise tiered by level.
                                                  _bubbleSkin(
                                                      m,
                                                      Container(
                                                        constraints: BoxConstraints(
                                                            maxWidth:
                                                                _maxBubbleWidth(
                                                                    context)),
                                                        // Confined to the artwork's empty middle.
                                                        padding: _bubblePadding(
                                                            m,
                                                            _bubbleReference(
                                                                context)),
                                                        decoration:
                                                            _bubbleDecoration(
                                                                m),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .end,
                                                          children: [
                                                            // Tapping the NAME goes straight to the
                                                            // writer's page (with the room's
                                                            // kick/mute controls on it) — the
                                                            // menu was an extra step in the way
                                                            // of "من ده؟ اطرده". The rest of the
                                                            // bubble still opens the quick menu.
                                                            GestureDetector(
                                                              behavior:
                                                                  HitTestBehavior
                                                                      .opaque,
                                                              onTap: () =>
                                                                  _openProfile(
                                                                      m.userId,
                                                                      m.username,
                                                                      from: m),
                                                              child: Padding(
                                                                // Bigger touch target: 11px text
                                                                // was near impossible to hit.
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                        vertical:
                                                                            4),
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Flexible(
                                                                      child:
                                                                          UserNameText(
                                                                        m.username,
                                                                        nameColor:
                                                                            m.nameColor,
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style:
                                                                            const TextStyle(
                                                                          color:
                                                                              Color(0xFFFFD54F),
                                                                          fontSize:
                                                                              13,
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                          decoration:
                                                                              TextDecoration.underline,
                                                                          decorationColor:
                                                                              Color(0x66FFD54F),
                                                                        ),
                                                                        textAlign:
                                                                            TextAlign.right,
                                                                      ),
                                                                    ),
                                                                    _roleIcon(
                                                                        m.userId,
                                                                        st.ownerId,
                                                                        st.adminIds),
                                                                    // "فهد  VIP 6 · LV 8" — the
                                                                    // writer's standing sits with
                                                                    // his name, above the text.
                                                                    if (m.vipLevel >
                                                                        0) ...[
                                                                      const SizedBox(
                                                                          width:
                                                                              6),
                                                                      _chip(
                                                                          'VIP ${m.vipLevel}',
                                                                          const Color(
                                                                              0xFFFFB300)),
                                                                    ],
                                                                    const SizedBox(
                                                                        width:
                                                                            5),
                                                                    _chip(
                                                                        'LV ${m.level}',
                                                                        const Color(
                                                                            0xFF7C4DFF)),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                            // شارات المستخدم — under the name,
                                                            // before what he wrote.
                                                            if (m.badges
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                  height: 3),
                                                              Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  for (final b
                                                                      in m
                                                                          .badges)
                                                                    _badgeIcon(
                                                                        b),
                                                                ],
                                                              ),
                                                            ],
                                                            const SizedBox(
                                                                height: 2),
                                                            if (m.isImage)
                                                              // صور في شات الروم — a thumbnail in
                                                              // the bubble; tap for full size.
                                                              GestureDetector(
                                                                onTap: () =>
                                                                    _openImage(m
                                                                        .imageUrl!),
                                                                child:
                                                                    ClipRRect(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              10),
                                                                  child:
                                                                      ConstrainedBox(
                                                                    constraints: const BoxConstraints(
                                                                        maxWidth:
                                                                            200,
                                                                        maxHeight:
                                                                            200),
                                                                    child:
                                                                        AppNetworkImage(
                                                                      m.imageUrl!,
                                                                      fit: BoxFit
                                                                          .cover,
                                                                      cacheWidth:
                                                                          480,
                                                                    ),
                                                                  ),
                                                                ),
                                                              )
                                                            else
                                                              Text(
                                                                m.message,
                                                                style:
                                                                    const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 17,
                                                                ),
                                                                textAlign:
                                                                    TextAlign
                                                                        .right,
                                                              ),
                                                            const SizedBox(
                                                                height: 4),
                                                            Text(
                                                              timeStr,
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white38,
                                                                fontSize: 12,
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                            ),
                                                          ],
                                                        ),
                                                      )),

                                                  // 🔻 RTL TAIL
                                                  Positioned(
                                                    right: -6,
                                                    bottom: 6,
                                                    child: CustomPaint(
                                                      size: const Size(16, 16),
                                                      painter:
                                                          _BubbleTailPainter(),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  // ===== ACTIVITY ITEM =====
                                  final e = item.event!;
                                  final username = (e.username == null ||
                                          e.username!.trim().isEmpty)
                                      ? tr('مستخدم', "User")
                                      : e.username!.trim();
                                  final icon = e.type == RoomEventType.join
                                      ? Icons.login_rounded
                                      : Icons.card_giftcard_rounded;
                                  // "فهد VIP 6 · LV 8 دخل الغرفة" — the entrant's standing
                                  // belongs on the line, not just his name.
                                  final standing = [
                                    if ((e.vipLevel ?? 0) > 0)
                                      'VIP ${e.vipLevel}',
                                    if ((e.level ?? 0) > 0) 'LV ${e.level}',
                                  ].join(' · ');
                                  final line = standing.isEmpty
                                      ? '$username ${e.text}'
                                      : '$username  $standing  ${e.text}';

                                  // Gift and join lines open the same card as a chat
                                  // bubble — the tap has to work under كل تبويب: الكل,
                                  // الهدايا and الدردشة, not only on messages.
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 6),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: e.userId == null
                                          ? null
                                          : () =>
                                              _openProfile(e.userId!, username),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                        // Join lines: the client's purple plate with a gold frame
                                        // (ref 3/11 22:07; 10/11 20:03 «ده حلو اوي حطه عندنا»).
                                        decoration: e.type == RoomEventType.join
                                            ? _joinPlate
                                            : BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF1a4a1a),
                                              Color(0xFF2d7a2d),
                                              Color(0xFF1a4a1a)
                                            ],
                                            begin: Alignment.centerRight,
                                            end: Alignment.centerLeft,
                                          ),
                                          border: Border.all(
                                              color: const Color(0xFF4caf50),
                                              width: 1.5),
                                          borderRadius:
                                              BorderRadius.circular(28),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (e.type == RoomEventType.join) _joinGem else Icon(icon, color: Colors.white, size: 18),
                                            _roleIcon(e.userId, st.ownerId,
                                                st.adminIds),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                line,
                                                style: TextStyle(
                                                  color: e.type == RoomEventType.join ? const Color(0xFFFFF3D6) : Colors.white,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            // شارات الداخل، بعد السطر.
                                            for (final b in e.badges)
                                              _badgeIcon(b),
                                            if (e.type == RoomEventType.join) ...[const SizedBox(width: 6), _joinGem],
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }));
                          },
                        ))),
                if (_unread > 0)
                  Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Center(
                          child: ActionChip(
                              backgroundColor: const Color(0xFF512885),
                              label: Text(
                                  tr('رسائل جديدة ↓ ($_unread)',
                                      'New messages ↓ ($_unread)'),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11)),
                              onPressed: _jumpToNewest))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Filter tabs: plain text, like the room reference under the mics.
  // SPEC52 #27 — compact segmented pill (~26px) so the tabs never push into
  // or cover the mics on small phones.
  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tabItem(0, tr("الكل", "All")),
                _tabItem(1, tr("هدية", "Gift")),
                _tabItem(2, tr("دردشة", "Chat")),
              ],
            ),
          ),
          const Spacer(),
          if (widget.tabsTrailing != null) widget.tabsTrailing!,
        ],
      ),
    );
  }

  Widget _tabItem(int index, String label) {
    final isSelected = _filterIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _filterIndex = index;
        _atNewest = true;
        _unread = 0;
        _knownFeed.clear();
      }),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)])
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.66),
            fontSize: 11.5,
            height: 1.0,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.deepPurple.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// شريط دخول الغرفة — purple plate, gold frame (client reference 3/11 22:07).
const BoxDecoration _joinPlate = BoxDecoration(
  gradient: LinearGradient(
    colors: [Color(0xFF2A0D52), Color(0xFF6A2DB8), Color(0xFF2A0D52)],
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
  ),
  border: Border.fromBorderSide(BorderSide(color: Color(0xFFE9C46A), width: 1.8)),
  borderRadius: BorderRadius.all(Radius.circular(10)),
  boxShadow: [BoxShadow(color: Color(0x88E9C46A), blurRadius: 8)],
);

const Widget _joinGem = Text('\u25C6', style: TextStyle(color: Color(0xFFE9C46A), fontSize: 12));

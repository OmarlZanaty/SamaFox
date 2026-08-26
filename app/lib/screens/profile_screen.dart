import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/screens/edit_profile_screen.dart';
import 'package:samafox/screens/chat_screen.dart';
import 'package:samafox/screens/room_screen.dart';
import 'package:samafox/services/follow_service.dart';
import 'package:samafox/services/user_account_service.dart';
import 'package:samafox/screens/feature_screens.dart';
import 'package:samafox/screens/store_screen.dart';
import '../models/InventoryItem.dart';
import '../providers/auth_provider.dart';
import '../providers/room_controller_provider.dart';
import '../models/user.dart';
import '../services/dio_client.dart';
import '../services/store_service.dart';
import '../utils/storage_service.dart';
import '../widgets/FramedAvatar.dart';
import '../services/level_catalog_service.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_background.dart';
import '../widgets/profile_decor_frame.dart';
import '../config/app_config.dart';
import '../repositories/cp_repository.dart';
import 'cp_list_screen.dart';
import '../widgets/vip_buy_sheet.dart';
import '../widgets/glass_bottom_bar.dart';
import '../widgets/video_preview_widget.dart';
import '../services/socket_service.dart';
import '../config/app_config.dart';
import 'home_screen.dart';

/// Model for Received Gift
class ReceivedGift {
  final int id;
  final String name;
  final String imageUrl;
  final int count;
  final String? senderName;

  ReceivedGift({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.count,
    this.senderName,
  });

  factory ReceivedGift.fromJson(Map<String, dynamic> json) {
    return ReceivedGift(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      imageUrl: json['image_url'] ?? json['image'] ?? '',
      count: json['count'] ?? 1,
      senderName: json['sender_name'],
    );
  }
}

/// Profile Screen - Redesigned with responsive layout and all requested features
class ProfileScreen extends ConsumerStatefulWidget {
  final int? userId; // null = show my own profile

  /// Set when the profile was opened FROM a room (a chat name, a seat). It
  /// carries the room's moderation actions onto the page, so an owner/admin can
  /// look at whoever is writing and kick or mute them right there — before they
  /// ever reach a mic.
  final int? roomId;

  const ProfileScreen({super.key, this.userId, this.roomId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with WidgetsBindingObserver {

  late final StoreService _service = StoreService();
  Timer? _coinsRefreshTimer;
  String selectedType = "seat_effect";
  InventoryItem? activeFrame;

  // Gifts state
  List<ReceivedGift> _receivedGifts = [];
  bool _loadingGifts = true;

  // #29 follow state (other-user profile action bar)
  String _followStatus = 'none'; // none | pending | following
  bool _followBusy = false;
  bool _followLoaded = false; // guard: load follow status only once per viewed user
  bool _targetBlocked = false; // #2 blacklist: whether I blocked the viewed user
  bool _blockBusy = false;

  // #28: badges row cache, keyed by userId so switching profiles refetches once.
  int? _badgesUserId;
  Future<List<Map<String, dynamic>>>? _badgesFuture;

  Future<List<Map<String, dynamic>>> _fetchBadges(int userId) async {
    try {
      final res = await DioClient.dio.get('/users/$userId/badges');
      final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fixed on-screen size for every badge in the row, whatever the uploaded
  /// artwork's pixel dimensions are.
  static const double _kBadgeSize = 26;

  IconData _badgeIconFor(String type) {
    switch (type) {
      case 'FRAME':
      case 'PROFILE_FRAME':
        return Icons.filter_frames;
      case 'ENTRANCE_EFFECT':
      case 'ENTRANCE_BANNER':
        return Icons.auto_awesome;
      case 'ROOM_THEME':
        return Icons.wallpaper;
      default:
        return Icons.military_tech;
    }
  }

  Widget _buildBadgesRow(int userId) {
    if (_badgesUserId != userId) {
      _badgesUserId = userId;
      _badgesFuture = _fetchBadges(userId);
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _badgesFuture,
      builder: (context, snapshot) {
        final badges = snapshot.data ?? const [];
        if (badges.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: badges.map((b) {
              final iconUrl = LevelCatalogService.absoluteBadgeUrl(
                (b['iconUrl'] ?? '').toString(),
              );
              // The dashboard artwork is authoritative, but it is uploaded at
              // whatever size the admin had (often huge). Every badge is drawn
              // inside the SAME square box with BoxFit.contain, so a 1024px PNG
              // and a 64px PNG end up identical on screen — the client's
              // "تظهر في التطبيق صغيرة" requirement.
              final Widget child = iconUrl == null
                  ? Icon(_badgeIconFor((b['type'] ?? '').toString()),
                      size: 16, color: const Color(0xFFDCC8FF))
                  : Image.network(
                      iconUrl,
                      width: _kBadgeSize,
                      height: _kBadgeSize,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => Icon(
                          _badgeIconFor((b['type'] ?? '').toString()),
                          size: 16,
                          color: const Color(0xFFDCC8FF)),
                    );
              return Tooltip(
                message: (b['name'] ?? '').toString(),
                child: iconUrl != null
                    ? SizedBox(
                        width: _kBadgeSize, height: _kBadgeSize, child: child)
                    : Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9C6BFF).withOpacity(0.18),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: const Color(0xFF9C6BFF).withOpacity(0.5)),
                        ),
                        child: child,
                      ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
  Future<User?>? _otherUserFuture; // cached so build() doesn't re-fetch every frame
  int? _otherUserFutureId;

  Future<User?> _otherUserFor(int userId) {
    if (_otherUserFutureId != userId || _otherUserFuture == null) {
      _otherUserFutureId = userId;
      _followLoaded = false;
      _followStatus = 'none';
      _otherUserFuture = _fetchUserById(userId);
    }
    return _otherUserFuture!;
  }

  Future<void> _loadFollowStatus(int userId) async {
    try {
      final s = await FollowService.getFollowStatus(userId);
      if (mounted) setState(() => _followStatus = s);
    } catch (_) {}
    try {
      final blocked = await UserAccountService.isBlocked(userId);
      if (mounted) setState(() => _targetBlocked = blocked);
    } catch (_) {}
  }

  /// Block/unblock the profile being viewed. This existed but was never wired
  /// to anything, so there was no way to block a user from inside the app —
  /// the blacklist screen could only unblock and so stayed empty.
  Future<void> _toggleBlock(int userId, String name) async {
    if (_blockBusy) return;

    if (!_targetBlocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A0E3E),
            title: const Text('حظر المستخدم', style: TextStyle(color: Colors.white)),
            content: Text(
              'لن يتمكن $name من مراسلتك، ولن تتمكن من مراسلته. يمكنك فك الحظر في أي وقت.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('حظر', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _blockBusy = true);
    try {
      if (_targetBlocked) {
        await UserAccountService.unblock(userId);
      } else {
        await UserAccountService.block(userId);
      }
      if (!mounted) return;
      setState(() => _targetBlocked = !_targetBlocked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_targetBlocked ? 'تم حظر المستخدم' : 'تم إلغاء الحظر')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تنفيذ العملية: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  Future<void> _toggleFollow(int userId) async {
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      if (_followStatus == 'following' || _followStatus == 'pending') {
        await FollowService.unfollow(userId);
        _followStatus = 'none';
      } else {
        await FollowService.sendFollowRequest(userId);
        _followStatus = 'following';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تنفيذ المتابعة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  /// Room moderation, shown only when this profile was opened from a room
  /// ([ProfileScreen.roomId]) and the viewer runs that room. It is the whole
  /// point of opening a writer's card from the chat: look at who is talking and
  /// remove him BEFORE he takes a mic.
  Widget? _buildRoomModerationBar(User user) {
    final roomId = widget.roomId;
    if (roomId == null) return null;
    final myId = ref.read(authStateProvider).user?.id;
    if (myId == null || myId == user.id) return null;
    final st = ref.watch(roomControllerProvider(roomId));
    final isAdmin = myId == st.ownerId || st.adminIds.contains(myId);
    if (!isAdmin) return null;

    Future<void> act(String path, String okText, {Map<String, dynamic> extra = const {}}) async {
      try {
        // Both spellings — the older room-admin endpoints accept either.
        await DioClient.dio.post(path, data: {
          'roomId': roomId,
          'room_id': roomId,
          'userId': user.id,
          'user_id': user.id,
          ...extra,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okText)));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشلت العملية: $e')));
      }
    }

    Widget btn(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.6)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 3),
                  Text(label,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('إدارة الغرفة',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              btn(Icons.mic_off, 'منع المايك', const Color(0xFFFFA726),
                  () => act('room-admin/seat-block', 'تم منع ${user.name} من صعود المايك',
                      extra: {'blocked': true})),
              btn(Icons.logout, 'طرد', const Color(0xFFFF7043),
                  () => act('room-admin/kick', 'تم طرد ${user.name} من الغرفة',
                      extra: {'minutes': 0})),
              btn(Icons.block, 'حظر', const Color(0xFFEF5350),
                  () => act('room-admin/ban', 'تم حظر ${user.name} من الغرفة')),
            ],
          ),
        ],
      ),
    );
  }

  /// #29: bottom action bar shown on another user's profile — room / message /
  /// follow / block.
  Widget _buildOtherUserActionBar(User user) {
    final following = _followStatus == 'following' || _followStatus == 'pending';
    Widget btn(IconData icon, String label, Color color, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn(Icons.meeting_room, 'غرفة', const Color(0xFF9C6BFF), () {
          // Own room first: this button means "their room", so it must not drop
          // us into whatever room they happen to be visiting as a guest, and it
          // must still work while they're offline. liveRoomId is only a fallback
          // for users who own no room but are currently in one.
          final targetRoomId = user.ownedRoomId ?? user.liveRoomId;
          if (targetRoomId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RoomScreen(roomId: targetRoomId)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لا توجد غرفة لهذا المستخدم')),
            );
          }
        }),
        btn(Icons.chat_bubble, 'رسالة', const Color(0xFF4F9BFF), () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                partnerId: user.id,
                partnerName: user.name,
                partnerAvatarUrl: user.avatarUrl,
              ),
            ),
          );
        }),
        btn(
          following ? Icons.check_circle : Icons.person_add,
          following ? 'متابَع' : 'متابعة',
          const Color(0xFFFFB74D),
          () => _toggleFollow(user.id),
        ),
        btn(
          _targetBlocked ? Icons.lock_open : Icons.block,
          _targetBlocked ? 'فك الحظر' : 'حظر',
          const Color(0xFFFF6B6B),
          () => _toggleBlock(user.id, user.name),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    loadInventory();
    _refreshCoins();
    _fetchReceivedGifts();
    _loadMyTarget();

    _coinsRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
          (_) => _refreshCoins(),
    );
  }

  Future<void> _refreshCoins() async {
    await ref.read(authStateProvider.notifier).refreshUser();
  }

  // #13: the user's own target (earned vs goal) as a host. null until loaded /
  // when the user has no target (not a host in any hosting agency).
  Map<String, dynamic>? _myTarget;

  /// True only for a hosting-agency member (مضيف) or an agency owner (وكيل);
  /// the server decides, so the rule lives in one place.
  bool get _hasTarget => _myTarget != null && _myTarget!['hasTarget'] == true;

  Future<void> _loadMyTarget() async {
    try {
      final token = await StorageService.getAccessToken();
      if (token == null) return;
      final resp = await DioClient.dio.get(
        '/agencies/my-target',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = (resp.data is Map) ? resp.data['data'] : null;
      // The card shows for every user now — with an agency goal when one is
      // set, and as a plain gift-earnings total when there isn't one.
      if (mounted && data is Map) {
        setState(() => _myTarget = Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // No target / older server — just don't show the card.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCoins();
    }
  }

  @override
  void dispose() {
    _coinsRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _applyAvatarFrame(InventoryItem item) {
    setState(() {
      activeFrame = item;
    });
  }

  bool isVideo(String url) {
    return url.toLowerCase().endsWith('.mp4') ||
        url.toLowerCase().endsWith('.mov');
  }

  Future<void> _confirmAndLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A1A5E),
          title: const Text(
            'تسجل الخروج',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'هل متاكد انك تريد تسجيل الخروج ؟',
            style: TextStyle(color: Colors.white.withOpacity(0.85)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await ref.read(authStateProvider.notifier).logout();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  List<InventoryItem> items = [];
  bool loading = true;
  bool activating = false;

  Future<void> loadInventory({bool force = false}) async {
    try {
      if (items.isNotEmpty && !force) return;

      final token = await StorageService.getAccessToken();
      final data = await _service.getInventory(token!);

      if (!mounted) return;

      InventoryItem? found;
      try {
        found = data.firstWhere(
              (e) => (e.type == "avatar_frame" || e.type == "FRAME") && e.isActive,
        );
      } catch (_) {}

      setState(() {
        items = data;
        loading = false;
        activeFrame = found;
      });

    } catch (e) {
      debugPrint("INVENTORY ERROR: $e");
    }
  }

  Future<void> activateItem(String productId) async {
    if (activating) return;

    setState(() => activating = true);

    try {
      final token = await StorageService.getAccessToken();

      final activatedItem = items.firstWhere(
            (e) => e.id == productId,
      );

      if (activatedItem.type == "avatar_frame" || activatedItem.type == "FRAME") {
        // Frames must go through activate-frame so User.activeFrameId +
        // avatarFrameUrl are set — that's what the ROOM SEAT reads. Calling only
        // /store/activate left the seat blank while the profile showed the frame.
        await _service.activateItem(token!, activatedItem.id);
        // activate-frame matches on the ITEM id (productId on the client).
        await _service.activateFrame(
          token,
          activatedItem.productId.isNotEmpty ? activatedItem.productId : activatedItem.id,
        );
      } else {
        await _service.activateItem(token!, activatedItem.id);
      }

      if (activatedItem.type == "seat_effect") {
        await SocketService().waitUntilConnected();
        SocketService().sendSeatEffect({
          "video": activatedItem.fileUrl,
        });
      }
      else if (activatedItem.type == "avatar_frame" || activatedItem.type == "FRAME") {
        setState(() {
          activeFrame = activatedItem;
        });
      }
      else if (_isProfilePageItem(activatedItem.type)) {
        // The page paints its background and decoration from the USER row, not
        // from the inventory, so it has to be re-read before the change shows.
        await ref.read(authStateProvider.notifier).refreshMe();
      }

      await loadInventory(force: true);

    } catch (e) {
      debugPrint(e.toString());
    }

    setState(() => activating = false);
  }

  /// Items whose equipped state is mirrored onto the user row (خلفية الصفحة
  /// الشخصية / إطار تزيين الصفحة الشخصية) and therefore need a user refresh
  /// before the profile page reflects them.
  static bool _isProfilePageItem(String type) =>
      type == 'profile_background' || type == 'profile_decor';

  /// Un-use (deactivate) an in-use product so it's no longer equipped.
  Future<void> deactivateItem(InventoryItem item) async {
    if (activating) return;
    setState(() => activating = true);
    try {
      final token = await StorageService.getAccessToken();
      if (item.type == "avatar_frame" || item.type == "FRAME") {
        await _service.deactivateFrame(token!);
        setState(() => activeFrame = null);
      } else if (item.type == "seat_effect") {
        await _service.deactivateItem(token!, item.id);
        await SocketService().waitUntilConnected();
        SocketService().sendSeatEffect({"video": ""});
      } else {
        // Only this item — deactivateAll used to strip the vehicle and frame
        // too, so taking off an entrance banner unequipped everything.
        await _service.deactivateItem(token!, item.id);
        if (_isProfilePageItem(item.type)) {
          await ref.read(authStateProvider.notifier).refreshMe();
        }
      }
      await loadInventory(force: true);
    } catch (e) {
      debugPrint("DEACTIVATE ERROR: $e");
    }
    setState(() => activating = false);
  }

  /// Fetch received gifts from backend
  Future<void> _fetchReceivedGifts() async {
    try {
      final token = await StorageService.getAccessToken();
      if (token == null) return;

      final targetId = widget.userId ?? ref.read(authStateProvider).user?.id;
      if (targetId == null) return;

      final response = await DioClient.dio.get(
        '/gifts/received-summary/$targetId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final List<dynamic> giftList = (response.data['data'] as List?) ?? const [];
        if (mounted) {
          setState(() {
            _receivedGifts = giftList.map((e) {
              final row = Map<String, dynamic>.from(e as Map);
              final g = Map<String, dynamic>.from(row['gift'] as Map);
              return ReceivedGift(
                id: g['id'] is int ? g['id'] : 0,
                name: (g['nameAr'] ?? g['name'] ?? '').toString(),
                imageUrl: (g['iconUrl'] ?? '').toString(),
                count: (row['count'] as num?)?.toInt() ?? 1,
              );
            }).toList();
            _loadingGifts = false;
          });
        }
      } else if (mounted) {
        setState(() => _loadingGifts = false);
      }
    } catch (e) {
      debugPrint('Error fetching gifts: $e');
      if (mounted) {
        setState(() => _loadingGifts = false);
      }
    }
  }

  /// Days-left badge for a time-limited product. Turns amber in the last three
  /// days so an expiry doesn't take the user by surprise.
  Widget _remainingChip(InventoryItem item) {
    final days = item.daysRemaining ?? 0;
    final urgent = days <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (urgent ? const Color(0xFFFF9800) : Colors.black).withOpacity(0.82),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: urgent ? const Color(0xFFFFD180) : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            urgent ? Icons.timer : Icons.schedule,
            size: 11,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            item.remainingLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildItem(InventoryItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: item.isActive
            ? Border.all(color: Colors.greenAccent, width: 2)
            : Border.all(color: Colors.white10),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: 120,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: isVideo(item.fileUrl)
                          ? VideoPreview(url: item.fileUrl)
                          : Image.network(
                        item.previewUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                        const Icon(Icons.image_not_supported),
                      ),
                    ),
                  ),
                  // Rented products say how long is left; permanent ones stay
                  // unlabelled so the common case adds no visual noise.
                  if (!item.isPermanent)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _remainingChip(item),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (item.isActive)
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: activating ? null : () => deactivateItem(item),
                  child: const Text("إلغاء الاستخدام", style: TextStyle(fontSize: 12, color: Colors.white)),
                ),
              )
            else
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFF4ECDC4),
                  ),
                  onPressed: activating
                      ? null
                      : () => activateItem(item.id),
                  child: const Text("استخدام", style: TextStyle(fontSize: 12)),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildInventorySection() {
    final filtered = items.where((e) => e.type == selectedType).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF5E35B1).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entrance banners, bubbles and badges had no tab here, so a user
          // could buy one and never equip it — which is why the entrance
          // banner never appeared in rooms. Scrolls because five tabs no
          // longer fit across the card.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTab("مركبة", "seat_effect"),
                _buildTab("مداخل", "entrance"),
                _buildTab("فقاعات", "chat_bubble"),
                _buildTab("إطارات", "avatar_frame"),
                _buildTab("شارات", "badge"),
                // B2/B3 — without these two the user could buy a profile
                // background or a page-decoration frame and never equip it.
                _buildTab("خلفية الصفحة", "profile_background"),
                _buildTab("تزيين الصفحة", "profile_decor"),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (filtered.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text("No items", style: TextStyle(color: Colors.white)),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.55,
              ),
              itemBuilder: (context, index) {
                return buildItem(filtered[index]);
              },
            ),
        ],
      ),
    );
  }

  /// Build Received Gifts Section
  Widget _buildReceivedGiftsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF5E35B1).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.card_giftcard, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'الهدايا',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingGifts)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Color(0xFF4ECDC4)),
              ),
            )
          else if (_receivedGifts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No gifts received yet',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _receivedGifts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.8,
              ),
              itemBuilder: (context, index) {
                final gift = _receivedGifts[index];
                return Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            gift.imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.card_giftcard,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'x${gift.count}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Future<User?> _fetchUserById(int userId) async {
    try {
      final token = await StorageService.getAccessToken();
      if (token == null) return null;

      final response = await DioClient.dio.get(
        '/users/$userId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        return User.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching user $userId: $e');
      return null;
    }
  }

  Widget _buildTab(String title, String type) {
    final isSelected = selectedType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedType = type;
        });
      },
      // التبويبات كانت ملتصقة ببعضها — مسافة بسيطة تفصلها.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 20,
            height: 3,
            color: isSelected ? Colors.white : Colors.transparent,
          )
        ],
        ),
      ),
    );
  }

  Widget _buildProfileContent(User user, {required bool isOwnProfile}) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A1A5E),
              Color(0xFF1A0E3E),
              Color(0xFF0D0620),
            ],
          ),
        ),
        child: Stack(
          children: [
            // The user's own page background — still image, animated GIF or a
            // video clip — painted UNDER everything, replacing the gradient.
            if ((user.profileBgUrl ?? '').trim().isNotEmpty)
              Positioned.fill(
                child: ProfileBackground(
                  url: user.profileBgUrl!.trim(),
                  isVideo: (user.profileBgType ?? '').toLowerCase() == 'video',
                ),
              ),
            SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // (Logout button removed from here — it lives in the Settings screen.)

                    _buildProfileAvatar(user, context, isOwnProfile: isOwnProfile),
                    const SizedBox(height: 8),

                    Text(
                      user.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // #31: live badge / مسار — enter this user's room if they're hosting.
                    if (!isOwnProfile && user.liveRoomId != null) ...[
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RoomScreen(roomId: user.liveRoomId!)),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4081),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFFF4081).withOpacity(0.5), blurRadius: 10),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sensors, color: Colors.white, size: 15),
                              SizedBox(width: 5),
                              Text('مسار • LIVE',
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],

                    // العمر ومعه علامة الجنس — العلامة كانت بجانب الليفل.
                    if (user.age != null || user.gender != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (user.age != null)
                            Text(
                              '${user.age} سنة',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 14,
                              ),
                            ),
                          if (user.gender == 'male' || user.gender == 'female') ...[
                            const SizedBox(width: 6),
                            Icon(
                              user.gender == 'female' ? Icons.female : Icons.male,
                              size: 16,
                              color: user.gender == 'female'
                                  ? const Color(0xFFFF7AB6)
                                  : const Color(0xFF62B6FF),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],

                    _buildLevelBadge(user.level ?? 1),
                    const SizedBox(height: 4),

                    // #28: badges row — owned special items (frames/effects/themes).
                    _buildBadgesRow(user.id),
                    const SizedBox(height: 4),

                    // A15 / #44 — "بعد الموافقة يظهر الـ CP في الصفحة الشخصية".
                    // Shown on anyone's profile, but only the owner's own page
                    // can end a pairing (the list screen enforces that).
                    _CpProfileCard(userId: user.id, isOwnProfile: isOwnProfile),

                    if (user.agencyRole != null) ...[
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/my-agencies'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: user.agencyRole == 'agent'
                                ? const Color(0xFFFFD700).withOpacity(0.18)
                                : const Color(0xFF4ECDC4).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: user.agencyRole == 'agent'
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFF4ECDC4),
                            ),
                          ),
                          child: Text(
                            user.agencyRole == 'agent' ? 'وكيل' : 'مضيف',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: user.agencyRole == 'agent'
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFF4ECDC4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],

                    _buildUserIdRow(user.publicDisplayId, context),
                    const SizedBox(height: 12),

                    _buildStatsRow(user),
                    const SizedBox(height: 10),

                    // Room moderation (only when opened from a room, by its
                    // owner/admin) — high up, since it is why the card was
                    // opened at all.
                    if (!isOwnProfile) ...[
                      Builder(builder: (_) {
                        final bar = _buildRoomModerationBar(user);
                        return bar == null ? const SizedBox.shrink() : bar;
                      }),
                      const SizedBox(height: 10),
                    ],

                    if (isOwnProfile) _buildCoinsCard(_displayCoins(user), context),
                    const SizedBox(height: 10),

                    // Only a وكيل or a مضيف has a target; anyone else already
                    // took their 5% at support time and must not see the card.
                    if (isOwnProfile && _hasTarget) ...[
                      _buildTargetCard(context),
                      const SizedBox(height: 10),
                    ],

                    // #26: وكالة / متجر / إعدادات quick-access row (own profile)
                    if (isOwnProfile) ...[
                      _buildQuickAccessRow(),
                      const SizedBox(height: 12),
                    ],

                    // Show inventory only for own profile
                    if (isOwnProfile) ...[
                      _buildInventorySection(),
                      const SizedBox(height: 10),
                    ],

                    _buildReceivedGiftsSection(),

                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // Bottom bar only for own profile
              if (isOwnProfile)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: GlassBottomBar(
                    homeLabel: "الرئيسية",
                    searchLabel: "الرسائل",
                    gamesLabel: "الألعاب",
                    profileLabel: "حسابي",
                    hasRoom: false,
                    roomImageUrl: null,
                    onHome: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                            (route) => false,
                      );
                    },
                    onSearch: () => Navigator.pushNamed(context, '/messages'),
                    onGames: () => Navigator.pushNamed(context, '/games'),
                    onProfile: () {},
                    onCenter: () {},
                  ),
                ),

              // #29: other-user profile → room / message / follow action bar
              if (!isOwnProfile)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 16,
                  child: _buildOtherUserActionBar(user),
                ),

              // #2 القائمة السوداء now has its own button in the action bar
              // below, next to متابعة — it was buried in this overflow menu,
              // which is why blocking looked like it didn't exist.
            ],
          ),
        ),

            // إطار تزيين الصفحة الشخصية — LAST in the stack so it sits on the
            // page's border above everything, and IgnorePointer inside so it
            // covers nothing you can press ("لا يغطي علي شئ من الصفحه").
            if ((user.profileDecorUrl ?? '').trim().isNotEmpty)
              Positioned.fill(
                child: ProfileDecorFrame(
                  url: user.profileDecorUrl!.trim(),
                  isVideo: (user.profileDecorType ?? '').toLowerCase() == 'video',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final currentUser = authState.user;

    // If viewing another user's profile
    final targetUserId = widget.userId;
    final isOtherUser = targetUserId != null && targetUserId != currentUser?.id;

    // Loading state while checking auth
    if (currentUser == null && !isOtherUser) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A0E3E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4ECDC4)),
        ),
      );
    }

    // For other users, fetch their data via FutureBuilder
    if (isOtherUser) {
      return FutureBuilder<User?>(
        future: _otherUserFor(targetUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF1A0E3E),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF4ECDC4)),
              ),
            );
          }

          final otherUser = snapshot.data;
          if (otherUser == null) {
            return Scaffold(
              backgroundColor: const Color(0xFF1A0E3E),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'User not found',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18),
                    ),
                  ],
                ),
              ),
            );
          }

          // Load follow status once for this other user.
          if (!_followLoaded) {
            _followLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadFollowStatus(otherUser.id));
          }
          return _buildProfileContent(otherUser, isOwnProfile: false);
        },
      );
    }

    // My own profile
    return _buildProfileContent(currentUser!, isOwnProfile: true);
  }

  /// Build profile avatar with edit button overlay
  Widget _buildProfileAvatar(User user, BuildContext context, {required bool isOwnProfile}) {
    final frame = activeFrame != null
        ? AvatarFrame.fromUrl(activeFrame!.fileUrl)
        : (user.avatarFrameUrl != null && user.avatarFrameUrl!.isNotEmpty)
        ? AvatarFrame.fromUrl(user.avatarFrameUrl!)
        : AvatarFrame.fromType(
      (user.vipLevel ?? 0) > 0
          ? AvatarFrameType.vip
          : AvatarFrameType.samafoxDefault,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: () => _openFullImage(context, user.avatarUrl),
          child: FramedAvatar(
            size: 120,
            avatarSize: 80,
            frame: frame,
            imageUrl: user.avatarUrl,
            fallbackText: user.name,
          ),
        ),
        // Edit button only for own profile
        if (isOwnProfile)
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                );
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF4ECDC4),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1A0E3E), width: 2),
                ),
                child: const Icon(Icons.edit, color: Colors.white, size: 18),
              ),
            ),
          ),
      ],
    );
  }

  /// Any user's photo can be opened full-screen (view/save), not just own.
  void _openFullImage(BuildContext context, String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return;
    String url = avatarUrl;
    if (!url.startsWith('http')) {
      url = AppConfig.socketUrl.replaceFirst(RegExp(r'/+$'), '') +
          (url.startsWith('/') ? url : '/$url');
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullImageViewer(imageUrl: url),
        fullscreenDialog: true,
      ),
    );
  }

  /// Build level badge (blue circle with number)
  Map<String, dynamic>? _progress;

  /// #23/#24: fetch level + VIP progress and show how far to the next tier.
  Future<void> _showProgressDialog(BuildContext context, {required bool vip}) async {
    try {
      if (_progress == null) {
        final token = await StorageService.getAccessToken();
        final res = await DioClient.dio.get(
          '/vip/progress',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        final data = res.data is Map ? (res.data['data'] ?? res.data) : null;
        if (data is Map) _progress = Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('progress fetch error: $e');
    }
    if (!mounted) return;
    final p = _progress ?? {};
    final title = vip ? 'تقدّم VIP' : 'تقدّم المستوى';
    final body = vip
        ? 'أنت الآن VIP ${p['vipLevel'] ?? 0}.\nتحتاج ${p['coinsRemainingForNextVip'] ?? '-'} كوينز شحن للوصول إلى VIP ${p['nextVip'] ?? '-'}.'
        : 'أنت الآن المستوى ${p['level'] ?? 1}.\nتحتاج ${p['xpRemaining'] ?? '-'} نقطة للوصول إلى المستوى ${p['nextLevel'] ?? '-'}.';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1347),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70, height: 1.6)),
        actions: [
          // Tiers the dashboard priced can be bought outright instead of
          // waiting to recharge to the threshold.
          if (vip)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final bought = await VipBuySheet.show(
                  context,
                  currentVipLevel: (p['vipLevel'] as num?)?.toInt() ?? 0,
                  coinsBalance: ref.read(authStateProvider).user?.coinsBalance,
                );
                if (bought == true && mounted) {
                  _progress = null; // stale after a promotion
                  await ref.read(authStateProvider.notifier).refreshUser();
                  if (mounted) setState(() {});
                }
              },
              child: const Text('شراء VIP', style: TextStyle(color: Color(0xFF4ECDC4))),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً', style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelBadge(int level) {
    // Appearance now comes from LevelBadge, which follows لوحة التحكم and falls
    // back to the original cyan chip when the tier isn't configured.
    return GestureDetector(
      onTap: () => _showProgressDialog(context, vip: false),
      child: LevelBadge(level: level),
    );
  }

  /// Build user ID row with copy icon
  Widget _buildUserIdRow(int userId, BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ID:$userId',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: userId.toString()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ID copied'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: Icon(
            Icons.copy,
            size: 18,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  /// Build stats row (Friends, Followed, Fans, Visitors)
  /// #26 / #27: وكالة / متجر / إعدادات quick-access row (store lives here now).
  Widget _buildQuickAccessRow() {
    Widget tile(IconData icon, String label, Color color, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          tile(Icons.workspaces, 'وكالتي', const Color(0xFFFFD700),
              () => Navigator.pushNamed(context, '/my-agencies')),
          tile(Icons.storefront, 'متجر', const Color(0xFF4ECDC4),
              () => Navigator.pushNamed(context, '/store')),
          tile(Icons.local_shipping, 'شحن', const Color(0xFFFF8A3D),
              () => Navigator.pushNamed(context, '/charging-agent').then((_) => _refreshCoins()),),
          tile(Icons.settings, 'إعدادات', const Color(0xFF9C6BFF),
              () => Navigator.pushNamed(context, '/settings')),
        ],
      ),
    );
  }

  Widget _buildStatsRow(User user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          GestureDetector(
            onTap: _showFollowingSheet,
            child: _buildStatItem('${user.followingCount ?? 0}', 'Following'),
          ),
          _buildStatItem('${user.followersCount ?? 0}', 'Fans'),
          GestureDetector(
            onTap: () => _showProgressDialog(context, vip: false),
            child: _buildStatItem('${user.level ?? 1}', 'Level'),
          ),
          GestureDetector(
            onTap: () => _showProgressDialog(context, vip: true),
            child: _buildStatItem('${user.vipLevel ?? 0}', 'VIP'),
          ),
        ],
      ),
    );
  }

  /// #25: list of accounts I follow; a live badge lets me jump into their room.
  Future<void> _showFollowingSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: FollowService.getFollowing(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return const SizedBox(
                height: 220,
                child: Center(child: Text('لا يوجد متابَعون بعد', style: TextStyle(color: Colors.white70))),
              );
            }
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('المتابَعون', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final u = list[i];
                        final liveRoomId = u['liveRoomId'];
                        final name = (u['name'] ?? '').toString();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF3D2B7A),
                            backgroundImage: (u['avatarUrl'] != null && '${u['avatarUrl']}'.isNotEmpty)
                                ? NetworkImage('${u['avatarUrl']}')
                                : null,
                            child: (u['avatarUrl'] == null || '${u['avatarUrl']}'.isEmpty)
                                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white))
                                : null,
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text('ID: ${u['displayId'] ?? '-'}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          trailing: liveRoomId != null
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF4081),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('LIVE',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                )
                              : const Icon(Icons.chevron_left, color: Colors.white38),
                          onTap: () {
                            Navigator.pop(context);
                            if (liveRoomId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => RoomScreen(roomId: liveRoomId as int)),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ProfileScreen(userId: u['id'] as int)),
                              );
                            }
                          },
                        );
                      },
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

  /// Build single stat item
  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  int _displayCoins(User user) {
    final coinsBalance = user.coinsBalance ?? 0;
    final fallbackCoins = user.coins ?? 0;
    if (coinsBalance > 0) return coinsBalance;
    return fallbackCoins;
  }

  /// Build coins card with integrated recharge button
  // #13: TARGET card — earned gifts vs the goal set by the agent, with a
  // progress bar and the remaining amount so the host knows how much is left.
  /// Compact target strip: 🎯 Target <goal> ──── $ earned.
  /// Tapping it opens the full breakdown (gifts, remaining, agency target).
  Widget _buildTargetCard(BuildContext context) {
    final t = _myTarget!;
    final items = (t['items'] as List?) ?? const [];
    final int earned = (t['totalEarned'] as num?)?.toInt() ?? 0;
    final double earnedDollars = (t['totalDollars'] as num?)?.toDouble() ?? 0.0;
    int goal = 0;
    for (final e in items) {
      if (e is Map) goal += (e['targetGoalCoins'] as num?)?.toInt() ?? 0;
    }
    // The وكيل's goal lives on the agency, not on a membership row, so summing
    // `items` alone left every agent at 0.
    for (final e in ((t['agentTargets'] as List?) ?? const [])) {
      if (e is Map) goal += (e['goalCoins'] as num?)?.toInt() ?? 0;
    }
    final double progress =
        goal > 0 ? (earned / goal).clamp(0.0, 1.0).toDouble() : 0.0;
    // Under the word Target goes the TARGET ITSELF — the coins earned — with
    // the goal after it when one is set. It used to print `goal` alone, so a
    // وكيل or مضيف with no admin-set goal saw a bare 0 next to his dollars.
    final String targetLabel = goal > 0 ? '$earned / $goal' : '$earned';
    final String dollars = earnedDollars == earnedDollars.roundToDouble()
        ? earnedDollars.toStringAsFixed(0)
        : earnedDollars.toStringAsFixed(2);

    return GestureDetector(
      onTap: () => _showTargetDetailsSheet(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF241A52),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        // The strip reads left-to-right in the design, so it keeps its own
        // direction instead of mirroring with the rest of the Arabic UI.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Target',
                    style: TextStyle(
                      color: Color(0xFFFFB74D),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    targetLabel,
                    style: const TextStyle(
                      color: Color(0xFFFFB74D),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 9,
                    backgroundColor: const Color(0xFF14103A),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFFFB300)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '\$ $dollars',
                style: const TextStyle(
                  color: Color(0xFF2ECC71),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTargetDetailsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 24, bottom: 32),
          child: _buildTargetDetails(),
        ),
      ),
    );
  }

  /// Full target breakdown — used by the sheet behind the compact strip.
  Widget _buildTargetDetails() {
    final t = _myTarget!;
    final items = (t['items'] as List?) ?? const [];
    final int earned = (t['totalEarned'] as num?)?.toInt() ?? 0;
    final double earnedDollars = (t['totalDollars'] as num?)?.toDouble() ?? 0.0;
    final int totalGifts = (t['totalGifts'] as num?)?.toInt() ?? 0;
    // Sum goals/remaining across memberships (usually just one).
    int goal = 0;
    int remaining = 0;
    for (final e in items) {
      if (e is Map) {
        goal += (e['targetGoalCoins'] as num?)?.toInt() ?? 0;
        remaining += (e['remainingCoins'] as num?)?.toInt() ?? 0;
      }
    }
    final double progress =
        goal > 0 ? (earned / goal).clamp(0.0, 1.0).toDouble() : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1A5E), Color(0xFF3A2A6E)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, color: Color(0xFF4ECDC4), size: 26),
              const SizedBox(width: 10),
              const Text(
                'التارجت',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                goal > 0 ? '$earned / $goal' : '$earned',
                style: const TextStyle(
                  color: Color(0xFF4ECDC4),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Dollar meter — moves with the target as it's set from the
          // dashboard's تارجت tiers (coins threshold -> $ payout).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2ECC71).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.attach_money, color: Color(0xFF2ECC71), size: 18),
                Text(
                  earnedDollars.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Color(0xFF2ECC71),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (goal > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.white.withOpacity(0.12),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF4ECDC4)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              remaining > 0
                  ? 'متبقٍ $remaining كوينز لإغلاق التارجت'
                  : 'اكتمل التارجت 🎉',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 13,
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'إجمالي الكوينزات من الهدايا المستلمة',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: Color(0xFFFFD700), size: 16),
              const SizedBox(width: 6),
              Text(
                'عدد الهدايا: $totalGifts',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          // 2026-08-23: the separate "تارجت الوكيل" block that used to sit under
          // this one is gone — the client wants ONE target panel
          // ("المطلوب الصفحه اللي فوق فقط ... اللي تحت غير مطلوبه"). The agency
          // goal it carried is folded into the single figure above.
        ],
      ),
    );
  }

  /// Gold coins card — the whole card opens وكالة الشحن (the recharge button
  /// that used to sit on the right is gone).
  Widget _buildCoinsCard(int coinsBalance, BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/charging-agent').then((_) => _refreshCoins());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        height: 112,
        decoration: BoxDecoration(
          color: const Color(0xFF2A1606),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFC24D), width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8A00).withOpacity(0.45),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          // Coin on the left, balance on the right — fixed direction so the
          // card does not mirror with the surrounding RTL layout.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                // Golden sunburst radiating from behind the coin.
                const Positioned.fill(
                  child: CustomPaint(painter: _CoinBurstPainter()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Two-tone coin: darker rim around a lighter face.
                    Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF7B733), Color(0xFFC77800)],
                        ),
                        boxShadow: [
                          BoxShadow(color: Color(0x99FFC107), blurRadius: 14),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 55,
                          height: 55,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFE9A8), Color(0xFFFFB300)],
                            ),
                          ),
                          child: const Icon(Icons.star, color: Colors.white, size: 32),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$coinsBalance',
                          style: const TextStyle(
                            color: Color(0xFFFFF8E1),
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            height: 1.05,
                            shadows: [
                              Shadow(color: Color(0xAA6B3B00), blurRadius: 8),
                            ],
                          ),
                        ),
                        Text(
                          'Coins',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build VIP card with XP progress bar. Removed from the profile layout on the
  /// owner's request; kept here in case the section comes back.
  // ignore: unused_element
  Widget _buildVIPCard(int vipLevel, int currentXp, BuildContext context) {
    const int xpPerLevel = 1000;
    final double progress = (currentXp % xpPerLevel) / xpPerLevel;
    final int xpForNextLevel = (vipLevel + 1) * xpPerLevel;

    return GestureDetector(
      onTap: () => _showProgressDialog(context, vip: true),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF5E35B1),
              Color(0xFF4A148C),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5E35B1).withOpacity(0.5),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.workspace_premium,
                    color: Colors.white,
                    size: 35,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SamaFox VIP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '10+ unique decorations and 30+ VIP\nprivileges for you!',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'XP Progress',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                    ),
                    Text(
                      '$currentXp / $xpForNextLevel XP',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sunburst backdrop for the coins card: a warm glow with light rays fanning
/// out from behind the coin, darkening towards the corners.
class _CoinBurstPainter extends CustomPainter {
  const _CoinBurstPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final focal = Offset(size.width * 0.16, size.height * 0.5);
    final reach = size.width * 1.25;

    // Warm pool of light behind the coin.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (focal.dx / size.width) * 2 - 1,
            (focal.dy / size.height) * 2 - 1,
          ),
          radius: 0.95,
          colors: const [
            Color(0xFFD9963A),
            Color(0xFF8A5216),
            Color(0xFF2A1606),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // Light rays.
    const rayCount = 26;
    final rayPaint = Paint()..color = const Color(0x2EFFE0A3);
    for (var i = 0; i < rayCount; i++) {
      final start = i * 2 * math.pi / rayCount;
      final end = start + (math.pi / rayCount) * 0.85;
      final path = Path()
        ..moveTo(focal.dx, focal.dy)
        ..lineTo(focal.dx + reach * math.cos(start), focal.dy + reach * math.sin(start))
        ..lineTo(focal.dx + reach * math.cos(end), focal.dy + reach * math.sin(end))
        ..close();
      canvas.drawPath(path, rayPaint);
    }

    // Vignette so the rays fade into the dark corners.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, 0),
          radius: 1.15,
          colors: [
            const Color(0xFF2A1606).withOpacity(0.0),
            const Color(0xFF2A1606).withOpacity(0.55),
            const Color(0xFF1A0D02).withOpacity(0.9),
          ],
          stops: const [0.35, 0.75, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _CoinBurstPainter oldDelegate) => false;
}

/// Full-screen viewer for any user's photo — pinch to zoom.
class _FullImageViewer extends StatelessWidget {
  const _FullImageViewer({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}


/// A15 / #44 — the CP strip on a profile page.
///
/// Renders nothing at all when the user has no pairings: an empty "CP" heading
/// on every profile in the app would be noise, and the feature announces itself
/// on the home page instead.
class _CpProfileCard extends StatefulWidget {
  const _CpProfileCard({required this.userId, required this.isOwnProfile});

  final int userId;
  final bool isOwnProfile;

  @override
  State<_CpProfileCard> createState() => _CpProfileCardState();
}

class _CpProfileCardState extends State<_CpProfileCard> {
  late Future<List<CpPartner>> _future;

  @override
  void initState() {
    super.initState();
    _future = CpRepository().partners(userId: widget.userId);
  }

  @override
  void didUpdateWidget(covariant _CpProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Navigating from one profile to another reuses this State object.
    if (oldWidget.userId != widget.userId) {
      _future = CpRepository().partners(userId: widget.userId);
    }
  }

  String? _resolve(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CpPartner>>(
      future: _future,
      builder: (context, snap) {
        final partners = snap.data ?? const <CpPartner>[];
        if (partners.isEmpty) return const SizedBox.shrink();
        // Four faces is what fits without crowding the header; the rest are
        // behind the "+N" chip, which opens the full list.
        final shown = partners.take(4).toList();
        final extra = partners.length - shown.length;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CpListScreen(
                    userId: widget.isOwnProfile ? null : widget.userId,
                  ),
                ),
              );
              if (mounted) {
                setState(() {
                  _future = CpRepository().partners(userId: widget.userId);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4081).withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFF4081).withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💞', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  const Text(
                    'CP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final p in shown) ...[
                    _face(p),
                    const SizedBox(width: 4),
                  ],
                  if (extra > 0)
                    Text(
                      '+$extra',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _face(CpPartner p) {
    final url = _resolve(p.avatarUrl);
    return CircleAvatar(
      radius: 11,
      backgroundColor: const Color(0xFF2A1A5E),
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null
          ? Text(
              p.name.isNotEmpty ? p.name.characters.first.toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            )
          : null,
    );
  }
}

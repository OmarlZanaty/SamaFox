import 'dart:async';
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
import '../models/user.dart';
import '../services/dio_client.dart';
import '../services/store_service.dart';
import '../utils/storage_service.dart';
import '../widgets/FramedAvatar.dart';
import '../widgets/glass_bottom_bar.dart';
import '../widgets/video_preview_widget.dart';
import '../services/socket_service.dart';
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

  const ProfileScreen({super.key, this.userId});

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

  Future<void> _toggleBlock(int userId) async {
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

  /// #29: bottom action bar shown on another user's profile — room / message / follow.
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
          if (user.liveRoomId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RoomScreen(roomId: user.liveRoomId!)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لم يتم فتح الغرفة حتى الآن')),
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

  Future<void> _loadMyTarget() async {
    try {
      final token = await StorageService.getAccessToken();
      if (token == null) return;
      final resp = await DioClient.dio.get(
        '/agencies/my-target',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = (resp.data is Map) ? resp.data['data'] : null;
      if (mounted && data is Map && data['hasTarget'] == true) {
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

      await loadInventory(force: true);

    } catch (e) {
      debugPrint(e.toString());
    }

    setState(() => activating = false);
  }

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
        await _service.deactivateAll(token!);
        await SocketService().waitUntilConnected();
        SocketService().sendSeatEffect({"video": ""});
      } else {
        await _service.deactivateAll(token!);
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTab("مركبة", "seat_effect"),
              _buildTab("إطارات", "avatar_frame"),
            ],
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
        child: SafeArea(
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

                    if (user.age != null) ...[
                      Text(
                        '${user.age} سنة',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],

                    _buildLevelBadge(user.level ?? 1),
                    const SizedBox(height: 4),

                    if (user.agencyRole != null) ...[
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/agency-panel'),
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

                    if (isOwnProfile) _buildCoinsCard(_displayCoins(user), context),
                    const SizedBox(height: 10),

                    if (isOwnProfile && _myTarget != null) ...[
                      _buildTargetCard(context),
                      const SizedBox(height: 10),
                    ],

                    _buildVIPCard(
                      user.vipLevel ?? 0,
                      user.xp ?? 0,
                      context,
                    ),

                    const SizedBox(height: 10),

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
                    storeLabel: "المتجر",
                    shippingAgentsLabel: "وكلاء الشحن",
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
                    onStore: () => Navigator.pushNamed(context, '/store'),
                    onShippingAgents: () => Navigator.pushNamed(context, '/charging-agent'),
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

              // #2 القائمة السوداء: block/unblock from another user's profile.
              if (!isOwnProfile)
                Positioned(
                  top: 4,
                  left: 8,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                    color: const Color(0xFF2A1A5E),
                    onSelected: (v) {
                      if (v == 'block') _toggleBlock(user.id);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'block',
                        child: Text(
                          _targetBlocked ? 'إلغاء الحظر' : 'حظر (القائمة السوداء)',
                          style: TextStyle(
                            color: _targetBlocked ? Colors.white : Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
        FramedAvatar(
          size: 120,
          avatarSize: 80,
          frame: frame,
          imageUrl: user.avatarUrl,
          fallbackText: user.name,
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً', style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelBadge(int level) {
    return GestureDetector(
      onTap: () => _showProgressDialog(context, vip: false),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.male, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Text(
            '$level',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
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
          tile(Icons.workspaces, 'وكالة', const Color(0xFFFFD700),
              () => Navigator.pushNamed(context, '/agency-panel')),
          tile(Icons.storefront, 'متجر', const Color(0xFF4ECDC4),
              () => Navigator.pushNamed(context, '/store')),
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
  Widget _buildTargetCard(BuildContext context) {
    final t = _myTarget!;
    final items = (t['items'] as List?) ?? const [];
    final int earned = (t['totalEarned'] as num?)?.toInt() ?? 0;
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
              'إجمالي الهدايا المستلمة منذ انضمامك',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoinsCard(int coinsBalance, BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 100,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF8E1),
            Color(0xFFFFE0B2),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 20,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.monetization_on,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$coinsBalance',
                      style: const TextStyle(
                        color: Color(0xFF5D4037),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Coins',
                      style: TextStyle(
                        color: const Color(0xFF5D4037).withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, '/charging-agent').then((_) => _refreshCoins());
              },
              child: Container(
                width: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.shade700,
                      Colors.deepOrange.shade700,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                    topLeft: Radius.circular(40),
                    bottomLeft: Radius.circular(40),
                  ),
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.card_giftcard, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'First\nRecharge',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build VIP card with XP progress bar
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

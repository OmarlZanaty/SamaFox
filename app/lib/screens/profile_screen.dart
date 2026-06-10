import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/screens/edit_profile_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    loadInventory();
    _refreshCoins();
    _fetchReceivedGifts();

    _coinsRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
          (_) => _refreshCoins(),
    );
  }

  Future<void> _refreshCoins() async {
    await ref.read(authStateProvider.notifier).refreshUser();
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
        await _service.activateItem(token!, activatedItem.id);
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

  /// Fetch received gifts from backend
  Future<void> _fetchReceivedGifts() async {
    try {
      final token = await StorageService.getAccessToken();
      if (token == null) return;

      final targetId = widget.userId ?? ref.read(authStateProvider).user?.id;
      if (targetId == null) return;

      final response = await DioClient.dio.get(
        '/users/$targetId/received-gifts',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> giftList = response.data;
        if (mounted) {
          setState(() {
            _receivedGifts = giftList.map((e) => ReceivedGift.fromJson(e)).toList();
            _loadingGifts = false;
          });
        }
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
              const Text(
                "ACTIVE",
                style: TextStyle(color: Colors.greenAccent, fontSize: 12),
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
                  child: const Text("Use", style: TextStyle(fontSize: 12)),
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

                    // Show logout only for own profile
                    if (isOwnProfile) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Spacer(),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: ref.watch(authStateProvider).isLoading
                                  ? null
                                  : () => _confirmAndLogout(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.redAccent.withOpacity(0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (ref.watch(authStateProvider).isLoading) ...[
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ] else ...[
                                      const Icon(Icons.logout,
                                          color: Colors.redAccent, size: 18),
                                      const SizedBox(width: 8),
                                    ],
                                    const Text(
                                      'تسجيل الخروج',
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

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

                    _buildUserIdRow(user.id ?? 0, context),
                    const SizedBox(height: 12),

                    _buildStatsRow(user),
                    const SizedBox(height: 10),

                    if (isOwnProfile) _buildCoinsCard(_displayCoins(user), context),
                    const SizedBox(height: 10),

                    _buildVIPCard(
                      user.vipLevel ?? 0,
                      user.xp ?? 0,
                      context,
                    ),

                    const SizedBox(height: 10),

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
        future: _fetchUserById(targetUserId),
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
  Widget _buildLevelBadge(int level) {
    return Container(
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
  Widget _buildStatsRow(User user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('${user.followingCount ?? 0}', 'Following'),
          _buildStatItem('${user.followersCount ?? 0}', 'Fans'),
          _buildStatItem('${user.level ?? 1}', 'Level'),
          _buildStatItem('${user.vipLevel ?? 0}', 'VIP'),
        ],
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
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VIP purchase coming soon')),
        );
      },
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

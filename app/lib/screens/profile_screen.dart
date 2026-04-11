import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/screens/edit_profile_screen.dart';
import 'package:samafox/screens/feature_screens.dart';
import 'package:samafox/screens/store_screen.dart';
import '../models/InventoryItem.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../services/dio_client.dart';
import '../services/store_service.dart';
import '../utils/storage_service.dart';
import '../widgets/FramedAvatar.dart';
import '../widgets/glass_bottom_bar.dart';
import '../widgets/video_preview_widget.dart';
import '../services/socket_service.dart';
import 'home_screen.dart';

/// Profile Screen - Redesigned with responsive layout and all requested features
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {

  late final StoreService _service = StoreService();
  String selectedType = "seat_effect";
  InventoryItem? activeFrame;

  @override
  void initState() {
    super.initState();

    loadInventory();
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

    // Call logout (clears tokens + disconnect socket in your notifier)
    await ref.read(authStateProvider.notifier).logout();

    if (!mounted) return;

    // Go to login and clear stack
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
      print("INVENTORY ERROR: $e");
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
        await _service.activateFrame(token!, productId);
      } else {
        await _service.activateItem(token!, productId);
      }

      // ✅ SEAT EFFECT
      if (activatedItem.type == "seat_effect") {
        await SocketService().waitUntilConnected();

        SocketService().sendSeatEffect({
          "video": activatedItem.fileUrl,
        });
      }

      // ✅ AVATAR FRAME
      else if (activatedItem.type == "avatar_frame" || activatedItem.type == "FRAME") {

        // 🔥 SAVE TO BACKEND
        await DioClient.dio.put(
          "/users/me",
          data: {
            "avatarFrameUrl": Uri.encodeFull(activatedItem.fileUrl),
          },
        );

        // 🔥 APPLY LOCALLY (IMPORTANT)
        setState(() {
          activeFrame = activatedItem;
        });
      }

      await loadInventory(force: true);

    } catch (e) {
      print(e);
    }

    setState(() => activating = false);
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
      child: SingleChildScrollView( // ✅ FIX OVERFLOW
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

    print("SELECTED TYPE: $selectedType");
    print("ITEM TYPES: ${items.map((e) => e.type).toList()}");

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

          /// 🔥 TABS (same as store)
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


  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    // If user is null, show a loading indicator
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A0E3E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4ECDC4)),
        ),
      );
    }

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

              /// ✅ MAIN CONTENT
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),

                /// 🔥 IMPORTANT: prevent overlap with bottom bar
                padding: const EdgeInsets.only(bottom: 120),

                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ✅ Top row with Logout button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Spacer(),
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: authState.isLoading
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
                                  if (authState.isLoading) ...[
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

                    _buildProfileAvatar(user, context),
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

                    _buildUserIdRow(user.id ?? 0, context),
                    const SizedBox(height: 12),

                    _buildStatsRow(user),
                    const SizedBox(height: 10),

                    _buildCoinsCard(user.coinsBalance ?? 0, context),
                    const SizedBox(height: 10),

                    _buildVIPCard(
                      user.vipLevel ?? 0,
                      user.xp ?? 0,
                      context,
                    ),

                    const SizedBox(height: 10),

                    _buildInventorySection(),
                    const SizedBox(height: 10),

                    _buildFeaturesGrid(context),

                    const SizedBox(height: 20),
                  ],
                ),
              ),

              /// 🔥 BOTTOM BAR (CORRECT POSITION)
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

                  onSearch: () =>
                      Navigator.pushNamed(context, '/messages'),

                  onStore: () =>
                      Navigator.pushNamed(context, '/store'),

                  onShippingAgents: () =>
                      Navigator.pushNamed(context, '/charging-agent'),

                  onGames: () =>
                      Navigator.pushNamed(context, '/games'),

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

  /// Build profile avatar with edit button overlay
  Widget _buildProfileAvatar(User user, BuildContext context)
  {
    // choose frame type (example: default, or vip if vipLevel > 0)
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
        // ✅ SAME FRAME like seats (SVG frame)
        FramedAvatar(
          size: 120,
          avatarSize: 80, // ✅ ADD THIS
          frame: frame,
          imageUrl: user.avatarUrl,
          fallbackText: user.name,
        ),

        // ✅ Edit button overlay (same as you already had)
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
                Navigator.pushNamed(context, '/charging_agent');
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

    final double progress =
        (currentXp % xpPerLevel) / xpPerLevel;

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

  /// Build features grid (3 columns, responsive)
  Widget _buildFeaturesGrid(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 5 : 4;

    final features = [
      {'icon': Icons.backpack, 'label': 'Backpack', 'color': const Color(0xFF00BCD4)},
      {'icon': Icons.emoji_events, 'label': 'Wealth Level', 'color': const Color(0xFFFFC107)},
      {'icon': Icons.favorite, 'label': 'Charm Level', 'color': const Color(0xFF4CAF50)},
      {'icon': Icons.business, 'label': 'Agency center', 'color': const Color(0xFF9C27B0)},
      {'icon': Icons.assignment, 'label': 'Task', 'color': const Color(0xFFFFC107)},
      {'icon': Icons.store, 'label': 'Store', 'color': const Color(0xFFE91E63), 'badge': true},
      {'icon': Icons.card_giftcard, 'label': 'Gift Gallery', 'color': const Color(0xFFE91E63)},
      {'icon': Icons.military_tech, 'label': 'Badge', 'color': const Color(0xFFFFC107)},
      {'icon': Icons.chat, 'label': 'Contact Us', 'color': const Color(0xFF4CAF50)},
      {'icon': Icons.people, 'label': 'Intimate\nRelationship', 'color': const Color(0xFF00BCD4)},
      {'icon': Icons.flag, 'label': 'Event Center', 'color': const Color(0xFFFFC107)},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF5E35B1).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.7,
        ),
        itemCount: features.length,
        itemBuilder: (context, index) {
          final feature = features[index];
          return _buildFeatureItem(
            icon: feature['icon'] as IconData,
            label: feature['label'] as String,
            color: feature['color'] as Color,
            hasBadge: feature['badge'] as bool? ?? false,
            context: context,
          );
        },
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String label,
    required Color color,
    required bool hasBadge,
    required BuildContext context,
  }) {
    return GestureDetector(
      onTap: () => _navigateToFeature(context, label),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0E3E),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.5), width: 2),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              if (hasBadge)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _navigateToFeature(BuildContext context, String label) {
    Widget screen;
    switch (label) {
      case 'Backpack':
        //screen = const BackpackScreen();
        break;
      case 'Wealth Level':
       // screen = const WealthLevelScreen();
        break;
      case 'Charm Level':
       // screen = const CharmLevelScreen();
        break;
      case 'Agency center':
      //  screen = const AgencyCenterScreen();
        break;
      case 'Task':
       // screen = const TaskScreen();
        break;
      case 'Store':
        screen = const StoreScreen();
        break;
      case 'Gift Gallery':
       // screen = const GiftGalleryScreen();
        break;
      case 'Badge':
       // screen = const BadgeScreen();
        break;
      case 'Contact Us':
       // screen = const ContactUsScreen();
        break;
      case 'Intimate\nRelationship':
       // screen = const IntimateRelationshipScreen();
        break;
      case 'Event Center':
      //  screen = const EventCenterScreen();
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label coming soon')),
        );
        return;
    }
    /*Navigator.push(
     // context,
     // MaterialPageRoute(builder: (context) => screen),
    );*/
  }
}

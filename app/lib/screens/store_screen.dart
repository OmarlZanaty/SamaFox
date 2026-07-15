import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart'; // for auth
import '../providers/store_provider.dart'; // to load products
import '../models/product.dart'; // product model
import 'package:samafox/widgets/store_product_tile.dart';
import '../widgets/glass_bottom_bar.dart';
import '../services/store_service.dart';
import '../utils/storage_service.dart';
import '../widgets/video_preview_widget.dart';
import '../widgets/FramedAvatar.dart';
import 'home_screen.dart'; // product tile widget

class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  // Store selected tab type
  String selectedType = "seat_effect"; // Default tab
  Set<String> ownedIds = {};
  bool loadingInventory = true;


  @override
  void initState() {
    super.initState();
    loadOwnedItems();
    // Auto-refresh the product catalog every time the store opens, so newly
    // added products (e.g. a background uploaded from the dashboard) show up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(storeProvider);
    });
  }

  /// Re-fetch the product catalog + owned items (pull-to-refresh / manual).
  Future<void> _refreshStore() async {
    ref.invalidate(storeProvider);
    await Future.wait([
      ref.read(storeProvider.future),
      loadOwnedItems(),
    ]);
  }

  Future<void> loadOwnedItems() async {
    try {
      final token = await StorageService.getAccessToken();
      final service = StoreService();

      final items = await service.getInventory(token!);

      setState(() {
        ownedIds = items.map((e) => e.productId).toSet();
        loadingInventory = false;
      });
    } catch (e) {
      //debugPrint(e);
      setState(() => loadingInventory = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(storeProvider);

    return productsAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF1A0E3E),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: const Color(0xFF1A0E3E),
        body: Center(
          child: Text(
            'Error: $err',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
      data: (products) {
        // Filter products based on selected tab
        final filtered = products.where((p) => p.type == selectedType).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF0D0620),
          body: SafeArea(
            child: Stack(
              children: [

                /// ✅ MAIN CONTENT (Column instead of broken Stack)
                Column(
                  children: [

                    const SizedBox(height: 20),

                    const Text(
                      "المتجر",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// PREVIEW
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF6A1B9A),
                            Color(0xFF311B92),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Image.asset("assets/images/logo.png", height: 50),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              "أهلا بك فى متجر سما فوكس",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          const Icon(Icons.store, color: Colors.white),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// TABS
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          _buildTab("مركبة", "seat_effect"),
                          const SizedBox(width: 10),
                          _buildTab("مداخل", "entrance"),
                          const SizedBox(width: 10),
                          _buildTab("إطارات", "avatar_frame"),
                          const SizedBox(width: 10),
                          _buildTab("شارات", "badge"),
                          const SizedBox(width: 10),
                          _buildTab("خلفيات", "background"),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    /// ✅ GRID (swipe down to refresh)
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshStore,
                        color: const Color(0xFF8E44AD),
                        child: filtered.isEmpty
                                ? ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    children: const [
                                      SizedBox(height: 160),
                                      Center(
                                        child: Text('لا توجد منتجات بعد',
                                            style: TextStyle(color: Colors.white54)),
                                      ),
                                    ],
                                  )
                                : GridView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 120), // 👈 IMPORTANT
                                    itemCount: filtered.length,
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 16,
                                      childAspectRatio: 0.6,
                                    ),
                                    itemBuilder: (context, index) {
                                      return StoreProductTile(
                                        product: filtered[index],
                                        isOwned: ownedIds.contains(filtered[index].id.toString()),
                                      );
                                    },
                                  ),
                      ),
                    ),
                  ],
                ),

                /// ✅ FLOATING BOTTOM BAR
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
                    onStore: () {},
                    onShippingAgents: () => Navigator.pushNamed(context, '/charging-agent'),
                    onGames: () => Navigator.pushNamed(context, '/games'),
                    onProfile: () => Navigator.pushNamed(context, '/profile'),
                    onCenter: () {},
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper to build tab buttons
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

}

// AFTER
class StoreProductTile extends ConsumerStatefulWidget {
  final Product product;
  final bool isOwned;

  const StoreProductTile({
    super.key,
    required this.product,
    required this.isOwned,
  });

  @override
  ConsumerState<StoreProductTile> createState() => _StoreProductTileState();
}

// AFTER
class _StoreProductTileState extends ConsumerState<StoreProductTile> {

  bool loading = false;

  bool isVideo(String url) {
    return url.toLowerCase().endsWith('.mp4') ||
        url.toLowerCase().endsWith('.mov');
  }

  /// Preview before buying: a frame is tried on the current user's own
  /// avatar; an entrance/seat effect plays full-screen. Everything else
  /// (badges, themes) just doesn't get a preview — tapping does nothing.
  void _previewProduct(BuildContext context, Product product) {
    final isFrame = product.type == 'avatar_frame';
    final isEffect = product.type == 'seat_effect' || product.type == 'entrance';
    if (!isFrame && !isEffect) return;

    if (isFrame) {
      final me = ref.read(authStateProvider).user;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF1A0E3E),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FramedAvatar(
                  size: 160,
                  avatarSize: 110,
                  frame: AvatarFrame.fromUrl(product.fileUrl),
                  imageUrl: me?.avatarUrl,
                  fallbackText: me?.name ?? '',
                ),
                const SizedBox(height: 16),
                Text(product.name, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
        ),
      );
      return;
    }

    // Entrance/seat effect: fullscreen playback.
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: Stack(
            children: [
              Center(child: VideoPreview(url: product.fileUrl)),
              Positioned(
                top: 40,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ask for the recipient's 6-digit ID, then gift this product to them.
  Future<void> _promptSendProduct(BuildContext context, String productId) async {
    final ctrl = TextEditingController();
    final displayId = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF241246),
          title: const Text('إرسال المنتج', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 4),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: 'رقم المستلم (6 أرقام)',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text.trim());
                Navigator.pop(ctx, v);
              },
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (displayId == null || displayId <= 0) return;

    setState(() => loading = true);
    try {
      final token = await StorageService.getAccessToken();
      await StoreService().sendProduct(token ?? '', productId, displayId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال المنتج بنجاح')),
      );
      await ref.read(authStateProvider.notifier).refreshUser();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final isOwned = widget.isOwned;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          /// IMAGE / VIDEO — tap for a preview before buying (frame try-on /
          /// fullscreen entrance playback).
          Expanded(
            child: GestureDetector(
              onTap: () => _previewProduct(context, product),
              child: ClipRRect(
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
                child: isVideo(product.fileUrl)
                    ? SizedBox.expand(
                  child: VideoPreview(url: product.fileUrl),
                )
                    : Image.network(
                  product.fileUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          /// NAME
          Text(
            product.name,
            style: const TextStyle(color: Colors.white),
          ),

          const SizedBox(height: 4),

          /// PRICE
          Text(
            "${product.priceCoins} 🪙",
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          /// BUTTON
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ElevatedButton(
              // AFTER
              onPressed: (isOwned || loading)
                  ? null
                  : () async {
                setState(() => loading = true);
                try {
                  final token = await StorageService.getAccessToken();
                  final service = StoreService();
                  await service.buyProduct(token!, product.id.toString());
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Purchased successfully")),
                  );
                  final parent = context.findAncestorStateOfType<_StoreScreenState>();
                  parent?.loadOwnedItems();

                  await ref.read(authStateProvider.notifier).refreshUser();

                  // ✅ ADD THIS — refresh auth user so room seat gets updated frame/effect
                  await parent?.ref.read(authStateProvider.notifier).refreshUser();
                } catch (e) {
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }

                if (mounted) {
                  setState(() => loading = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                (isOwned || loading) ? Colors.grey : const Color(0xFF8E44AD),
                minimumSize: const Size(double.infinity, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: loading
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : Text(isOwned ? "Owned" : "شراء"),
            ),
          ),
          // Step 8: send this product to another user as a gift.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: OutlinedButton.icon(
              onPressed: loading
                  ? null
                  : () => _promptSendProduct(context, product.id.toString()),
              icon: const Icon(Icons.card_giftcard, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFC107),
                side: const BorderSide(color: Color(0xFFFFC107)),
                minimumSize: const Size(double.infinity, 34),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              label: const Text("إرسال"),
            ),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

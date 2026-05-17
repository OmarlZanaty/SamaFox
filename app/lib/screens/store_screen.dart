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
  bool loadingFrames = false;
  List<Map<String, dynamic>> myFrames = [];


  @override
  void initState() {
    super.initState();
    loadOwnedItems();
    loadMyFrames();
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
      debugPrint(e);
      setState(() => loadingInventory = false);
    }
  }

  Future<void> loadMyFrames() async {
    try {
      setState(() => loadingFrames = true);
      final token = await StorageService.getAccessToken();
      if (token == null) return;
      final service = StoreService();
      final frames = await service.getMyFrames(token);
      setState(() {
        myFrames = frames;
      });
    } catch (e) {
      debugPrint(e);
    } finally {
      if (mounted) setState(() => loadingFrames = false);
    }
  }

  Future<void> toggleFrame(Map<String, dynamic> frame) async {
    try {
      final token = await StorageService.getAccessToken();
      if (token == null) return;
      final service = StoreService();
      final isActive = frame['isActive'] == true;

      if (isActive) {
        await service.deactivateFrame(token);
      } else {
        await service.activateFrame(token, frame['id'].toString());
      }

      // Keep auth user in sync so room seat payload uses the latest active frame.
      await ref.read(authStateProvider.notifier).refreshUser();
      await loadMyFrames();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isActive ? "تم إلغاء التفعيل" : "تم التفعيل")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildTab("مركبة", "seat_effect"),
                        _buildTab("إطارات", "avatar_frame"),
                        _buildTab("الإطارات", "frames"),
                      ],
                    ),

                    const SizedBox(height: 10),

                    /// ✅ GRID
                    Expanded(
                      child: selectedType == "frames"
                          ? _buildFramesGrid()
                          : GridView.builder(
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

  Widget _buildFramesGrid() {
    if (loadingFrames) {
      return const Center(child: CircularProgressIndicator());
    }
    if (myFrames.isEmpty) {
      return const Center(
        child: Text("لا توجد إطارات مملوكة بعد", style: TextStyle(color: Colors.white70)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
      itemCount: myFrames.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (_, index) {
        final frame = myFrames[index];
        final isActive = frame['isActive'] == true;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A0E3E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? Colors.greenAccent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              if (isActive)
                const Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.check_circle, color: Colors.greenAccent),
                  ),
                ),
              Expanded(
                child: Image.network(
                  (frame['imageUrl'] ?? '').toString(),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  (frame['name'] ?? '').toString(),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ElevatedButton(
                  onPressed: () => toggleFrame(frame),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? Colors.redAccent : const Color(0xFF8E44AD),
                    minimumSize: const Size(double.infinity, 36),
                  ),
                  child: Text(isActive ? "إلغاء التفعيل" : "تفعيل"),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
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
          /// IMAGE / VIDEO
          Expanded(
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

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

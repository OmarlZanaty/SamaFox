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


  @override
  void initState() {
    super.initState();
    loadOwnedItems();
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
      print(e);
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
        final filtered = products
            .where((p) => p.type == selectedType)
            .toList();

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
                      ],
                    ),

                    const SizedBox(height: 10),

                    /// ✅ GRID
                    Expanded(
                      child: GridView.builder(
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
}

class StoreProductTile extends StatefulWidget {
  final Product product;
  final bool isOwned;

  const StoreProductTile({
    super.key,
    required this.product,
    required this.isOwned,
  });

  @override
  State<StoreProductTile> createState() => _StoreProductTileState();
}

class _StoreProductTileState extends State<StoreProductTile> {
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
              onPressed: (isOwned || loading)
                  ? null
                  : () async {
                setState(() => loading = true);

                try {
                  final token =
                  await StorageService.getAccessToken();
                  final service = StoreService();

                  await service.buyProduct(
                      token!, product.id.toString());

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Purchased successfully")),
                  );

                  /// 🔥 refresh inventory
                  final parent = context
                      .findAncestorStateOfType<_StoreScreenState>();
                  parent?.loadOwnedItems();

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


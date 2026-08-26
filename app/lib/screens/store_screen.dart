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
                          _buildTab("فقاعات", "chat_bubble"),
                          const SizedBox(width: 10),
                          _buildTab("إطارات", "avatar_frame"),
                          const SizedBox(width: 10),
                          _buildTab("شارات", "badge"),
                          const SizedBox(width: 10),
                          _buildTab("خلفيات", "background"),
                          const SizedBox(width: 10),
                          // B2/B3 — لوحة التحكم could create both of these but
                          // the store had no tab for either, so they were
                          // invisible and unbuyable.
                          _buildTab("خلفية الصفحة", "profile_background"),
                          const SizedBox(width: 10),
                          _buildTab("تزيين الصفحة", "profile_decor"),
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

  /// Delegates to the file-level helper so the tile and its poster can never
  /// disagree about what counts as a clip.
  bool isVideo(String url) => _isVideoUrl(url);

  /// Preview before buying: a frame is tried on the current user's own
  /// avatar; a seat effect plays full-screen; entrance banners and chat
  /// bubbles are still images, so they're shown in place instead. Everything
  /// else (badges, themes) just doesn't get a preview — tapping does nothing.
  void _previewProduct(BuildContext context, Product product) {
    final isFrame = product.type == 'avatar_frame';
    final isEffect = product.type == 'seat_effect';
    // 'entrance' used to be lumped in with seat effects and handed to the
    // video player, which could never render a banner PNG.
    final isStill = product.type == 'entrance' || product.type == 'chat_bubble';
    // B2/B3 — the two profile-page pieces. Both come as صورة or فيديو, and both
    // are only meaningful against a page-shaped box, so they share one preview:
    // a portrait card showing the background filling it, or the decoration
    // frame sitting on its border.
    final isPagePiece =
        product.type == 'profile_background' || product.type == 'profile_decor';
    if (!isFrame && !isEffect && !isStill && !isPagePiece) return;

    if (isPagePiece) {
      final isDecor = product.type == 'profile_decor';
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF1A0E3E),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 9:16 stands in for the profile page itself.
                AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The page's own gradient, so a decoration frame is
                        // judged against what it will actually sit on.
                        const DecoratedBox(
                          decoration: BoxDecoration(
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
                        ),
                        if (isVideo(product.fileUrl))
                          // A decoration frame is stretched to the page border,
                          // so its preview fills the box; a background clip is
                          // centred instead of squashed to the card's ratio.
                          isDecor
                              ? VideoPreview(url: product.fileUrl)
                              : Center(child: VideoPreview(url: product.fileUrl))
                        else
                          Image.network(
                            product.fileUrl,
                            // A background covers the page; a decoration frame
                            // is stretched to its border and must not be
                            // cropped, or its corners disappear.
                            fit: isDecor ? BoxFit.fill : BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image, color: Colors.white54),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(product.name,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
        ),
      );
      return;
    }

    if (isStill) {
      final isBubble = product.type == 'chat_bubble';
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF1A0E3E),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: isBubble ? 52 : 56,
                  padding: EdgeInsets.symmetric(
                    horizontal: isBubble ? 26 : 18,
                    vertical: 12,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage(product.fileUrl),
                      fit: BoxFit.fill,
                      onError: (_, __) {},
                    ),
                  ),
                  child: Text(
                    isBubble ? 'رسالة تجريبية' : 'اسمك دخل الغرفة',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                  ),
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
                // A25 — "المركبات ثقيلة جداً وقت فتح المتجر".
                //
                // Every video tile used to build its own VideoPlayerController
                // and autoplay it, so opening the مركبات tab spun up one live
                // decoder and one network stream PER VISIBLE PRODUCT — twenty
                // clips downloading and decoding at once on a phone. That is
                // the whole reason the store crawled.
                //
                // The grid now shows a still poster; the clip plays in the
                // preview the tile already opens on tap, one at a time. If the
                // dashboard supplied a separate preview image it is used,
                // otherwise the tile falls back to a static card rather than
                // paying for a decoder just to show a thumbnail.
                child: isVideo(product.fileUrl)
                    ? _VideoPosterTile(product: product)
                    : Image.network(
                  product.fileUrl,
                  fit: BoxFit.cover,
                  // A decoded full-resolution PNG per tile is the other half of
                  // the memory cost; the grid cell is ~200px wide.
                  cacheWidth: 320,
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

          const SizedBox(height: 2),

          /// TERM — how long the item lasts, so the decision to buy is made
          /// with the duration in view instead of after the fact.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                product.durationDays == null
                    ? Icons.all_inclusive
                    : Icons.schedule,
                size: 13,
                color: product.durationDays == null
                    ? const Color(0xFF4CD964)
                    : const Color(0xFFBDA9E8),
              ),
              const SizedBox(width: 4),
              Text(
                product.durationLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: product.durationDays == null
                      ? const Color(0xFF4CD964)
                      : const Color(0xFFBDA9E8),
                ),
              ),
            ],
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
                // Confirm with the term spelled out. Coins leave the wallet
                // the moment this call succeeds, so the duration has to be in
                // front of the user BEFORE that, not discovered afterwards.
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      backgroundColor: const Color(0xFF1A0E3E),
                      title: const Text('تأكيد الشراء',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                      content: Text(
                        '${product.name}\n'
                        'السعر: ${product.priceCoins} كوينز\n'
                        'المدة: ${product.durationLabel}',
                        style: const TextStyle(color: Colors.white70, height: 1.6),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: const Text('إلغاء'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, true),
                          child: const Text('شراء'),
                        ),
                      ],
                    ),
                  ),
                );
                if (confirmed != true) return;

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

/// Shared with `_StoreProductTileState.isVideo`, which delegates here so both
/// the tile and its poster agree on what counts as a clip.
bool _isVideoUrl(String url) {
  final u = url.toLowerCase();
  return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm');
}

/// A25 — a video product's grid cell, without a video player.
///
/// Uses the dashboard's separate preview image when there is one; otherwise it
/// draws a labelled placeholder. Either way it costs one image at most, versus
/// the live `VideoPlayerController` this replaces — which is what made opening
/// the مركبات tab so heavy.
class _VideoPosterTile extends StatelessWidget {
  const _VideoPosterTile({required this.product});

  final Product product;

  bool get _hasImagePoster {
    final url = product.previewUrl;
    return url.isNotEmpty && !_isVideoUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_hasImagePoster)
          Image.network(
            product.previewUrl,
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        else
          _placeholder(),
        // Makes it obvious the still is a clip you can play.
        const Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x66000000),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2A1A5E), Color(0xFF1A0E3E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 34),
    );
  }
}

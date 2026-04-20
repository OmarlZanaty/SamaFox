import 'package:flutter/material.dart';
import '../models/gift.dart';
import '../models/user.dart';
import '../repositories/gift_repository.dart';
import '../config/app_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'mega_gift_card.dart';
class GiftSelectionDialog extends StatefulWidget {
  final User? targetUser;
  final int roomId;
  final int currentUserCoins;
  final List<User> roomMembers;
  final Function(Gift gift, User? targetUser) onGiftSelected;

  const GiftSelectionDialog({
    Key? key,
    this.targetUser,
    required this.roomId,
    required this.currentUserCoins,
    this.roomMembers = const [],
    required this.onGiftSelected,
  }) : super(key: key);

  @override
  State<GiftSelectionDialog> createState() => _GiftSelectionDialogState();
}

class _GiftSelectionDialogState extends State<GiftSelectionDialog> {

  double get scale => MediaQuery.of(context).size.width / 375;


  double rs(double size) => size * scale;
  int _quantity = 1;
  final GiftRepository _repository = GiftRepository();
  final PageController _pageController = PageController();
  bool _showHearts = false;
  List<Gift> _gifts = [];
  List<Gift> _megaGifts = [];
  List<Gift> _normalGifts = [];

  bool _isLoading = true;
  Gift? _selectedGift;

  /// SINGLE USER (UI indicator)
  User? _selectedUser;

  /// MULTI USERS (sending)
  List<User> _selectedUsers = [];

  String _selectedCategory = 'all';
  List<Gift> _filtered = [];

  final Map<String, IconData> _categoryIcons = {
    'all': Icons.all_inclusive,
    'common': Icons.star_border,
    'rare': Icons.star_half,
    'epic': Icons.star,
    'RELATION_RING': Icons.favorite,
    'legendary': Icons.workspace_premium,
  };

  final List<String> _categories = [
    'all',
    'common',
    'rare',
    'epic',
    'legendary'
  ];

  @override
  void initState() {
    super.initState();

    // Clear the gift lists to reload them from the start
    _gifts.clear();
    _megaGifts.clear();
    _normalGifts.clear();
    _filtered.clear();

    _selectedUser = widget.targetUser;

    if (_selectedUser != null) {
      _selectedUsers.add(_selectedUser!);
    }

    _loadGifts();  // Call to fetch gifts again when dialog is opened
  }

  Future<void> _loadGifts() async {
    setState(() => _isLoading = true);

    final result = await _repository.getGifts();

    if (result.isSuccess && result.data != null) {
      setState(() {
        _gifts = result.data!;
        _megaGifts = _gifts.where((g) => g.animationKey != null).toList();
        _normalGifts = _gifts.where((g) => g.animationKey == null).toList();
        _filtered = _normalGifts;

        print("Mega Gifts Loaded: ${_megaGifts.length}"); // Debug print
        _isLoading = false;
      });
    } else {
      setState(() {
        _gifts = [];
        _megaGifts = [];
        _normalGifts = [];
        _filtered = [];
        _isLoading = false;

        print("Failed to load gifts: ${result.error}");
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    final screen = MediaQuery.of(context).size;
    final scale = screen.width / 375; // base iPhone width
    final height = MediaQuery.of(context).size.height;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1A0F3E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
            children: [
            /// drag handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            _buildUserSelector(),

            if (_megaGifts.isNotEmpty)
              _buildMegaGiftRow(),

            _buildCategoryTabs(),

            _buildBalanceBar(),

              _buildGiftPreview(),

              const SizedBox(height: 6),

              Flexible(
                child: _buildGiftGrid(),
              ),

            _buildPageIndicator((_filtered.length / 8).ceil()),

            _buildSendButton(),
          ],
        ),
      ),
    );
  }

  /// USER SELECTOR
  Widget _buildUserSelector() {

    return SizedBox(
      height: 65,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.roomMembers.length,
        itemBuilder: (context, index) {

          final user = widget.roomMembers[index];
          final selected = _selectedUsers.contains(user);

          return GestureDetector(
            onTap: () {

              setState(() {

                _selectedUser = user;

                if (selected) {
                  _selectedUsers.remove(user);
                } else {
                  _selectedUsers.add(user);
                }

              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                children: [

                  CircleAvatar(
                  radius: 18 * scale,
                  backgroundImage: user.avatarUrl != null
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(user.name[0])
                        : null,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    user.name,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? Colors.amber : Colors.white70,
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// CATEGORY TABS
  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = category;

                if (category == 'all') {
                  _filtered = _gifts;
                } else {
                  _filtered =
                      _gifts.where((g) => g.category == category).toList();
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.amber
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Row(
                children: [
                Icon(
                _categoryIcons[category],
                size: 14,
                color: selected ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                category.toUpperCase(),
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ]),
            )
          );
        },
      ),
    );
  }
  /// MEGA GIFTS
  Widget _buildMegaGiftRow() {

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _megaGifts.length,
        itemBuilder: (_, i) {

          final gift = _megaGifts[i];

          return GestureDetector(
            onTap: () {
              setState(() => _selectedGift = gift);
            },
            child: Container(
              width: 90,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFFD700),
                    Color(0xFFFF8C00)
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(.5),
                    blurRadius: 12,
                  )
                ],
              ),
              child: MegaGiftCard(
                gift: gift,
                selected: _selectedGift?.id == gift.id,
                onTap: () {
                  setState(() => _selectedGift = gift);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// BALANCE BAR
  Widget _buildBalanceBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [

          const Icon(Icons.monetization_on, color: Colors.amber),

          const SizedBox(width: 6),

          Text(
            "${widget.currentUserCoins}",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 14 * scale,
            ),
          ),

          const Spacer(),

          TextButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, "/wallet");
            },
            icon: const Icon(Icons.add_circle, color: Colors.amber),
            label: const Text(
              "Recharge",
              style: TextStyle(color: Colors.amber),
            ),
          ),

          Text(
            "Recipients: ${_selectedUsers.length}",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12 * scale,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftPreview() {

    if (_selectedGift == null) return const SizedBox();

    return AnimatedScale(
      scale: 1,
      duration: const Duration(milliseconds: 200),
      child: Column(
        children: [

          SizedBox(
            width: 110,
            height: 110,
            child: _buildGiftMedia(_selectedGift!),
          ),

          const SizedBox(height: 4),

          Text(
            _selectedGift!.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),

        ],
      ),
    );
  }

  /// GRID
  Widget _buildGiftCard(Gift gift) {

    final selected = _selectedGift?.id == gift.id;
    final glowColor = _getCategoryColor(gift.category ?? 'common');

    final isVip = (gift.category ?? '').toLowerCase() == 'legendary';

    return AnimatedScale(
        scale: selected ? 1.1 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.all(4),

    decoration: BoxDecoration(
    color: Colors.white.withOpacity(.05),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
    color: selected ? glowColor : Colors.transparent,
    width: 2,
    ),
    boxShadow: selected
    ? [
    BoxShadow(
    color: glowColor.withOpacity(.7),
    blurRadius: 14,
    spreadRadius: 1,
    )
    ]
        : [],
    ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [

          Container(
            width: 70,
            height: 70,
            alignment: Alignment.center,
            child: _buildGiftMedia(gift),
          ),

          const SizedBox(height: 6),

          Text(
            gift.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 10 * scale,
              decoration: TextDecoration.none,
            ),
          ),

          const SizedBox(height: 2),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              const Icon(
                Icons.monetization_on,
                color: Colors.amber,
                size: 12,
              ),

              const SizedBox(width: 2),

              Text(
                "${gift.displayCoinsValue}",
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 10 * scale,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ],
      ),
        ),

    );
  }

  Widget _buildHearts() {
    if (!_showHearts) return const SizedBox();

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: List.generate(6, (i) {
            return Positioned(
              bottom: 0,
              left: 40.0 * i,
              child: TweenAnimationBuilder(
                tween: Tween(begin: 0.0, end: -120.0),
                duration: const Duration(milliseconds: 900),
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, value),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.pinkAccent,
                      size: 18,
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ),
    );
  }


  Widget _buildPageIndicator(int pageCount) {

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SmoothPageIndicator(
        controller: _pageController,
        count: pageCount,
        effect: const WormEffect(
          dotHeight: 6,
          dotWidth: 16,
          activeDotColor: Colors.amber,
          dotColor: Colors.white24,
        ),
      ),
    );
  }

  Widget _buildGiftGrid() {

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.65,
      ),
      itemCount: _filtered.length,
      itemBuilder: (_, i) {

        final gift = _filtered[i];

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedGift = gift;
            });
          },
          child: _buildGiftCard(gift),
        );
      },
    );
  }

  Widget _buildSendButton() {

    return Column(
      children: [

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _qtyBtn(1),
            const SizedBox(width: 8),
            _qtyBtn(10),
            const SizedBox(width: 8),
            _qtyBtn(100),
          ],
        ),

        const SizedBox(height: 10),

        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purpleAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 40,
            ),
          ),
          onPressed: () => _sendGift(_quantity),
          child: Text(
            "Send x$_quantity",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
  Widget _qtyBtn(int value) {
    final active = value == _quantity;

    return GestureDetector(
      onTap: () {
        setState(() {
          _quantity = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.amber : Colors.white10,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          "x$value",
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _sendGift(int quantity) {

    if (_selectedGift == null) return;

    if (_selectedUsers.isEmpty) return;

    for (final user in _selectedUsers) {
      widget.onGiftSelected(_selectedGift!, user);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Sent ${_selectedGift!.displayName} x$quantity",
        ),
      ),
    );

    Navigator.pop(context);
  }

  Widget _buildGiftMedia(Gift gift) {
    final raw = (gift.imageUrl ?? '').trim();

    if (raw.isEmpty) {
      return Icon(
        _getGiftIcon(gift.displayName),
        color: _getCategoryColor(gift.category ?? 'common'),
        size: 34,
      );
    }

    /// ✅ EMOJI GIFTS
    if (_isEmojiLike(raw)) {
      return Center(
        child: Text(
          raw,
          style: const TextStyle(fontSize: 32),
        ),
      );
    }

    /// ✅ LOCAL ASSETS
    if (raw.startsWith('assets/')) {
      if (raw.toLowerCase().endsWith('.svg')) {
        return SvgPicture.asset(raw, fit: BoxFit.contain);
      }
      return Image.asset(raw, fit: BoxFit.cover);
    }

    /// ✅ NETWORK IMAGE
    final url = raw.startsWith('/') ? '${AppConfig.apiBaseUrl}$raw' : raw;
    if (url.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        url,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (_, __, ___) => Icon(
        _getGiftIcon(gift.displayName),
        color: _getCategoryColor(gift.category ?? 'common'),
        size: 34,
      ),
    );
  }

  /// detect emoji gifts
  bool _isEmojiLike(String value) {
    if (value.isEmpty) return false;

    final lower = value.toLowerCase();

    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        value.contains('/') ||
        value.contains('.png') ||
        value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.webp') ||
        value.contains('.gif')) {
      return false;
    }

    return value.runes.length <= 6;
  }

  /// fallback icon
  IconData _getGiftIcon(String giftName) {
    final name = giftName.toLowerCase();

    if (name.contains('rose') || name.contains('flower')) {
      return Icons.local_florist;
    } else if (name.contains('diamond') || name.contains('ring')) {
      return Icons.diamond;
    } else if (name.contains('car')) {
      return Icons.directions_car;
    } else if (name.contains('firework')) {
      return Icons.celebration;
    } else if (name.contains('heart') || name.contains('balloon')) {
      return Icons.favorite;
    } else if (name.contains('star')) {
      return Icons.star;
    } else if (name.contains('crown')) {
      return Icons.workspace_premium;
    }

    return Icons.card_giftcard;
  }

  /// category color
  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'common':
        return Colors.grey;

      case 'rare':
        return Colors.blue;

      case 'relation_ring':
        return const Color(0xFFFF4D8B); // pink/red special

      case 'epic':
        return Colors.purple;

      case 'legendary':
        return Colors.amber;

      default:
        return Colors.white;
    }
  }

  @override
  void dispose() {
    super.dispose();
    // Reset all lists when dialog is disposed.
    _gifts.clear();
    _megaGifts.clear();
    _normalGifts.clear();
    _filtered.clear();
  }
}

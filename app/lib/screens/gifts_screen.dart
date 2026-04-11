import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gift.dart';
import '../providers/locale_provider.dart';
import '../repositories/gift_repository.dart';
import '../utils/result.dart';

class GiftsScreen extends ConsumerStatefulWidget {
  const GiftsScreen({super.key});

  @override
  ConsumerState<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends ConsumerState<GiftsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GiftRepository _giftRepository = GiftRepository();
  late Future<Result<List<Gift>>> _giftsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _giftsFuture = _giftRepository.getGifts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          strings.gifts,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.card_giftcard, color: theme.iconTheme.color),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.searchComingSoon)),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
          labelColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
          unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
          tabs: [
            Tab(text: strings.giftStore),
            Tab(text: strings.myGifts),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGiftStoreTab(strings, theme, isDark),
          _buildMyGiftsTab(strings, theme, isDark),
        ],
      ),
    );
  }

  Widget _buildGiftStoreTab(dynamic strings, ThemeData theme, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0D0620) : Colors.grey.shade50,
      child: Column(
        children: [
          // Balance card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF6B4CE6), const Color(0xFF2D1B69)]
                    : [const Color(0xFF00A3FF), const Color(0xFF0077CC)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFF6B4CE6) : const Color(0xFF00A3FF))
                      .withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.balance,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.monetization_on,
                          color: isDark ? const Color(0xFFFFD700) : Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '1,250',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(strings.searchComingSoon)),
                    );
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(strings.addCoins),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: isDark ? const Color(0xFF6B4CE6) : const Color(0xFF00A3FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Gifts grid
          Expanded(
            child: FutureBuilder<Result<List<Gift>>>(
              future: _giftsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final result = snapshot.data;
                final gifts = (result != null && result.isSuccess && result.data != null)
                    ? result.data!
                    : <Gift>[];

                if (gifts.isEmpty) {
                  return Center(
                    child: Text(
                      strings.noGiftsAvailable,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _giftsFuture = _giftRepository.getGifts();
                    });
                    await _giftsFuture;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: gifts.length,
                    itemBuilder: (context, index) {
                      final gift = gifts[index];
                      return _buildGiftCard(gift, strings, theme, isDark);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftCard(
    Gift gift,
    dynamic strings,
    ThemeData theme,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () => _showBuyGiftDialog(gift, strings, theme, isDark),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: (gift.imageUrl ?? '').trim().isEmpty
                  ? const Icon(Icons.card_giftcard, size: 36, color: Colors.amber)
                  : Image.network(
                      gift.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.card_giftcard, size: 36, color: Colors.amber),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              gift.displayName,
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.monetization_on,
                  color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '${gift.displayCoinsValue}',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyGiftsTab(dynamic strings, ThemeData theme, bool isDark) {
    // Mock received gifts data
    final receivedGifts = [
      {'name': 'Rose', 'from': 'User 1', 'icon': '🌹', 'count': 5},
      {'name': 'Heart', 'from': 'User 2', 'icon': '❤️', 'count': 3},
      {'name': 'Diamond', 'from': 'User 3', 'icon': '💎', 'count': 1},
      {'name': 'Crown', 'from': 'User 4', 'icon': '👑', 'count': 2},
    ];

    if (receivedGifts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.card_giftcard_outlined,
              size: 80,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              strings.noGiftsAvailable,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: isDark ? const Color(0xFF0D0620) : Colors.grey.shade50,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: receivedGifts.length,
        itemBuilder: (context, index) {
          final gift = receivedGifts[index];
          return Card(
            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D1B69) : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    gift['icon'] as String,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              title: Text(
                gift['name'] as String,
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'From ${gift['from']}',
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFFFFD700).withOpacity(0.2)
                      : const Color(0xFF00A3FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'x${gift['count']}',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showBuyGiftDialog(
    Gift gift,
    dynamic strings,
    ThemeData theme,
    bool isDark,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        title: Text(
          strings.buy,
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: (gift.imageUrl ?? '').trim().isEmpty
                  ? const Icon(Icons.card_giftcard, size: 56, color: Colors.amber)
                  : Image.network(
                      gift.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.card_giftcard, size: 56, color: Colors.amber),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              gift.displayName,
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.monetization_on,
                  color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  '${gift.displayCoinsValue} ${strings.coins}',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              strings.cancel,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.purchaseSuccessful)),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            child: Text(strings.buy),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift.dart';
import '../providers/locale_provider.dart';
import '../repositories/gift_repository.dart';
import '../config/app_config.dart';

/// GiftStoreScreen displays the available gifts fetched from the backend.
/// It replaces the previous hard-coded list with data loaded from
/// GiftRepository. Users can browse gifts and view their prices. In a future
/// version, tapping on a gift could open a modal to select quantity and add
/// a message, but currently it only displays the items.
class GiftStoreScreen extends ConsumerStatefulWidget {
  const GiftStoreScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<GiftStoreScreen> createState() => _GiftStoreScreenState();
}

class _GiftStoreScreenState extends ConsumerState<GiftStoreScreen> {
  final GiftRepository _repository = GiftRepository();
  List<Gift> _gifts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    setState(() => _isLoading = true);
    final result = await _repository.getGifts();
    if (result.isSuccess && result.data != null) {
      _gifts = result.data!;
    } else {
      // Fallback to mock gifts on error
      _gifts = _repository.getMockGifts();
    }
    setState(() => _isLoading = false);
  }

  Widget _buildBottomBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      onTap: (index) {
        if (index == 0) {
          Navigator.pop(context); // back to home
        } else if (index == 1) {
          // TODO: navigate to search
        } else if (index == 2) {
          // TODO: navigate to profile
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      bottomNavigationBar: _buildBottomBar(context),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          strings.giftStore,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _gifts.length,
        itemBuilder: (context, index) {
          final gift = _gifts[index];
          final raw = (gift.imageUrl ?? '').trim();
          final url = raw.isEmpty
              ? ''
              : (raw.startsWith('http')
              ? raw
              : '${AppConfig.apiBaseUrl}$raw');
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                // TODO: open quantity/message modal when implemented
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  url.isNotEmpty
                      ? Image.network(
                    url,
                    height: 56,
                    width: 56,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.card_giftcard,
                      size: 40,
                      color: Colors.orange,
                    ),
                  )
                      : const Icon(
                    Icons.card_giftcard,
                    size: 40,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gift.name,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${gift.priceCoins}',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF00A3FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

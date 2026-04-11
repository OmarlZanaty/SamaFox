import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';
import '../repositories/gift_repository.dart';
import '../models/gift_history.dart';
import '../models/gift.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';

/// WalletScreen shows the user’s coin balance and their transaction history.
/// It fetches gift history via GiftRepository and displays incoming and
/// outgoing transactions along with optional messages. The statistics tab
/// still contains placeholder values and can be updated when real data is
/// available.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Gift history state
  final GiftRepository _giftRepository = GiftRepository();
  List<GiftTransaction> _transactions = [];
  Pagination? _pagination;
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    final result = await _giftRepository.getGiftHistory();
    if (result.isSuccess && result.data != null) {
      _transactions = result.data!.history;
      _pagination = result.data!.pagination;
    } else {
      _transactions = [];
    }
    setState(() => _isLoadingHistory = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Current user from auth provider to show balance and determine spend/earn
    final User? user = ref.watch(authStateProvider).user;
    final int balance = user?.userCoinsBalance ?? 0;

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
          strings.wallet,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Balance Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF6B4CE6), const Color(0xFF2D1B69)]
                    : [const Color(0xFF00A3FF), const Color(0xFF0077CC)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFF6B4CE6) : const Color(0xFF00A3FF))
                      .withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.myBalance,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: isDark ? const Color(0xFFFFD700) : Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      balance.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.coins,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(strings.searchComingSoon)),
                          );
                        },
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(strings.addCoins),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor:
                          isDark ? const Color(0xFF6B4CE6) : const Color(0xFF00A3FF),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(strings.searchComingSoon)),
                          );
                        },
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        label: Text(strings.withdrawal),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor:
              isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
              labelColor:
              isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
              unselectedLabelColor:
              theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              tabs: [
                Tab(text: strings.transactions),
                Tab(text: strings.statistics),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTransactionsTab(strings, theme, isDark),
                _buildStatisticsTab(strings, theme, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab(dynamic strings, ThemeData theme, bool isDark) {
    final user = ref.watch(authStateProvider).user;
    // Loading spinner while history loads
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    // No transactions case
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 80,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              strings.noTransactions,
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
        itemCount: _transactions.length,
        itemBuilder: (context, index) {
          final tx = _transactions[index];
          // Determine if current user sent or received
          final isSender = user != null && tx.senderId == user.id;
          final amount = isSender ? -tx.coinsSpent : tx.coinsSpent;
          final isPositive = amount > 0;
          final type = isSender ? 'spend' : 'earn';
          // Build description based on gift and participants
          final giftName = tx.gift?.name ?? '';
          final otherName = isSender
              ? (tx.receiver?.name ?? 'Unknown')
              : (tx.sender?.name ?? 'Unknown');
          final description = isSender
              ? 'Sent $giftName to $otherName'
              : 'Received $giftName from $otherName';
          // Parse date
          final dateStr = tx.createdAt;
          String displayDate = dateStr;
          try {
            final parsed = DateTime.parse(dateStr);
            displayDate =
            '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
          } catch (_) {}

          IconData icon;
          Color iconColor;
          switch (type) {
            case 'earn':
              icon = Icons.card_giftcard;
              iconColor = Colors.green;
              break;
            case 'spend':
              icon = Icons.shopping_bag;
              iconColor = Colors.red;
              break;
            default:
              icon = Icons.monetization_on;
              iconColor = Colors.grey;
          }

          return Card(
            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              title: Text(
                description,
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    displayDate,
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                  if (tx.message != null && tx.message!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        tx.message!,
                        style: TextStyle(
                          color:
                          theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
              trailing: Text(
                '${isPositive ? '+' : ''}$amount',
                style: TextStyle(
                  color: isPositive ? Colors.green : Colors.red,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Placeholder statistics tab. Replace with real data when available.
  Widget _buildStatisticsTab(dynamic strings, ThemeData theme, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0D0620) : Colors.grey.shade50,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatCard(
            strings.totalVisitors,
            '2,450',
            Icons.trending_up,
            Colors.green,
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            '${strings.coins} ${strings.earned}',
            '1,850',
            Icons.monetization_on,
            Colors.blue,
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            '${strings.coins} ${strings.send}',
            '600',
            Icons.send,
            Colors.orange,
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            strings.pending,
            '200',
            Icons.pending,
            Colors.purple,
            theme,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title,
      String value,
      IconData icon,
      Color color,
      ThemeData theme,
      bool isDark,
      ) {
    return Card(
      color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: Text(
          value,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

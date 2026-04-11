import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  String _selectedPlan = 'monthly';

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0620) : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          strings.premium,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Premium header
          Container(
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
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 80,
                  color: isDark ? const Color(0xFFFFD700) : Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  strings.upgradeToPremium,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlock exclusive features and benefits',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Features list
          Text(
            strings.premiumFeatures,
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildFeatureCard(
            Icons.verified,
            strings.exclusiveBadge,
            'Stand out with a premium badge',
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.card_giftcard,
            strings.unlimitedGifts,
            'Send unlimited gifts to friends',
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.support_agent,
            strings.prioritySupport,
            '24/7 priority customer support',
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.block,
            strings.adFree,
            'Enjoy ad-free experience',
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.palette,
            strings.customThemes,
            'Access to exclusive themes',
            theme,
            isDark,
          ),
          const SizedBox(height: 24),

          // Pricing plans
          Text(
            'Choose Your Plan',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildPlanCard(
            'monthly',
            strings.monthly,
            '\$9.99',
            '/month',
            'Billed monthly',
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildPlanCard(
            'yearly',
            strings.yearly,
            '\$99.99',
            '/year',
            'Save 17% - Best Value!',
            theme,
            isDark,
            isPopular: true,
          ),
          const SizedBox(height: 12),
          _buildPlanCard(
            'lifetime',
            strings.lifetime,
            '\$299.99',
            'one-time',
            'Pay once, enjoy forever',
            theme,
            isDark,
          ),
          const SizedBox(height: 24),

          // Subscribe button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.searchComingSoon)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                foregroundColor: isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 5,
              ),
              child: Text(
                strings.subscribe,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
    IconData icon,
    String title,
    String description,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    String planId,
    String title,
    String price,
    String period,
    String description,
    ThemeData theme,
    bool isDark, {
    bool isPopular = false,
  }) {
    final isSelected = _selectedPlan == planId;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlan = planId;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                : (isDark ? Colors.white10 : Colors.grey.shade200),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                        .withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Radio<String>(
                      value: planId,
                      groupValue: _selectedPlan,
                      onChanged: (value) {
                        setState(() {
                          _selectedPlan = value!;
                        });
                      },
                      activeColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: TextStyle(
                        color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        period,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    color: isPopular ? Colors.green : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: isPopular ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            if (isPopular)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'POPULAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

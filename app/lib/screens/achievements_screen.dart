import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';
import '../providers/gamification_provider.dart';
import '../providers/auth_provider.dart';
import '../models/achievement.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final authState = ref.watch(authStateProvider);
    final userId = authState.user?.id;

    if (userId == null) {
      return const Center(child: Text('Please log in to view achievements.'));
    }

    final userAchievementsAsync = ref.watch(userAchievementsProvider(userId));

    return userAchievementsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
      data: (userAchievements) {
        final allAchievementsAsync = ref.watch(achievementsProvider);

        return allAchievementsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (allAchievements) {
            final achievementsMap = {for (var a in allAchievements) a.id: a};
            final unlockedAchievements = userAchievements.map((ua) {
              final achievement = achievementsMap[ua.achievementId];
              return achievement != null ? ua.copyWith(achievement: achievement) : null;
            }).whereType<UserAchievement>().toList();

            final unlockedCount = unlockedAchievements.length;
            final totalCount = allAchievements.length;
            final progressValue = totalCount > 0 ? unlockedCount / totalCount : 0.0;

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
                  strings.achievements,
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              body: Column(
                children: [
                  // Progress card
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
                    ),
                    child: Column(
                      children: [
                        Text(
                          strings.totalAchievements,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$unlockedCount / $totalCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? const Color(0xFFFFD700) : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Achievements grid
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: allAchievements.length,
                      itemBuilder: (context, index) {
                        final achievement = allAchievements[index];
                        final userAchievement = unlockedAchievements.firstWhere(
                              (ua) => ua.achievementId == achievement.id,
                          orElse: () => UserAchievement(
                            id: '0',
                            userId: userId,
                            achievementId: achievement.id,
                            unlockedAt: DateTime.fromMillisecondsSinceEpoch(0),
                            achievement: achievement,
                          ),
                        );
                        final unlocked = userAchievement.id != '0';
                        return _buildAchievementCard(
                          context,
                          theme,
                          strings,
                          achievement,
                          unlocked,
                          userAchievement.unlockedAt,
                          isDark,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAchievementCard(
      BuildContext context,
      ThemeData theme,
      dynamic strings,
      Achievement achievement,
      bool unlocked,
      DateTime unlockedAt,
      bool isDark,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
              : (isDark ? Colors.white10 : Colors.grey.shade200),
          width: unlocked ? 2 : 1,
        ),
        boxShadow: unlocked
            ? [
          BoxShadow(
            color: (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                .withOpacity(0.3),
            blurRadius: 12,
          ),
        ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getIconForAchievement(achievement.metric),
            size: 48,
            color: unlocked
                ? (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                : theme.iconTheme.color?.withOpacity(0.3),
          ),
          const SizedBox(height: 12),
          Text(
            achievement.name,
            style: TextStyle(
              color: unlocked
                  ? theme.textTheme.bodyLarge?.color
                  : theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            achievement.description,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (unlocked) ...[
            const SizedBox(height: 8),
            Text(
              '${strings.earnedOn} ${unlockedAt.toLocal().toString().split(' ')[0]}',
              style: TextStyle(
                color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (!unlocked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.lock,
                size: 20,
                color: theme.iconTheme.color?.withOpacity(0.3),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getIconForAchievement(String metric) {
    switch (metric) {
      case 'create_room':
        return Icons.flag;
      case 'make_friends':
        return Icons.people;
      case 'send_messages':
        return Icons.chat;
      case 'send_gifts':
        return Icons.card_giftcard;
      case 'get_followers':
        return Icons.star;
      case 'subscribe_premium':
        return Icons.workspace_premium;
      default:
        return Icons.emoji_events;
    }
  }
}

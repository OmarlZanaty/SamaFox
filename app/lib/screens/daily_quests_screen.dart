import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/gamification_provider.dart';
import '../providers/locale_provider.dart';
import '../models/quest.dart';

class DailyQuestsScreen extends ConsumerWidget {
  const DailyQuestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final questsAsync = ref.watch(dailyQuestsProvider);


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
          'Daily Quests',
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: questsAsync.when(
        data: (quests) {
          if (quests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 80,
                    color: theme.iconTheme.color?.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No quests available',
                    style: TextStyle(
                      fontSize: 18,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            );
          }

          final completedCount = quests.where((q) => q.isComplete).length;

          return Column(
            children: [
              // Progress header
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
                    const Text(
                      'Daily Progress',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$completedCount / ${quests.length}',
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
                        value: completedCount / quests.length,
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
              // Quests list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: quests.length,
                  itemBuilder: (context, index) {
                    final quest = quests[index];
                    return _buildQuestCard(context, ref, quest, isDark, theme);
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error loading quests: $error',
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestCard(
      BuildContext context,
      WidgetRef ref,
      QuestWithProgress quest,
      bool isDark,
      ThemeData theme,
      ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: quest.isComplete ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: quest.isComplete
              ? (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
              : (isDark ? Colors.white10 : Colors.grey.shade200),
          width: quest.isComplete ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: quest.isComplete
                        ? (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                        : theme.iconTheme.color?.withOpacity(0.1),
                  ),
                  child: Icon(
                    quest.isComplete ? Icons.check_circle : _getIconForMetric(quest.metric),
                    color: quest.isComplete
                        ? Colors.white
                        : theme.iconTheme.color?.withOpacity(0.5),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Title and description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quest.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        quest.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // Reward
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFFFFD700).withOpacity(0.2) : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.monetization_on,
                        size: 16,
                        color: isDark ? const Color(0xFFFFD700) : Colors.amber.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${quest.rewardCoins}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFFFD700) : Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Progress bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress: ${quest.progress} / ${quest.target}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                    Text(
                      '${quest.progressPercentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: quest.isComplete
                            ? (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                            : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: quest.progressPercentage / 100,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      quest.isComplete
                          ? (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF))
                          : (isDark ? const Color(0xFF6B4CE6) : const Color(0xFF00A3FF)),
                    ),
                  ),
                ),
              ],
            ),
            if (quest.isComplete) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final questNotifier = ref.read(questNotifierProvider.notifier);
                  await questNotifier.completeQuest(quest.id.toString());
                  ref.invalidate(dailyQuestsProvider);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Claim Reward',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF)).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Completed!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getIconForMetric(String metric) {
    switch (metric) {
      case 'send_gift':
        return Icons.card_giftcard;
      case 'join_room':
        return Icons.meeting_room;
      case 'send_message':
        return Icons.chat;
      default:
        return Icons.assignment;
    }
  }
}

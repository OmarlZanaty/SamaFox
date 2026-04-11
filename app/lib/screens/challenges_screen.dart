import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final challenges = [
      {'title': 'Daily Login', 'progress': 5, 'total': 7, 'reward': 50, 'status': 'in_progress'},
      {'title': 'Send 10 Messages', 'progress': 10, 'total': 10, 'reward': 100, 'status': 'completed'},
      {'title': 'Join 5 Rooms', 'progress': 3, 'total': 5, 'reward': 75, 'status': 'in_progress'},
      {'title': 'Make 3 Friends', 'progress': 0, 'total': 3, 'reward': 150, 'status': 'not_started'},
    ];

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
          strings.challenges,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: challenges.length,
        itemBuilder: (context, index) {
          final challenge = challenges[index];
          final progress = challenge['progress'] as int;
          final total = challenge['total'] as int;
          final status = challenge['status'] as String;
          final progressPercent = progress / total;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                        Icons.emoji_events,
                        color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            challenge['title'] as String,
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.monetization_on,
                                size: 14,
                                color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '+${challenge['reward']} ${strings.coins}',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (status == 'completed')
                      ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(strings.searchComingSoon)),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(strings.claimReward),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${strings.progress}: $progress/$total',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${(progressPercent * 100).toInt()}%',
                          style: TextStyle(
                            color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progressPercent,
                        minHeight: 8,
                        backgroundColor: isDark ? const Color(0xFF0D0620) : Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

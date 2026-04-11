import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final blockedUsers = [
      {'name': 'Blocked User 1'},
      {'name': 'Blocked User 2'},
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
          strings.blockedUsers,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: blockedUsers.length,
        itemBuilder: (context, index) {
          final user = blockedUsers[index];
          return Card(
            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isDark ? const Color(0xFF2D1B69) : Colors.blue.shade100,
                child: Icon(Icons.person, color: isDark ? Colors.white70 : Colors.blue.shade700),
              ),
              title: Text(
                user['name'] as String,
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: TextButton(
                onPressed: () {},
                child: Text(
                  'Unblock',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

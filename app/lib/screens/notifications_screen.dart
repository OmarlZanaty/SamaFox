import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final notifications = [
      {'type': 'follow', 'user': 'User 1', 'message': strings.newFollower, 'time': '2h ago', 'read': false},
      {'type': 'message', 'user': 'User 2', 'message': strings.newMessage, 'time': '5h ago', 'read': false},
      {'type': 'gift', 'user': 'User 3', 'message': strings.giftReceived, 'time': '1d ago', 'read': true},
      {'type': 'invite', 'user': 'User 4', 'message': strings.roomInvite, 'time': '2d ago', 'read': true},
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
          strings.notification,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.searchComingSoon)),
              );
            },
            child: Text(
              strings.markAllRead,
              style: TextStyle(
                color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: isDark ? const Color(0xFF0D0620) : Colors.grey.shade50,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notif = notifications[index];
            final isRead = notif['read'] as bool;
            IconData icon;
            Color iconColor;
            switch (notif['type']) {
              case 'follow':
                icon = Icons.person_add;
                iconColor = Colors.blue;
                break;
              case 'message':
                icon = Icons.message;
                iconColor = Colors.green;
                break;
              case 'gift':
                icon = Icons.card_giftcard;
                iconColor = Colors.purple;
                break;
              case 'invite':
                icon = Icons.group_add;
                iconColor = Colors.orange;
                break;
              default:
                icon = Icons.notifications;
                iconColor = Colors.grey;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isRead
                    ? (isDark ? const Color(0xFF1A0E3E) : Colors.white)
                    : (isDark
                        ? const Color(0xFF6B4CE6).withOpacity(0.1)
                        : const Color(0xFF00A3FF).withOpacity(0.05)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isRead
                      ? (isDark ? Colors.white10 : Colors.grey.shade200)
                      : (isDark ? const Color(0xFFFFD700).withOpacity(0.3) : const Color(0xFF00A3FF).withOpacity(0.3)),
                ),
              ),
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
                title: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${notif['user']} ',
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: notif['message'] as String,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    notif['time'] as String,
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
                trailing: !isRead
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

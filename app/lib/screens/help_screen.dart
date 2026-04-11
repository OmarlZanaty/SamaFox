import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          strings.help,
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
          _buildHelpCard(
            Icons.help_outline,
            strings.faq,
            'Find answers to common questions',
            () {},
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildHelpCard(
            Icons.support_agent,
            strings.contactSupport,
            'Get help from our support team',
            () {},
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildHelpCard(
            Icons.bug_report,
            strings.reportProblem,
            'Report a bug or issue',
            () {},
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildHelpCard(
            Icons.feedback,
            strings.sendFeedback,
            'Share your thoughts with us',
            () {},
            theme,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCard(
    IconData icon,
    String title,
    String description,
    VoidCallback onTap,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
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
      child: ListTile(
        leading: Container(
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
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            fontSize: 13,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: theme.iconTheme.color?.withOpacity(0.5),
        ),
        onTap: onTap,
      ),
    );
  }
}

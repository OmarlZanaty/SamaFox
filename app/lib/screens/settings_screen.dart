import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentLocale = ref.watch(localeProvider);
    final isDarkMode = ref.watch(themeProvider) == ThemeMode.dark;

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
          strings.settings,
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
          // Account Settings Section
          _buildSectionTitle(strings.accountSettings, theme, isDark),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildSettingsTile(
                icon: Icons.person_outline,
                title: strings.editProfile,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.lock_outline,
                title: strings.changePassword,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.block,
                title: strings.blockedUsers,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Appearance Section
          _buildSectionTitle(strings.theme, theme, isDark),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildSwitchTile(
                icon: Icons.dark_mode_outlined,
                title: strings.darkMode,
                value: isDarkMode,
                onChanged: (value) {
                  ref.read(themeProvider.notifier).toggleTheme();
                },
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Language Section
          _buildSectionTitle(strings.language, theme, isDark),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildRadioTile(
                title: 'English',
                value: currentLocale.locale.languageCode == 'en',
                onTap: () {
                  ref.read(localeProvider.notifier).setLocale('en');
                },
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildRadioTile(
                title: 'العربية',
                value: currentLocale.locale.languageCode == 'ar',
                onTap: () {
                  ref.read(localeProvider.notifier).setLocale('ar');
                },
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Notifications Section
          _buildSectionTitle(strings.notifications, theme, isDark),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildSettingsTile(
                icon: Icons.notifications_outlined,
                title: strings.notifications,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Privacy & Security Section
          _buildSectionTitle(strings.privacy, theme, isDark),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildSettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: strings.privacyPolicy,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.description_outlined,
                title: strings.termsOfService,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // About Section
          _buildSectionTitle(strings.about, theme, isDark),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildSettingsTile(
                icon: Icons.info_outline,
                title: strings.about,
                trailing: Text(
                  '${strings.version} 1.0.0',
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.help_outline,
                title: strings.help,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.searchComingSoon)),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Danger Zone
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildSettingsTile(
                icon: Icons.logout,
                title: strings.logout,
                onTap: () => _showLogoutDialog(context, strings, theme, isDark),
                theme: theme,
                isDark: isDark,
                isDestructive: true,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.delete_forever,
                title: strings.deleteAccount,
                onTap: () => _showDeleteAccountDialog(context, strings, theme, isDark),
                theme: theme,
                isDark: isDark,
                isDestructive: true,
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSettingsCard({
    required ThemeData theme,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
    required ThemeData theme,
    required bool isDark,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive
            ? Colors.red
            : (isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF)),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : theme.textTheme.bodyLarge?.color,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right,
            color: theme.iconTheme.color?.withOpacity(0.5),
          ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ThemeData theme,
    required bool isDark,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required bool value,
    required VoidCallback onTap,
    required ThemeData theme,
    required bool isDark,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Radio<bool>(
        value: true,
        groupValue: value,
        onChanged: (_) => onTap(),
        activeColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
      ),
      onTap: onTap,
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      color: isDark ? Colors.white10 : Colors.grey.shade200,
    );
  }

  void _showLogoutDialog(
      BuildContext context,
      dynamic strings,
      ThemeData theme,
      bool isDark,
      ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        title: Text(
          strings.logout,
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        content: Text(
          strings.logoutConfirm,
          style: TextStyle(color: theme.textTheme.bodyMedium?.color),
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
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement logout
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.searchComingSoon)),
              );
            },
            child: Text(
              strings.logout,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(
      BuildContext context,
      dynamic strings,
      ThemeData theme,
      bool isDark,
      ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        title: Text(
          strings.deleteAccount,
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        content: Text(
          strings.deleteAccountConfirm,
          style: TextStyle(color: theme.textTheme.bodyMedium?.color),
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
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement delete account
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.searchComingSoon)),
              );
            },
            child: Text(
              strings.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

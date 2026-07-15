import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/dio_client.dart';
import '../services/user_account_service.dart';
import 'blocked_users_screen.dart';
import 'edit_profile_screen.dart';

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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EditProfileScreen()),
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.swap_horiz,
                title: 'تبديل الحساب',
                onTap: () => _showSwitchAccountDialog(context, ref, strings, theme, isDark),
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.currency_exchange,
                title: 'تبديل الكوينزات',
                onTap: () => _showTargetConvertDialog(context, theme, isDark),
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
                onTap: () => _showLogoutDialog(context, ref, strings, theme, isDark),
                theme: theme,
                isDark: isDark,
                isDestructive: true,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.delete_forever,
                title: strings.deleteAccount,
                onTap: () => _showDeleteAccountDialog(context, ref, strings, theme, isDark),
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

  /// Signs out and returns to the login screen, clearing the whole stack.
  Future<void> _logoutToLogin(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    await ref.read(authStateProvider.notifier).logout();
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _showLogoutDialog(
      BuildContext context,
      WidgetRef ref,
      dynamic strings,
      ThemeData theme,
      bool isDark,
      ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              strings.cancel,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _logoutToLogin(context, ref);
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

  /// تبديل الحساب: sign out of this account and go to the login screen to
  /// sign in with a different one.
  void _showSwitchAccountDialog(
      BuildContext context,
      WidgetRef ref,
      dynamic strings,
      ThemeData theme,
      bool isDark,
      ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        title: Text(
          'تبديل الحساب',
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        content: Text(
          'سيتم تسجيل خروجك للدخول بحساب آخر. متابعة؟',
          style: TextStyle(color: theme.textTheme.bodyMedium?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              strings.cancel,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _logoutToLogin(context, ref);
            },
            child: const Text('تبديل'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(
      BuildContext context,
      WidgetRef ref,
      dynamic strings,
      ThemeData theme,
      bool isDark,
      ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        title: Text(
          strings.deleteAccount,
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        content: Text(
          'سيتم حذف حسابك نهائياً ولن تتمكن من الدخول به مرة أخرى. هل أنت متأكد؟',
          style: TextStyle(color: theme.textTheme.bodyMedium?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              strings.cancel,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await UserAccountService.deleteAccount();
                if (context.mounted) await _logoutToLogin(context, ref);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذّر حذف الحساب: $e')),
                  );
                }
              }
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

  /// تبديل الكوينزات — cash out accumulated (uncashed) target at 50% into
  /// spendable coins. Target total itself is unaffected.
  void _showTargetConvertDialog(BuildContext context, ThemeData theme, bool isDark) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _TargetConvertDialog(theme: theme, isDark: isDark),
    );
  }
}

class _TargetConvertDialog extends StatefulWidget {
  const _TargetConvertDialog({required this.theme, required this.isDark});
  final ThemeData theme;
  final bool isDark;

  @override
  State<_TargetConvertDialog> createState() => _TargetConvertDialogState();
}

class _TargetConvertDialogState extends State<_TargetConvertDialog> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _selected;
  final _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.dio.get('/agencies/my-target');
      final data = (res.data as Map)['data'] as Map;
      final items = ((data['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => (e['convertibleCoins'] as num?) != null)
          .toList();
      setState(() {
        _items = items;
        _selected = items.isNotEmpty ? items.first : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'تعذّر تحميل التارجت';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final sel = _selected;
    if (sel == null) return;
    final amount = int.tryParse(_amountCtrl.text.trim());
    final convertible = (sel['convertibleCoins'] as num?)?.toInt() ?? 0;
    if (amount == null || amount <= 0 || amount > convertible) {
      setState(() => _error = 'أدخل مبلغًا صحيحًا لا يتجاوز $convertible كوينز');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await DioClient.dio.post('/agencies/target/convert', data: {
        'agencyId': sel['agencyId'],
        'amount': amount,
      });
      final data = (res.data as Map)['data'] as Map;
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إضافة ${data['creditedCoins']} كوينز لرصيدك')),
        );
      }
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'فشل التبديل: $e';
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = widget.isDark;
    final convertible = (_selected?['convertibleCoins'] as num?)?.toInt() ?? 0;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
      title: Text('تبديل الكوينزات', style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      content: _loading
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : _items.isEmpty
              ? Text(
                  'لا يوجد تارجت متاح للتبديل حاليًا',
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المتاح للتبديل: $convertible كوينز (سيتحول نصفه، ${convertible ~/ 2} كحد أقصى، لرصيدك)',
                      style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ المراد تبديله',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        if (_items.isNotEmpty)
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('تبديل'),
          ),
      ],
    );
  }
}

import 'link_phone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'about_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/dio_client.dart';
import '../services/user_account_service.dart';
import 'blocked_users_screen.dart';
import 'dm_privacy_screen.dart';
import 'broadcast_time_screen.dart';
import 'edit_profile_screen.dart';
import '../providers/staff_provider.dart';
import 'staff/staff_ban_screen.dart';
import 'staff/staff_panel_screen.dart';
import '../l10n/tr.dart';

/// What the signed-in account is actually allowed to do with التارجت, so the
/// settings screen only offers the actions that can succeed.
class _TargetActions {
  const _TargetActions({
    required this.canSell,
    required this.canConvert,
    this.blocked = false,
  });
  const _TargetActions.none()
      : canSell = false,
        canConvert = false,
        blocked = false;

  /// Has target left to sell to another account. Host or وكيل — selling stopped
  /// being an owner-only action in 2026-08.
  final bool canSell;

  /// Has a hosting membership with target left to convert.
  final bool canConvert;

  /// Admin has stopped this account selling or converting. The tiles stay
  /// visible but disabled — a hidden tile reads as a bug, a disabled one with
  /// a reason reads as a decision.
  final bool blocked;
}

final _targetActionsProvider = FutureProvider.autoDispose<_TargetActions>((ref) async {
  try {
    final res = await DioClient.dio.get('/agencies/my-target');
    final data = (res.data as Map)['data'] as Map;
    final items = (data['items'] as List?) ?? const [];
    return _TargetActions(
      // Selling is open to hosts and agents alike since 2026-08; the server
      // says whether this account has anything sellable. `canSellMemberTarget`
      // is the old key, still sent with the same value.
      canSell: data['canSellTarget'] == true || data['canSellMemberTarget'] == true,
      canConvert: items.any(
        (e) => e is Map && ((e['convertibleCoins'] as num?)?.toInt() ?? 0) > 0,
      ),
      blocked: data['targetSellBlocked'] == true,
    );
  } catch (_) {
    // Older server or offline — hide the section rather than offer a dead tile.
    return const _TargetActions.none();
  }
});

/// «منح المميزات» — what the admin granted this account. Only granted
/// features get a row; the server re-checks every one of them where it is used.
final _myFeaturesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await DioClient.dio.get('/users/me/features');
    final list = ((res.data as Map)['data'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } catch (_) {
    return const [];
  }
});

/// الدخول المخفي — ON: entering a room shows nobody an entrance notice. The
/// switch only records the choice; the server applies it on every entry.
class _HiddenModeSwitch extends StatefulWidget {
  const _HiddenModeSwitch({required this.initial});
  final bool initial;
  @override
  State<_HiddenModeSwitch> createState() => _HiddenModeSwitchState();
}

class _HiddenModeSwitchState extends State<_HiddenModeSwitch> {
  late bool _on = widget.initial;
  bool _busy = false;

  Future<void> _set(bool v) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _on = v;
    });
    try {
      final res = await DioClient.dio.put('/users/me/features/HIDDEN_MODE', data: {'on': v});
      final on = ((res.data as Map)['data'] as Map?)?['on'] == true;
      if (mounted) setState(() => _on = on);
    } catch (e) {
      if (!mounted) return;
      setState(() => _on = !v);
      final msg = e is DioException ? (e.error?.toString() ?? tr('تعذر الحفظ', 'Unable to save')) : tr('تعذر الحفظ', 'Unable to save');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ListTile(
      leading: Icon(Icons.visibility_off_outlined, color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF)),
      title: Text(tr('الدخول المخفي', 'Invisible entry'), style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.w500)),
      subtitle: Text(
        _on ? tr('ON — لا يظهر دخولك للمستخدمين', 'ON — your entry is hidden from other users') : tr('غير مفعل', 'OFF'),
        style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 12),
      ),
      trailing: Switch(
        value: _on,
        onChanged: _busy ? null : _set,
        activeColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final targetActions =
        ref.watch(_targetActionsProvider).valueOrNull ?? const _TargetActions.none();
    final features = ref.watch(_myFeaturesProvider).valueOrNull ?? const [];
    final hiddenMode = features.where((f) => f['key'] == 'HIDDEN_MODE').firstOrNull;
    // نظام الإدارة — what the server says this account holds right now. The
    // provider refreshes on the staff_access_changed socket event and on resume,
    // so a withdrawn role disappears from here without reopening the app.
    final staff = ref.watch(staffMeProvider).valueOrNull;
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
              // قفل الرسائل الخاصة — عامة / الأصدقاء فقط / بكوينز.
              _buildSettingsTile(
                icon: Icons.lock_outline,
                title: tr('قفل الرسائل الخاصة', 'Lock private messages'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DmPrivacyScreen()),
                  );
                },
                theme: theme,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                icon: Icons.swap_horiz,
                title: tr('تبديل الحساب', 'Switch account'),
                onTap: () => _showSwitchAccountDialog(context, ref, strings, theme, isDark),
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // نظام الإدارة — only the systems this account actually holds.
          if (staff != null && (staff.rolePanel || staff.ban)) ...[
            _buildSectionTitle(tr('نظام الإدارة', 'Management system'), theme, isDark),
            const SizedBox(height: 12),
            _buildSettingsCard(
              theme: theme,
              isDark: isDark,
              children: [
                if (staff.rolePanel)
                  _buildSettingsTile(
                    icon: staff.manager
                        ? Icons.workspace_premium
                        : staff.role == 'SUPER_ADMIN'
                            ? Icons.diamond_outlined
                            : Icons.shield_outlined,
                    title: StaffPanelScreen.titleFor(staff.role),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StaffPanelScreen()),
                    ),
                    theme: theme,
                    isDark: isDark,
                  ),
                if (staff.rolePanel && staff.ban) _buildDivider(isDark),
                if (staff.ban)
                  _buildSettingsTile(
                    icon: Icons.gpp_bad_outlined,
                    title: tr('🚫 نظام الحظر', '🚫 Ban system'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StaffBanScreen()),
                    ),
                    theme: theme,
                    isDark: isDark,
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Target Actions Section — "بيع التارجت" moves target to another
          // account by ID (any amount, up to all of it); "تبديل الكوينزات"
          // cashes half of it into your own wallet. Both are open to hosts and
          // agents alike since 2026-08.
          //
          // Still gated on having something to act on: a membership with target
          // left. Showing them to everyone meant most users tapped a tile that
          // could only answer 403/empty.
          if (targetActions.canSell || targetActions.canConvert) ...[
            _buildSectionTitle(tr('إجراءات المستهدف', 'Target actions'), theme, isDark),
            const SizedBox(height: 12),
            _buildSettingsCard(
              theme: theme,
              isDark: isDark,
              children: [
                if (targetActions.blocked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 16, color: Color(0xFFFF9800)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('تم إيقاف بيع واستبدال التارجيت لحسابك من قِبَل الإدارة', 'Management has disabled target sales and exchanges for your account'),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.orange.shade200 : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (targetActions.canSell)
                  _buildSettingsTile(
                    icon: Icons.sell_outlined,
                    title: tr('بيع التارجت', 'Sell target'),
                    // Blocked accounts see the tile greyed out rather than
                    // tapping through to a 403.
                    onTap: targetActions.blocked
                        ? null
                        : () => _showSellTargetDialog(context, theme, isDark),
                    theme: theme,
                    isDark: isDark,
                  ),
                if (targetActions.canSell && targetActions.canConvert)
                  _buildDivider(isDark),
                if (targetActions.canConvert)
                  _buildSettingsTile(
                    icon: Icons.currency_exchange,
                    title: tr('تبديل الكوينزات', 'Exchange coins'),
                    onTap: targetActions.blocked
                        ? null
                        : () => _showTargetConvertDialog(context, theme, isDark),
                    theme: theme,
                    isDark: isDark,
                  ),
                _buildDivider(isDark),
                // وقت البث — days/hours on air, which feed the target.
                _buildSettingsTile(
                  icon: Icons.podcasts,
                  title: tr('وقت البث', 'Broadcast time'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BroadcastTimeScreen()),
                  ),
                  theme: theme,
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

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

          // SPEC52 #37 — Account: link a phone number to this account.
          _buildSectionTitle(tr('الحساب', 'Account'), theme, isDark),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildSettingsTile(
                icon: Icons.phone_iphone_outlined,
                title: tr('ربط رقم الهاتف', 'Link phone number'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LinkPhoneScreen()),
                ),
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
              if (hiddenMode != null) ...[
                _HiddenModeSwitch(initial: hiddenMode['on'] == true),
                _buildDivider(isDark),
              ],
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
                // Opened the "coming soon" toast and claimed version 1.0.0;
                // the About screen shows the installed version.
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
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
    // Nullable so a tile can be shown disabled (e.g. an admin-locked payout)
    // instead of being hidden, which users read as a missing feature.
    required VoidCallback? onTap,
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
          tr('تبديل الحساب', 'Switch account'),
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        content: Text(
          tr('سيتم تسجيل خروجك للدخول بحساب آخر. متابعة؟', 'You will be logged out to sign in with another account. Continue?'),
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
            child: Text(tr('تبديل', 'Switch')),
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
          tr('سيتم حذف حسابك نهائياً ولن تتمكن من الدخول به مرة أخرى. هل أنت متأكد؟', 'Your account will be permanently deleted and you will not be able to sign in again. Are you sure?'),
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
                    SnackBar(content: Text(tr('تعذّر حذف الحساب: $e', 'Unable to delete account: $e'))),
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

  /// بيع التارجت — the seller enters the buyer's ID and any amount up to their
  /// whole available target. The amount (and its dollar value) leaves the
  /// seller and lands on the buyer's target; the buyer's dollars only rise once
  /// the resulting total completes the tier set in the dashboard.
  void _showSellTargetDialog(BuildContext context, ThemeData theme, bool isDark) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _SellTargetDialog(theme: theme, isDark: isDark),
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
        _error = tr('تعذّر تحميل التارجت', 'Unable to load target');
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
      setState(() => _error = tr('أدخل مبلغًا صحيحًا لا يتجاوز $convertible كوينز', 'Enter a valid amount up to $convertible coins'));
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
          SnackBar(content: Text(tr('تم إضافة ${data['creditedCoins']} كوينز لرصيدك', '${data['creditedCoins']} coins added to your balance'))),
        );
      }
    } catch (e) {
      // Show what the server actually said (e.g. the max convertible amount)
      // instead of dumping the raw exception.
      final message = e is DioException && e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? tr('فشل التبديل', 'Exchange failed'))
          : tr('فشل التبديل', 'Exchange failed');
      setState(() {
        _submitting = false;
        _error = message;
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
    // Commission counted for the agent but not payable yet: the member who
    // generated it hasn't completed their target. Shown so a shrunken
    // "المتاح للتبديل" doesn't look like missing money.
    final lockedCommission =
        (_selected?['commissionLockedCoins'] as num?)?.toInt() ?? 0;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
      title: Text(tr('تبديل الكوينزات', 'Exchange coins'), style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      content: _loading
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : _items.isEmpty
              ? Text(
                  tr('لا يوجد تارجت متاح للتبديل حاليًا', 'No target balance available to exchange'),
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('المتاح للتبديل: $convertible كوينز (سيتحول نصفه، ${convertible ~/ 2} كحد أقصى، لرصيدك)', 'Available to exchange: $convertible coins (half, up to ${convertible ~/ 2}, will be added to your balance)'),
                      style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 13),
                    ),
                    if (lockedCommission > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        tr('عمولة محسوبة ومحجوزة: $lockedCommission كوينز — تُفتح عندما يكمل أصحابها التارجت المحدد', 'Calculated and reserved commission: $lockedCommission coins — unlocks when its owners reach their targets'),
                        style: const TextStyle(color: Color(0xFFFFB020), fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                      decoration: InputDecoration(
                        labelText: tr('المبلغ المراد تبديله', 'Amount to exchange'),
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
          child: Text(tr('إلغاء', 'Cancel')),
        ),
        if (_items.isNotEmpty)
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('تبديل', 'Switch')),
          ),
      ],
    );
  }
}

class _SellTargetDialog extends StatefulWidget {
  const _SellTargetDialog({required this.theme, required this.isDark});
  final ThemeData theme;
  final bool isDark;

  @override
  State<_SellTargetDialog> createState() => _SellTargetDialogState();
}

class _SellTargetDialogState extends State<_SellTargetDialog> {
  final _idCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final toUserId = int.tryParse(_idCtrl.text.trim());
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (toUserId == null || toUserId <= 0) {
      setState(() => _error = tr('أدخل معرّف (ID) صحيح', 'Enter a valid ID'));
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = tr('أدخل عدد كوينز صحيح', 'Enter a valid coin amount'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1A0E3E) : Colors.white,
        title: Text(tr('تأكيد البيع', 'Confirm sale'), style: TextStyle(color: widget.theme.textTheme.bodyLarge?.color)),
        content: Text(
          tr('سيتم نقل $amount كوينز من التارجت الخاص بك إلى المستخدم #$toUserId، '
          'وتُخصم قيمتها بالدولار من حسابك. متابعة؟', '$amount coins will be transferred from your target to user #$toUserId, and their dollar value will be deducted from your account. Continue?'),
          style: TextStyle(color: widget.theme.textTheme.bodyMedium?.color),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('لا', 'No'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('نعم', 'Yes'))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await DioClient.dio.post('/agencies/target/sell', data: {
        'toUserId': toUserId,
        'amount': amount,
      });
      final data = (res.data as Map)['data'] as Map;
      if (mounted) {
        Navigator.pop(context);
        final buyerName = (data['buyer'] as Map?)?['name']?.toString() ?? tr('المستفيد', 'Recipient');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('تم بيع $amount كوينز إلى $buyerName — تارجته الآن ${data['buyerTargetCoins']} كوينز', 'Sold $amount coins to $buyerName — their target is now ${data['buyerTargetCoins']} coins'),
            ),
          ),
        );
      }
    } catch (e) {
      final message = e is DioException
          ? (e.response?.data is Map ? (e.response!.data['message']?.toString() ?? tr('فشل البيع', 'Sale failed')) : tr('فشل البيع', 'Sale failed'))
          : tr('فشل البيع', 'Sale failed');
      setState(() {
        _submitting = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = widget.isDark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
      title: Text(tr('بيع التارجت', 'Sell target'), style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('بيع أي مقدار من تارجتك — حتى كامله — لمستخدم آخر بإدخال معرّفه (ID). '
            'يُخصم المبلغ وقيمته بالدولار من حسابك ويُضاف إلى تارجت المستفيد، '
            'وترتفع قيمته بالدولار عند إكماله التارجت المحدد.', 'Sell any amount of your target, including the full balance, to another user by entering their ID. The amount and its dollar value are deducted from your account and added to the recipient target. Its dollar value increases when they reach the required target.'),
            style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
            decoration: InputDecoration(
              labelText: tr('معرّف المستفيد (ID)', 'Recipient ID'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
            decoration: InputDecoration(
              labelText: tr('عدد الكوينز المراد بيعها', 'Number of coins to sell'),
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
          child: Text(tr('إلغاء', 'Cancel')),
        ),
        TextButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('بيع', 'Sell')),
        ),
      ],
    );
  }
}

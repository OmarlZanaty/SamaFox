import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_agencies_screen.dart';
import 'staff_audit_screen.dart';
import 'staff_grants_screen.dart';
import 'staff_members_screen.dart';
import 'staff_permissions_screen.dart';
import 'staff_widgets.dart';

/// نظام إدارة Manager / Super Admin / Admin. Every tile is shown only for a
/// permission the server says this account holds; the server still checks each
/// action on its own (spec 20–21).
class StaffPanelScreen extends ConsumerWidget {
  const StaffPanelScreen({super.key});

  static String titleFor(String? role) => switch (role) {
    'MANAGER' => tr('👑 نظام إدارة Manager', "👑 Manager panel"),
    'SUPER_ADMIN' => tr('💎 نظام إدارة Super Admin', "💎 Super admin panel"),
    'ADMIN' => tr('🛡️ نظام إدارة Admin', "🛡️ Admin panel"),
    _ => tr('نظام الإدارة', "Management panel"),
  };

  Widget _tile(BuildContext context, String title, String subtitle, IconData icon, Widget screen) => staffCard(title,
      subtitle: subtitle, leading: Icon(icon, color: staffGold), trailing: const Icon(Icons.chevron_left),
      onTap: () => openStaff(context, screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    return StaffScreen(title: titleFor(me?.role), allowed: (a) => a.rolePanel,
      child: me == null ? const SizedBox() : StaffRefreshList(onRefresh: () async => ref.refresh(staffMeProvider.future), children: [
        _header(me),
        if (me.manages) ...[
          staffHeading(tr('الإدارة', "Management")),
          _tile(context, tr('👥 الإداريون', "👥 Admins"), tr('كل من عيّنتهم: المدة والحالة والصلاحيات', "Everyone you appointed: duration, status and permissions"), Icons.groups, const StaffMembersScreen()),
          if (me.manager) _tile(context, tr('💎 تعيين Super Admin', "💎 Appoint super admin"), tr('المدة الأساسية شهر — قابلة للتجديد والتمديد', "Default duration: one month — renewable and extendable"), Icons.person_add, const StaffAppointScreen(role: 'SUPER_ADMIN')),
          _tile(context, tr('🛡️ تعيين Admin', "🛡️ Appoint admin"), tr('المدة الأساسية شهر — قابلة للتجديد والتمديد', "Default duration: one month — renewable and extendable"), Icons.person_add_alt, const StaffAppointScreen(role: 'ADMIN')),
          _tile(context, tr('🔐 صلاحيات الإدارة', "🔐 Admin permissions"), tr('تشغيل وإيقاف كل صلاحية لكل إداري', "Enable or disable each permission for each admin"), Icons.admin_panel_settings, const StaffPermissionsHubScreen()),
        ],
        if (me.has('grant_vip') || me.has('grant_level') || me.has('grant_frame') || me.has('grant_entry') || me.has('grant_bubble')) ...[
          staffHeading(tr('المنح المؤقتة — ٧ أيام', "Temporary grants — 7 days")),
          if (me.has('grant_vip')) _tile(context, tr('💎 منح VIP', "💎 Grant VIP"), 'VIP 1 → VIP ${me.vipCap}', Icons.workspace_premium, const StaffGrantScreen(kind: 'vip')),
          if (me.has('grant_level')) _tile(context, tr('⭐ منح Level', "⭐ Grant level"), 'Level 1 → Level ${me.levelCap}', Icons.trending_up, const StaffGrantScreen(kind: 'level')),
          if (me.has('grant_frame') || me.has('grant_entry') || me.has('grant_bubble'))
            _tile(context, tr('🎁 منح المنتجات', "🎁 Grant products"), tr('إطار / دخولية / فقاعة دردشة من القائمة المسموحة', "Frame / entrance / chat bubble from the allowed list"), Icons.card_giftcard, const StaffGrantScreen(kind: 'item')),
          _tile(context, tr('📋 المنح السابقة', "📋 Previous grants"), tr('المنح السارية والمنتهية', "Active and expired grants"), Icons.history, const StaffGrantsListScreen()),
        ],
        if (me.has('manage_host_agency') || me.has('follow_agencies')) ...[
          staffHeading(tr('وكالات المضيفين', "Hosting agencies")),
          _tile(context, tr('🏢 وكالات المضيفين', "🏢 Hosting agencies"), me.has('manage_host_agency') ? tr('إنشاء وتفعيل ومتابعة الوكالات والمضيفين', "Create, activate and monitor agencies and hosts") : tr('متابعة الوكالات والمضيفين', "Monitor agencies and hosts"),
              Icons.business, const StaffAgenciesScreen()),
        ],
        staffHeading(tr('السجل', "Log")),
        _tile(context, tr('📜 سجل العمليات', "📜 Activity log"), tr('كل ما نفذته${me.manages ? ' أنت وفريقك' : ''}', "All actions by ${me.manages ? 'you and your team' : 'you'}"), Icons.receipt_long, const StaffAuditScreen()),
      ]));
  }

  Widget _header(StaffAccess me) {
    final left = me.expiresAt?.difference(DateTime.now());
    final days = left == null ? null : (left.inHours / 24).ceil();
    return staffCard(staffRoles[me.role] ?? '',
      leading: const Icon(Icons.verified_user, color: staffGold),
      subtitle: tr('بداية الإدارة: ${dateLabel(me.startedAt)}\n'
          'نهاية الإدارة: ${dateLabel(me.expiresAt)}${days == null ? '' : ' (متبقٍ $days يوم)'}\n'
          'عيّنك: ${me.assignedBy?.label ?? 'إدارة المنصة'}', "Management started: ${dateLabel(me.startedAt)}\nManagement ends: ${dateLabel(me.expiresAt)}${days == null ? '' : ' ($days days left)'}\nAppointed by: ${me.assignedBy?.label ?? 'Platform management'}"));
  }
}

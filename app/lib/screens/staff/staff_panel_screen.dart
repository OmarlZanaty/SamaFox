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
    'MANAGER' => '👑 نظام إدارة Manager',
    'SUPER_ADMIN' => '💎 نظام إدارة Super Admin',
    'ADMIN' => '🛡️ نظام إدارة Admin',
    _ => 'نظام الإدارة',
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
          staffHeading('الإدارة'),
          _tile(context, '👥 الإداريون', 'كل من عيّنتهم: المدة والحالة والصلاحيات', Icons.groups, const StaffMembersScreen()),
          if (me.manager) _tile(context, '💎 تعيين Super Admin', 'المدة الأساسية شهر — قابلة للتجديد والتمديد', Icons.person_add, const StaffAppointScreen(role: 'SUPER_ADMIN')),
          _tile(context, '🛡️ تعيين Admin', 'المدة الأساسية شهر — قابلة للتجديد والتمديد', Icons.person_add_alt, const StaffAppointScreen(role: 'ADMIN')),
          _tile(context, '🔐 صلاحيات الإدارة', 'تشغيل وإيقاف كل صلاحية لكل إداري', Icons.admin_panel_settings, const StaffPermissionsHubScreen()),
        ],
        if (me.has('grant_vip') || me.has('grant_level') || me.has('grant_frame') || me.has('grant_entry') || me.has('grant_bubble')) ...[
          staffHeading('المنح المؤقتة — ٧ أيام'),
          if (me.has('grant_vip')) _tile(context, '💎 منح VIP', 'VIP 1 → VIP 5', Icons.workspace_premium, const StaffGrantScreen(kind: 'vip')),
          if (me.has('grant_level')) _tile(context, '⭐ منح Level', 'Level 1 → Level 20', Icons.trending_up, const StaffGrantScreen(kind: 'level')),
          if (me.has('grant_frame') || me.has('grant_entry') || me.has('grant_bubble'))
            _tile(context, '🎁 منح المنتجات', 'إطار / دخولية / فقاعة دردشة من القائمة المسموحة', Icons.card_giftcard, const StaffGrantScreen(kind: 'item')),
          _tile(context, '📋 المنح السابقة', 'المنح السارية والمنتهية', Icons.history, const StaffGrantsListScreen()),
        ],
        if (me.has('manage_host_agency') || me.has('follow_agencies')) ...[
          staffHeading('وكالات المضيفين'),
          _tile(context, '🏢 وكالات المضيفين', me.has('manage_host_agency') ? 'إنشاء وتفعيل ومتابعة الوكالات والمضيفين' : 'متابعة الوكالات والمضيفين',
              Icons.business, const StaffAgenciesScreen()),
        ],
        staffHeading('السجل'),
        _tile(context, '📜 سجل العمليات', 'كل ما نفذته${me.manages ? ' أنت وفريقك' : ''}', Icons.receipt_long, const StaffAuditScreen()),
      ]));
  }

  Widget _header(StaffAccess me) {
    final left = me.expiresAt?.difference(DateTime.now());
    final days = left == null ? null : (left.inHours / 24).ceil();
    return staffCard(staffRoles[me.role] ?? '',
      leading: const Icon(Icons.verified_user, color: staffGold),
      subtitle: 'بداية الإدارة: ${dateLabel(me.startedAt)}\n'
          'نهاية الإدارة: ${dateLabel(me.expiresAt)}${days == null ? '' : ' (متبقٍ $days يوم)'}\n'
          'عيّنك: ${me.assignedBy?.label ?? 'إدارة المنصة'}');
  }
}

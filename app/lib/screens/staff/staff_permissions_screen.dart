import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';
import '../../l10n/tr.dart';

/// What a permission/product editor needs: the permission catalog and the
/// products the editor may hand on. A Manager picks from the dashboard pool;
/// a Super Admin only from his own list (the server enforces the same).
class StaffEditorData {
  StaffEditorData(this.catalog, this.items);
  final List<StaffPermissionDefinition> catalog;
  final List<StaffItem> items;
}

Future<StaffEditorData> loadStaffEditor(StaffService service, StaffAccess me, {bool rewards = false}) async {
  final catalog = await service.catalog();
  final items = me.manager ? await service.pool(rewards: rewards) : await service.grantable();
  return StaffEditorData(catalog, items);
}

/// Keys this editor may switch for [role]: only what the role can hold, never
/// نظام الحظر unless the editor is a Manager, and below Manager only keys the
/// editor holds himself.
List<StaffPermissionDefinition> editableDefinitions(List<StaffPermissionDefinition> catalog, StaffAccess me, String role) =>
    catalog.where((d) => d.roles.contains(role) && (d.key != 'ban_users' || me.manager) && (me.manager || me.has(d.key))).toList();

String permissionLabel(StaffPermissionDefinition d, String role) =>
    d.label.replaceAll('{role}', staffRoles[role] ?? role);

List<Widget> permissionChecklist(List<StaffPermissionDefinition> catalog, StaffAccess me, String role,
    Map<String, bool> values, void Function(String key, bool value) onChanged) =>
    editableDefinitions(catalog, me, role).map((d) => CheckboxListTile(
      value: values[d.key] ?? false,
      title: Text(permissionLabel(d, role)),
      onChanged: (v) => onChanged(d.key, v ?? false),
    )).toList();

/// 🔐 صلاحيات الإدارة — the checklist for one staff member (spec 7).
class StaffPermissionEditorScreen extends ConsumerStatefulWidget {
  const StaffPermissionEditorScreen({super.key, required this.roleId});
  final int roleId;
  @override
  ConsumerState<StaffPermissionEditorScreen> createState() => _StaffPermissionEditorScreenState();
}

class _StaffPermissionEditorScreenState extends StaffActionState<StaffPermissionEditorScreen> {
  Map<String, bool>? values;
  Map<String, bool> original = {};
  int banDays = 0;
  int originalBanDays = 0;

  Future<(StaffFile, StaffEditorData)> load() async {
    final file = await service.member(widget.roleId);
    final data = await loadStaffEditor(service, access!);
    return (file, data);
  }

  void seed(StaffFile file) {
    if (values != null) return;
    final active = file.permissions.where((p) => p.active).toList();
    original = {for (final p in active) p.key: true};
    values = {...original};
    final ban = active.where((p) => p.key == 'ban_users').firstOrNull;
    if (ban?.expiresAt != null) {
      final left = ban!.expiresAt!.difference(DateTime.now()).inDays + 1;
      originalBanDays = [1, 7, 30, 365].firstWhere((d) => d >= left, orElse: () => 365);
    }
    banDays = originalBanDays;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    return StaffScreen(title: tr('🔐 صلاحيات الإدارة', '🔐 Management permissions'), allowed: (a) => a.manages,
      child: StaffLoad<(StaffFile, StaffEditorData)>(revision: revision, load: load, builder: (result) {
        final (file, data) = result;
        seed(file);
        final role = file.role.role;
        final editable = editableDefinitions(data.catalog, me!, role);
        return [
          staffUserCard(file.user),
          staffCard(tr('نوع الإدارة: ${staffRoles[role] ?? role}', 'Role type: ${staffRoles[role] ?? role}'),
              subtitle: tr('${statusLabel(file.role.effectiveStatus)} — نهاية: ${dateLabel(file.role.expiresAt)}', '${statusLabel(file.role.effectiveStatus)} — expires: ${dateLabel(file.role.expiresAt)}')),
          if (!file.role.active) Text(tr('الإدارة غير نشطة؛ جدّدها أولاً لتعديل الصلاحيات', 'This role is inactive; renew it before editing permissions')),
          if (file.role.active) ...[
            ...permissionChecklist(data.catalog, me, role, values!, (k, v) => setState(() => values![k] = v)),
            if (me.manager && values!['ban_users'] == true)
              permissionDuration(banDays, (v) => setState(() => banDays = v)),
            FilledButton(onPressed: busy ? null : () async {
              final changed = <String, bool>{
                for (final d in editable)
                  if ((values![d.key] ?? false) != (original[d.key] ?? false)) d.key: values![d.key] ?? false,
              };
              // A new term for نظام الحظر is a change even when the box stays ticked.
              if (values!['ban_users'] == true && banDays != originalBanDays) changed['ban_users'] = true;
              if (changed.isEmpty) { staffSnack(context, tr('لا توجد تغييرات', 'No changes')); return; }
              final ok = await act(() async {
                await service.setPermissions(widget.roleId, changed,
                    terms: {if (changed['ban_users'] == true) 'ban_users': banDays == 0 ? null : banDays});
              }, message: tr('تم حفظ الصلاحيات', 'Permissions saved'));
              if (ok) setState(() => values = null);
            }, child: Text(busy ? tr('جارٍ الحفظ…', 'Saving…') : tr('حفظ الصلاحيات', 'Save permissions'))),
          ],
        ];
      }));
  }
}

/// المنتجات المسموحة (what he may grant) or مكافآت الإداري (perks he gets).
class StaffItemsEditorScreen extends ConsumerStatefulWidget {
  const StaffItemsEditorScreen({super.key, required this.roleId, this.rewards = false});
  final int roleId;
  final bool rewards;
  @override
  ConsumerState<StaffItemsEditorScreen> createState() => _StaffItemsEditorScreenState();
}

class _StaffItemsEditorScreenState extends StaffActionState<StaffItemsEditorScreen> {
  Set<String>? selected;

  Future<(StaffFile, StaffEditorData)> load() async {
    final file = await service.member(widget.roleId);
    final data = await loadStaffEditor(service, access!, rewards: widget.rewards);
    return (file, data);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.rewards ? tr('مكافآت الإداري', 'Staff rewards') : tr('المنتجات المسموحة', 'Allowed products');
    return StaffScreen(title: title, allowed: (a) => a.manages,
      child: StaffLoad<(StaffFile, StaffEditorData)>(revision: revision, load: load, builder: (result) {
        final (file, data) = result;
        selected ??= (widget.rewards ? file.role.rewardItemIds : file.role.allowedItemIds).toSet();
        return [
          staffUserCard(file.user),
          Text(widget.rewards
              ? tr('منتجات يحصل عليها الإداري نفسه طوال مدة إدارته، وتُسحب تلقائياً عند انتهائها.', 'Products the staff member receives during their role, automatically removed when it expires.')
              : tr('المنتجات التي يستطيع هذا الإداري منحها للمستخدمين (٧ أيام). لا يستطيع تعديل أي منتج.', 'Products this staff member can grant to users (7 days). They cannot edit any product.')),
          StaffItemPicker(items: data.items, selected: selected!, title: title,
              onChanged: (v) => setState(() => selected = v)),
          FilledButton(onPressed: busy || !file.role.active ? null : () async {
            final ok = await act(() => widget.rewards
                ? service.setRewardItems(widget.roleId, selected!.toList())
                : service.setAllowedItems(widget.roleId, selected!.toList()), message: tr('تم الحفظ', 'Saved'));
            if (ok) setState(() => selected = null);
          }, child: Text(busy ? tr('جارٍ الحفظ…', 'Saving…') : tr('حفظ', 'Save'))),
        ];
      }));
  }
}

/// 🔐 صلاحيات الإدارة — entry point: pick a staff member by ID (spec 7), plus
/// the Manager-only parts: who holds نظام الحظر and the role rewards.
class StaffPermissionsHubScreen extends ConsumerStatefulWidget {
  const StaffPermissionsHubScreen({super.key});
  @override
  ConsumerState<StaffPermissionsHubScreen> createState() => _StaffPermissionsHubScreenState();
}

class _StaffPermissionsHubScreenState extends StaffActionState<StaffPermissionsHubScreen> {
  StaffUser? user;
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    final found = user?.staffRole;
    // Your own role is not editable here; the server answers 403 for it.
    final self = found != null && found.id == me?.roleId;
    final role = self ? null : found;
    return StaffScreen(title: tr('🔐 صلاحيات الإدارة', '🔐 Management permissions'), allowed: (a) => a.manages,
      child: StaffRefreshList(onRefresh: () async => ref.refresh(staffMeProvider.future), children: [
        Text(tr('أدخل ID الإداري لعرض نوع إدارته وصلاحياته:', 'Enter the staff ID to view their role and permissions:')),
        StaffUserLookup(onSelected: (v) => setState(() => user = v)),
        if (self) Text(tr('لا يمكنك تعديل صلاحياتك بنفسك.', 'You cannot edit your own permissions.')),
        if (user != null && found == null)
          Text(tr('هذا المستخدم ليس لديه إدارة نشطة.', 'This user has no active role.')),
        if (role != null) ...[
          staffCard(tr('نوع الإدارة: ${staffRoles[role.role] ?? role.role}', 'Role type: ${staffRoles[role.role] ?? role.role}'),
              subtitle: tr('نهاية: ${dateLabel(role.expiresAt)}', 'Expires: ${dateLabel(role.expiresAt)}')),
          FilledButton(onPressed: () => openStaff(context, StaffPermissionEditorScreen(roleId: role.id)),
              child: Text(tr('عرض وتعديل الصلاحيات', 'View and edit permissions'))),
          OutlinedButton(onPressed: () => openStaff(context, StaffItemsEditorScreen(roleId: role.id)),
              child: Text(tr('المنتجات المسموحة', 'Allowed products'))),
          if (me?.manager == true)
            OutlinedButton(onPressed: () => openStaff(context, StaffItemsEditorScreen(roleId: role.id, rewards: true)),
                child: Text(tr('مكافآت الإداري', 'Staff rewards'))),
        ],
        if (me?.manager == true) ...[
          const Divider(),
          staffCard(tr('🚫 نظام الحظر — من يملك الصلاحية', '🚫 Ban system — permission holders'), subtitle: tr('منح وسحب صلاحية الحظر ومدتها', 'Grant or revoke ban permission and set its duration'),
              trailing: const Icon(Icons.chevron_left), onTap: () => openStaff(context, const StaffBanHoldersScreen())),
          staffCard(tr('🎁 مكافآت الإدارة', '🎁 Management rewards'), subtitle: tr('إطار وشارة ومنتجات Admin / Super Admin / Manager', 'Frames, badges, and products for Admin / Super Admin / Manager'),
              trailing: const Icon(Icons.chevron_left), onTap: () => openStaff(context, const StaffRoleRewardsScreen())),
        ],
      ]));
  }
}

/// Manager: who holds نظام الحظر, grant it (with a term) and withdraw it.
class StaffBanHoldersScreen extends ConsumerStatefulWidget {
  const StaffBanHoldersScreen({super.key});
  @override
  ConsumerState<StaffBanHoldersScreen> createState() => _StaffBanHoldersScreenState();
}

class _StaffBanHoldersScreenState extends StaffActionState<StaffBanHoldersScreen> {
  StaffUser? user;
  int days = 0;
  @override
  Widget build(BuildContext context) => StaffScreen(title: tr('🚫 صلاحية نظام الحظر', '🚫 Ban system permission'), allowed: (a) => a.manager,
    child: StaffLoad<List<StaffPermission>>(revision: revision, load: service.banHolders, header: [
      staffHeading(tr('منح صلاحية الحظر', 'Grant ban permission')),
      StaffUserLookup(onSelected: (v) => setState(() => user = v)),
      permissionDuration(days, (v) => setState(() => days = v), standalone: user?.staffRole == null),
      FilledButton(onPressed: busy || user == null ? null : () async {
        final target = user!;
        if (!await staffConfirm(context, tr('منح صلاحية الحظر', 'Grant ban permission'), tr('${target.label}\nالمدة: ${days == 0 ? (target.staffRole == null ? 'أبدي' : 'حتى نهاية الإدارة') : '$days يوم'}', '${target.label}\nDuration: ${days == 0 ? (target.staffRole == null ? 'Permanent' : 'Until role expires') : '$days days'}')) || !mounted) return;
        await act(() => service.grantBanPermission(target.id, days == 0 ? null : days), message: tr('🚫 نظام الحظر: مفعل', '🚫 Ban system: enabled'));
      }, child: Text(tr('منح الصلاحية', 'Grant permission'))),
      const Divider(),
      staffHeading(tr('من يملك صلاحية الحظر', 'Ban permission holders')),
      Text(tr('كل Manager يملكها تلقائياً.', 'Every manager has this permission automatically.')),
    ], builder: (rows) => rows.map((p) => staffCard(p.user?.label ?? 'ID ${p.userId}',
      leading: p.user == null ? null : staffAvatar(p.user!),
      subtitle: tr('نهاية الصلاحية: ${dateLabel(p.expiresAt)}', 'Permission expires: ${dateLabel(p.expiresAt)}'),
      trailing: TextButton(onPressed: busy ? null : () async {
        if (!await staffConfirm(context, tr('سحب صلاحية الحظر', 'Revoke ban permission'), p.user?.label ?? 'ID ${p.userId}') || !mounted) return;
        await act(() => service.revokeBanPermission(p.userId), message: tr('🚫 نظام الحظر: مسحوب', '🚫 Ban system: revoked'));
      }, child: Text(tr('سحب', 'Revoke'))))).toList()));
}

/// Manager: the products every Admin / Super Admin / Manager gets with the role.
class StaffRoleRewardsScreen extends ConsumerStatefulWidget {
  const StaffRoleRewardsScreen({super.key});
  @override
  ConsumerState<StaffRoleRewardsScreen> createState() => _StaffRoleRewardsScreenState();
}

class _StaffRoleRewardsScreenState extends StaffActionState<StaffRoleRewardsScreen> {
  Map<String, Set<String>>? selected;
  Future<(Map<String, List<String>>, List<StaffItem>)> load() async =>
      (await service.roleRewards(), await service.pool(rewards: true));
  @override
  Widget build(BuildContext context) => StaffScreen(title: tr('🎁 مكافآت الإدارة', '🎁 Management rewards'), allowed: (a) => a.manager,
    child: StaffLoad<(Map<String, List<String>>, List<StaffItem>)>(revision: revision, load: load, builder: (result) {
      final (config, items) = result;
      selected ??= {for (final r in staffRoles.keys) r: (config[r] ?? const []).toSet()};
      return [
        Text(tr('إطار الإداري وشارته والمنتجات الإضافية — تُمنح مع الإدارة وتُسحب عند انتهائها.', 'Staff frames, badges, and extra products — granted with the role and removed when it expires.')),
        ...staffRoles.entries.map((r) => ExpansionTile(title: Text(r.value), children: [
          StaffItemPicker(items: items, selected: selected![r.key]!, title: tr('منتجات ${r.value}', '${r.value} products'),
              onChanged: (v) => setState(() => selected![r.key] = v)),
          FilledButton(onPressed: busy ? null : () => act(() => service.setRoleRewards(r.key, selected![r.key]!.toList()),
              message: tr('تم حفظ مكافآت ${r.value}', 'Rewards saved for ${r.value}')), child: Text(tr('حفظ', 'Save'))),
        ])),
      ];
    }));
}

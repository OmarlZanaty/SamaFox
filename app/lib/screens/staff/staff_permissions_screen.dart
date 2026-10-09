import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';

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
    return StaffScreen(title: '🔐 صلاحيات الإدارة', allowed: (a) => a.manages,
      child: StaffLoad<(StaffFile, StaffEditorData)>(revision: revision, load: load, builder: (result) {
        final (file, data) = result;
        seed(file);
        final role = file.role.role;
        final editable = editableDefinitions(data.catalog, me!, role);
        return [
          staffUserCard(file.user),
          staffCard('نوع الإدارة: ${staffRoles[role] ?? role}',
              subtitle: '${statusLabel(file.role.effectiveStatus)} — نهاية: ${dateLabel(file.role.expiresAt)}'),
          if (!file.role.active) const Text('الإدارة غير نشطة؛ جدّدها أولاً لتعديل الصلاحيات'),
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
              if (changed.isEmpty) { staffSnack(context, 'لا توجد تغييرات'); return; }
              final ok = await act(() async {
                await service.setPermissions(widget.roleId, changed,
                    terms: {if (changed['ban_users'] == true) 'ban_users': banDays == 0 ? null : banDays});
              }, message: 'تم حفظ الصلاحيات');
              if (ok) setState(() => values = null);
            }, child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ الصلاحيات')),
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
    final title = widget.rewards ? 'مكافآت الإداري' : 'المنتجات المسموحة';
    return StaffScreen(title: title, allowed: (a) => a.manages,
      child: StaffLoad<(StaffFile, StaffEditorData)>(revision: revision, load: load, builder: (result) {
        final (file, data) = result;
        selected ??= (widget.rewards ? file.role.rewardItemIds : file.role.allowedItemIds).toSet();
        return [
          staffUserCard(file.user),
          Text(widget.rewards
              ? 'منتجات يحصل عليها الإداري نفسه طوال مدة إدارته، وتُسحب تلقائياً عند انتهائها.'
              : 'المنتجات التي يستطيع هذا الإداري منحها للمستخدمين (٧ أيام). لا يستطيع تعديل أي منتج.'),
          StaffItemPicker(items: data.items, selected: selected!, title: title,
              onChanged: (v) => setState(() => selected = v)),
          FilledButton(onPressed: busy || !file.role.active ? null : () async {
            final ok = await act(() => widget.rewards
                ? service.setRewardItems(widget.roleId, selected!.toList())
                : service.setAllowedItems(widget.roleId, selected!.toList()), message: 'تم الحفظ');
            if (ok) setState(() => selected = null);
          }, child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ')),
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
    final role = user?.staffRole;
    return StaffScreen(title: '🔐 صلاحيات الإدارة', allowed: (a) => a.manages,
      child: StaffRefreshList(onRefresh: () async => ref.refresh(staffMeProvider.future), children: [
        const Text('أدخل ID الإداري لعرض نوع إدارته وصلاحياته:'),
        StaffUserLookup(onSelected: (v) => setState(() => user = v)),
        if (user != null && role == null)
          const Text('هذا المستخدم ليس لديه إدارة نشطة.'),
        if (role != null) ...[
          staffCard('نوع الإدارة: ${staffRoles[role.role] ?? role.role}',
              subtitle: 'نهاية: ${dateLabel(role.expiresAt)}'),
          FilledButton(onPressed: () => openStaff(context, StaffPermissionEditorScreen(roleId: role.id)),
              child: const Text('عرض وتعديل الصلاحيات')),
          OutlinedButton(onPressed: () => openStaff(context, StaffItemsEditorScreen(roleId: role.id)),
              child: const Text('المنتجات المسموحة')),
          if (me?.manager == true)
            OutlinedButton(onPressed: () => openStaff(context, StaffItemsEditorScreen(roleId: role.id, rewards: true)),
                child: const Text('مكافآت الإداري')),
        ],
        if (me?.manager == true) ...[
          const Divider(),
          staffCard('🚫 نظام الحظر — من يملك الصلاحية', subtitle: 'منح وسحب صلاحية الحظر ومدتها',
              trailing: const Icon(Icons.chevron_left), onTap: () => openStaff(context, const StaffBanHoldersScreen())),
          staffCard('🎁 مكافآت الإدارة', subtitle: 'إطار وشارة ومنتجات Admin / Super Admin / Manager',
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
  Widget build(BuildContext context) => StaffScreen(title: '🚫 صلاحية نظام الحظر', allowed: (a) => a.manager,
    child: StaffLoad<List<StaffPermission>>(revision: revision, load: service.banHolders, header: [
      staffHeading('منح صلاحية الحظر'),
      StaffUserLookup(onSelected: (v) => setState(() => user = v)),
      permissionDuration(days, (v) => setState(() => days = v), standalone: user?.staffRole == null),
      FilledButton(onPressed: busy || user == null ? null : () async {
        final target = user!;
        if (!await staffConfirm(context, 'منح صلاحية الحظر', '${target.label}\nالمدة: ${days == 0 ? (target.staffRole == null ? 'أبدي' : 'حتى نهاية الإدارة') : '$days يوم'}') || !mounted) return;
        await act(() => service.grantBanPermission(target.id, days == 0 ? null : days), message: '🚫 نظام الحظر: مفعل');
      }, child: const Text('منح الصلاحية')),
      const Divider(),
      staffHeading('من يملك صلاحية الحظر'),
      const Text('كل Manager يملكها تلقائياً.'),
    ], builder: (rows) => rows.map((p) => staffCard(p.user?.label ?? 'ID ${p.userId}',
      leading: p.user == null ? null : staffAvatar(p.user!),
      subtitle: 'نهاية الصلاحية: ${dateLabel(p.expiresAt)}',
      trailing: TextButton(onPressed: busy ? null : () async {
        if (!await staffConfirm(context, 'سحب صلاحية الحظر', p.user?.label ?? 'ID ${p.userId}') || !mounted) return;
        await act(() => service.revokeBanPermission(p.userId), message: '🚫 نظام الحظر: مسحوب');
      }, child: const Text('سحب')))).toList()));
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
  Widget build(BuildContext context) => StaffScreen(title: '🎁 مكافآت الإدارة', allowed: (a) => a.manager,
    child: StaffLoad<(Map<String, List<String>>, List<StaffItem>)>(revision: revision, load: load, builder: (result) {
      final (config, items) = result;
      selected ??= {for (final r in staffRoles.keys) r: (config[r] ?? const []).toSet()};
      return [
        const Text('إطار الإداري وشارته والمنتجات الإضافية — تُمنح مع الإدارة وتُسحب عند انتهائها.'),
        ...staffRoles.entries.map((r) => ExpansionTile(title: Text(r.value), children: [
          StaffItemPicker(items: items, selected: selected![r.key]!, title: 'منتجات ${r.value}',
              onChanged: (v) => setState(() => selected![r.key] = v)),
          FilledButton(onPressed: busy ? null : () => act(() => service.setRoleRewards(r.key, selected![r.key]!.toList()),
              message: 'تم حفظ مكافآت ${r.value}'), child: const Text('حفظ')),
        ])),
      ];
    }));
}

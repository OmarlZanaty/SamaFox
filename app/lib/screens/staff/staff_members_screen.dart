import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';
import 'staff_permissions_screen.dart';
import 'staff_audit_screen.dart';
import 'staff_agencies_screen.dart';
import '../../l10n/tr.dart';

class StaffMembersScreen extends ConsumerStatefulWidget {
  const StaffMembersScreen({super.key});
  @override
  ConsumerState<StaffMembersScreen> createState() => _StaffMembersScreenState();
}
class _StaffMembersScreenState extends StaffActionState<StaffMembersScreen> {
  String status = '', role = '';
  @override
  Widget build(BuildContext context) => StaffScreen(title: tr('👥 الإداريون', '👥 Staff'), allowed: (a) => a.manages,
    child: StaffLoad<List<StaffRole>>(revision: revision,
      load: () => service.members(status: status.isEmpty ? null : status, role: role.isEmpty ? null : role),
      header: [staffSelect(tr('الحالة', 'Status'), status, staffStatuses, (v) { setState(() => status = v); reload(); }),
        staffSelect(tr('النوع', 'Type'), role, {'': tr('كل الأنواع', 'All types'), 'SUPER_ADMIN': tr('مشرف عام', 'Super Admin'), 'ADMIN': tr('مشرف', 'Admin')}, (v) { setState(() => role = v); reload(); })],
      builder: (rows) => rows.map((r) => staffCard(r.user?.label ?? 'ID ${r.userId}',
        leading: r.user == null ? null : staffAvatar(r.user!),
        subtitle: tr('${staffRoles[r.role]} | ${statusLabel(r.effectiveStatus)}\nبداية: ${dateLabel(r.startedAt)}\nنهاية: ${dateLabel(r.expiresAt)}', '${staffRoles[r.role]} | ${statusLabel(r.effectiveStatus)}\nStarts: ${dateLabel(r.startedAt)}\nExpires: ${dateLabel(r.expiresAt)}'),
        trailing: const Icon(Icons.chevron_left), onTap: () async {
          await openStaff(context, StaffMemberScreen(roleId: r.id)); reload();
        })).toList()));
}

class StaffMemberScreen extends ConsumerStatefulWidget {
  const StaffMemberScreen({super.key, required this.roleId});
  final int roleId;
  @override
  ConsumerState<StaffMemberScreen> createState() => _StaffMemberScreenState();
}
class _StaffMemberScreenState extends StaffActionState<StaffMemberScreen> {
  late int roleId = widget.roleId;
  Future<void> term(StaffRole role) async {
    final value = await staffPrompt(context, role.active ? tr('تمديد الإدارة', 'Extend role') : tr('تجديد الإدارة', 'Renew role'), initial: '30', maxDays: access?.maxDays ?? 30);
    if (value == null || !mounted) return;
    await act(() async {
      final result = role.active ? await service.extend(role.id, int.parse(value)) : await service.renew(role.id, int.parse(value));
      roleId = result.id;
    });
  }
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    return StaffScreen(title: tr('ملف الإداري', 'Staff profile'), allowed: (a) => a.manages,
      child: StaffLoad<StaffFile>(revision: revision, load: () => service.member(roleId), builder: (file) => [
        staffUserCard(file.user),
        staffCard(staffRoles[file.role.role] ?? file.role.role,
          subtitle: tr('${statusLabel(file.role.effectiveStatus)}\nبداية: ${dateLabel(file.role.startedAt)}\nنهاية: ${dateLabel(file.role.expiresAt)}', '${statusLabel(file.role.effectiveStatus)}\nStarts: ${dateLabel(file.role.startedAt)}\nExpires: ${dateLabel(file.role.expiresAt)}')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: busy ? null : () => term(file.role), child: Text(file.role.active ? tr('تمديد الإدارة', 'Extend role') : tr('تجديد', 'Renew'))),
          if (file.role.active) OutlinedButton(onPressed: busy ? null : () async {
            final reason = await staffPrompt(context, tr('سحب الإدارة — أدخل السبب', 'Revoke role — enter reason'));
            if (reason == null || !context.mounted) return;
            if (await staffConfirm(context, tr('تأكيد سحب الإدارة', 'Confirm role revocation'), tr('سحب إدارة ${file.user.label}\nالسبب: $reason', 'Revoke role of ${file.user.label}\nReason: $reason')) && mounted) {
              await act(() => service.revoke(roleId, reason));
            }
          }, child: Text(tr('سحب الإدارة', 'Revoke role'))),
          if (file.role.active) OutlinedButton(onPressed: () async {
            await openStaff(context, StaffPermissionEditorScreen(roleId: roleId)); reload();
          }, child: Text(tr('تعديل الصلاحيات', 'Edit permissions'))),
        ]),
        staffHeading(tr('الصلاحيات', 'Permissions')),
        ...file.permissions.where((p) => p.active).map((p) => staffCard(permissionLabels[p.key] ?? p.key,
          subtitle: tr('نهاية الصلاحية: ${dateLabel(p.expiresAt ?? file.role.expiresAt)}', 'Permission expires: ${dateLabel(p.expiresAt ?? file.role.expiresAt)}'))),
        if (!file.permissions.any((p) => p.active)) Text(tr('لا توجد صلاحيات نشطة', 'No active permissions')),
        staffHeading(tr('المنتجات المسموحة', 'Allowed products')),
        Text(file.role.allowedItemIds.isEmpty ? tr('لا توجد منتجات', 'No products') : file.role.allowedItemIds.join(tr('، ', ', '))),
        if (file.role.active) OutlinedButton(onPressed: () async {
          await openStaff(context, StaffItemsEditorScreen(roleId: roleId)); reload();
        }, child: Text(tr('تعديل المنتجات المسموحة', 'Edit allowed products'))),
        staffHeading(tr('مكافآت الإدارة الإضافية', 'Extra management rewards')),
        Text(file.role.rewardItemIds.isEmpty ? tr('لا توجد منتجات إضافية', 'No extra products') : file.role.rewardItemIds.join(tr('، ', ', '))),
        if (file.role.active) OutlinedButton(onPressed: () async {
          await openStaff(context, StaffItemsEditorScreen(roleId: roleId, rewards: true)); reload();
        }, child: Text(tr('تعديل مكافآت الإداري', 'Edit staff rewards'))),
        staffHeading(tr('الوكالات', 'Agencies')),
        if (file.agencies.isEmpty) Text(tr('لا توجد وكالات', 'No agencies')),
        ...file.agencies.map((agency) => agencyCard(context, agency, canOpen: me?.has('follow_agencies') == true)),
        staffHeading(tr('آخر 50 عملية', 'Last 50 actions')),
        if (file.audit.isEmpty) Text(tr('لا توجد عمليات', 'No actions')),
        ...file.audit.map(staffAuditCard),
        OutlinedButton(onPressed: () => openStaff(context, StaffAuditScreen(actorId: file.user.id)), child: Text(tr('كل العمليات', 'All actions'))),
      ]));
  }
}

class StaffAppointScreen extends ConsumerStatefulWidget {
  const StaffAppointScreen({super.key, required this.role});
  final String role;
  @override
  ConsumerState<StaffAppointScreen> createState() => _StaffAppointScreenState();
}
class _StaffAppointScreenState extends StaffActionState<StaffAppointScreen> {
  final form = GlobalKey<FormState>();
  final days = TextEditingController(text: '30');
  StaffUser? user;
  Map<String, bool>? permissions;
  Set<String> selected = {};
  int banDays = 0;
  @override
  void dispose() { days.dispose(); super.dispose(); }
  Future<StaffEditorData> load() => loadStaffEditor(service, access!);
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    return StaffScreen(title: tr('تعيين ${staffRoles[widget.role]}', 'Appoint ${staffRoles[widget.role]}'),
      allowed: (a) => a.manages && (widget.role == 'ADMIN' || a.manager),
      child: StaffLoad<StaffEditorData>(load: load, builder: (data) {
        final editable = editableDefinitions(data.catalog, me!, widget.role);
        permissions ??= {for (final p in editable) p.key: p.key != 'ban_users' &&
          (widget.role == 'SUPER_ADMIN' || ['role_panel', 'manage_host_agency', 'follow_agencies'].contains(p.key))};
        return [StaffUserLookup(onSelected: (v) => setState(() => user = v)),
          Form(key: form, child: TextFormField(controller: days, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('المدة بالأيام — شهر = 30 (1–${me.maxDays})', 'Duration in days — month = 30 (1–${me.maxDays})')), validator: (v) {
              final n = int.tryParse(v ?? ''); return n == null || n < 1 || n > me.maxDays ? tr('أدخل من 1 إلى ${me.maxDays} يوم', 'Enter 1 to ${me.maxDays} days') : null;
            })),
          staffHeading(tr('الصلاحيات الأولية', 'Initial permissions')),
          ...permissionChecklist(data.catalog, me, widget.role, permissions!, (key, value) => setState(() => permissions![key] = value)),
          if (permissions!['ban_users'] == true) permissionDuration(banDays, (v) => setState(() => banDays = v)),
          StaffItemPicker(items: data.items, selected: selected, onChanged: (v) => setState(() => selected = v)),
          FilledButton(onPressed: busy || user == null ? null : () async {
            // The days field is at the top of a lazy ListView: once the button is
            // scrolled into view the field may be disposed and the form state gone.
            form.currentState?.validate();
            final term = int.tryParse(days.text.trim());
            if (term == null || term < 1 || term > me.maxDays) { staffSnack(context, tr('المدة: أدخل من 1 إلى ${me.maxDays} يوم', 'Duration: enter 1 to ${me.maxDays} days')); return; }
            final target = user!;
            if (!await staffConfirm(context, tr('تأكيد التعيين', 'Confirm appointment'), tr('${target.label}\n${staffRoles[widget.role]} لمدة $term يوم', '${target.label}\n${staffRoles[widget.role]} for $term days')) || !mounted) return;
            final ok = await act(() async { await service.appoint(userId: target.id, role: widget.role, days: term,
              permissions: {for (final p in editable) p.key: permissions![p.key] ?? false},
              allowedItemIds: selected.toList(), banDays: banDays == 0 ? null : banDays); });
            if (ok && context.mounted) Navigator.pop(context);
          }, child: Text(busy ? tr('جارٍ التعيين…', 'Appointing…') : tr('تأكيد التعيين', 'Confirm appointment')))];
      }));
  }
}

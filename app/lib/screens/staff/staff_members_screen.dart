import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';
import 'staff_permissions_screen.dart';
import 'staff_audit_screen.dart';
import 'staff_agencies_screen.dart';

class StaffMembersScreen extends ConsumerStatefulWidget {
  const StaffMembersScreen({super.key});
  @override
  ConsumerState<StaffMembersScreen> createState() => _StaffMembersScreenState();
}
class _StaffMembersScreenState extends StaffActionState<StaffMembersScreen> {
  String status = '', role = '';
  @override
  Widget build(BuildContext context) => StaffScreen(title: '👥 الإداريون', allowed: (a) => a.manages,
    child: StaffLoad<List<StaffRole>>(revision: revision,
      load: () => service.members(status: status.isEmpty ? null : status, role: role.isEmpty ? null : role),
      header: [staffSelect('الحالة', status, staffStatuses, (v) { setState(() => status = v); reload(); }),
        staffSelect('النوع', role, {'': 'كل الأنواع', 'SUPER_ADMIN': 'Super Admin', 'ADMIN': 'Admin'}, (v) { setState(() => role = v); reload(); })],
      builder: (rows) => rows.map((r) => staffCard(r.user?.label ?? 'ID ${r.userId}',
        leading: r.user == null ? null : staffAvatar(r.user!),
        subtitle: '${staffRoles[r.role]} | ${statusLabel(r.effectiveStatus)}\nبداية: ${dateLabel(r.startedAt)}\nنهاية: ${dateLabel(r.expiresAt)}',
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
    final value = await staffPrompt(context, role.active ? 'تمديد الإدارة' : 'تجديد الإدارة', initial: '30', maxDays: access?.maxDays ?? 30);
    if (value == null || !mounted) return;
    await act(() async {
      final result = role.active ? await service.extend(role.id, int.parse(value)) : await service.renew(role.id, int.parse(value));
      roleId = result.id;
    });
  }
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    return StaffScreen(title: 'ملف الإداري', allowed: (a) => a.manages,
      child: StaffLoad<StaffFile>(revision: revision, load: () => service.member(roleId), builder: (file) => [
        staffUserCard(file.user),
        staffCard(staffRoles[file.role.role] ?? file.role.role,
          subtitle: '${statusLabel(file.role.effectiveStatus)}\nبداية: ${dateLabel(file.role.startedAt)}\nنهاية: ${dateLabel(file.role.expiresAt)}'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: busy ? null : () => term(file.role), child: Text(file.role.active ? 'تمديد الإدارة' : 'تجديد')),
          if (file.role.active) OutlinedButton(onPressed: busy ? null : () async {
            final reason = await staffPrompt(context, 'سحب الإدارة — أدخل السبب');
            if (reason == null || !context.mounted) return;
            if (await staffConfirm(context, 'تأكيد سحب الإدارة', 'سحب إدارة ${file.user.label}\nالسبب: $reason') && mounted) {
              await act(() => service.revoke(roleId, reason));
            }
          }, child: const Text('سحب الإدارة')),
          if (file.role.active) OutlinedButton(onPressed: () async {
            await openStaff(context, StaffPermissionEditorScreen(roleId: roleId)); reload();
          }, child: const Text('تعديل الصلاحيات')),
        ]),
        staffHeading('الصلاحيات'),
        ...file.permissions.where((p) => p.active).map((p) => staffCard(permissionLabels[p.key] ?? p.key,
          subtitle: 'نهاية الصلاحية: ${dateLabel(p.expiresAt ?? file.role.expiresAt)}')),
        if (!file.permissions.any((p) => p.active)) const Text('لا توجد صلاحيات نشطة'),
        staffHeading('المنتجات المسموحة'),
        Text(file.role.allowedItemIds.isEmpty ? 'لا توجد منتجات' : file.role.allowedItemIds.join('، ')),
        if (file.role.active) OutlinedButton(onPressed: () async {
          await openStaff(context, StaffItemsEditorScreen(roleId: roleId)); reload();
        }, child: const Text('تعديل المنتجات المسموحة')),
        staffHeading('مكافآت الإدارة الإضافية'),
        Text(file.role.rewardItemIds.isEmpty ? 'لا توجد منتجات إضافية' : file.role.rewardItemIds.join('، ')),
        if (file.role.active) OutlinedButton(onPressed: () async {
          await openStaff(context, StaffItemsEditorScreen(roleId: roleId, rewards: true)); reload();
        }, child: const Text('تعديل مكافآت الإداري')),
        staffHeading('الوكالات'),
        if (file.agencies.isEmpty) const Text('لا توجد وكالات'),
        ...file.agencies.map((agency) => agencyCard(context, agency, canOpen: me?.has('follow_agencies') == true)),
        staffHeading('آخر 50 عملية'),
        if (file.audit.isEmpty) const Text('لا توجد عمليات'),
        ...file.audit.map(staffAuditCard),
        OutlinedButton(onPressed: () => openStaff(context, StaffAuditScreen(actorId: file.user.id)), child: const Text('كل العمليات')),
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
    return StaffScreen(title: 'تعيين ${staffRoles[widget.role]}',
      allowed: (a) => a.manages && (widget.role == 'ADMIN' || a.manager),
      child: StaffLoad<StaffEditorData>(load: load, builder: (data) {
        final editable = editableDefinitions(data.catalog, me!, widget.role);
        permissions ??= {for (final p in editable) p.key: p.key != 'ban_users' &&
          (widget.role == 'SUPER_ADMIN' || ['role_panel', 'manage_host_agency', 'follow_agencies'].contains(p.key))};
        return [StaffUserLookup(onSelected: (v) => setState(() => user = v)),
          Form(key: form, child: TextFormField(controller: days, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'المدة بالأيام — شهر = 30 (1–${me.maxDays})'), validator: (v) {
              final n = int.tryParse(v ?? ''); return n == null || n < 1 || n > me.maxDays ? 'أدخل من 1 إلى ${me.maxDays} يوم' : null;
            })),
          staffHeading('الصلاحيات الأولية'),
          ...permissionChecklist(data.catalog, me, widget.role, permissions!, (key, value) => setState(() => permissions![key] = value)),
          if (permissions!['ban_users'] == true) permissionDuration(banDays, (v) => setState(() => banDays = v)),
          StaffItemPicker(items: data.items, selected: selected, onChanged: (v) => setState(() => selected = v)),
          FilledButton(onPressed: busy || user == null ? null : () async {
            if (!form.currentState!.validate()) return;
            final target = user!;
            final term = int.parse(days.text);
            if (!await staffConfirm(context, 'تأكيد التعيين', '${target.label}\n${staffRoles[widget.role]} لمدة $term يوم') || !mounted) return;
            final ok = await act(() async { await service.appoint(userId: target.id, role: widget.role, days: term,
              permissions: {for (final p in editable) p.key: permissions![p.key] ?? false},
              allowedItemIds: selected.toList(), banDays: banDays == 0 ? null : banDays); });
            if (ok && context.mounted) Navigator.pop(context);
          }, child: Text(busy ? 'جارٍ التعيين…' : 'تأكيد التعيين'))];
      }));
  }
}

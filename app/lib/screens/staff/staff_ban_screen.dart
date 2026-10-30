import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';
import '../../l10n/tr.dart';

/// 🚫 نظام الحظر (spec 12–14). Shown only to a holder of the ban permission;
/// the server refuses the ban API to anyone else, whatever the app sends.
class StaffBanScreen extends ConsumerStatefulWidget {
  const StaffBanScreen({super.key});
  @override
  ConsumerState<StaffBanScreen> createState() => _StaffBanScreenState();
}

class _StaffBanScreenState extends StaffActionState<StaffBanScreen> {
  final reason = TextEditingController();
  StaffUser? user;
  String duration = '1d';
  String status = 'ACTIVE';

  @override
  void dispose() { reason.dispose(); super.dispose(); }

  Future<void> confirmBan() async {
    final target = user!;
    final why = reason.text.trim();
    if (why.isEmpty) { staffSnack(context, tr('سبب الحظر مطلوب', 'Ban reason is required')); return; }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => Directionality(textDirection: TextDirection.rtl,
      child: AlertDialog(title: Text(tr('تأكيد الحظر', 'Confirm ban')), content: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('ID المستخدم: ${target.displayId ?? target.id}', 'User ID: ${target.displayId ?? target.id}')),
          Text(tr('اسم المستخدم: ${target.name}', 'Username: ${target.name}')),
          Text(tr('مدة الحظر: ${banDurations[duration]}', 'Ban duration: ${banDurations[duration]}')),
          Text(tr('سبب الحظر: $why', 'Ban reason: $why')),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true), child: Text(tr('تأكيد الحظر', 'Confirm ban'))),
        ]))) ?? false;
    if (!ok || !mounted) return;
    final done = await act(() async { await service.ban(target.id, duration, why); }, message: tr('تم حظر ${target.name}', 'Banned ${target.name}'));
    if (done) setState(() { reason.clear(); user = null; });
  }

  @override
  Widget build(BuildContext context) => StaffScreen(title: tr('🚫 نظام الحظر', '🚫 Ban system'), allowed: (a) => a.ban,
    child: StaffPagedLoad<StaffBan>(revision: revision, load: (page) => service.bans(page: page, status: status.isEmpty ? null : status), header: [
      StaffUserLookup(onSelected: (v) => setState(() => user = v)),
      if (user?.staffRole != null) Text(tr('تنبيه: هذا الحساب ${staffRoles[user!.staffRole!.role]} — لا يمكن حظر إداري من نفس الرتبة أو أعلى.', 'Notice: this account is ${staffRoles[user!.staffRole!.role]} — you cannot ban staff of the same or a higher rank.')),
      staffSelect(tr('مدة الحظر', 'Ban duration'), duration, banDurations, (v) => setState(() => duration = v)),
      TextField(controller: reason, maxLines: 2, decoration: InputDecoration(labelText: tr('سبب الحظر (مطلوب)', 'Ban reason (required)'))),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          onPressed: busy || user == null ? null : confirmBan, child: Text(busy ? tr('جارٍ الحظر…', 'Banning…') : tr('حظر', 'Block'))),
      const Divider(),
      staffSelect(tr('سجل الحظر', 'Ban history'), status, {'': tr('الكل', 'All'), 'ACTIVE': tr('ساري', 'Active'), 'LIFTED': tr('تم رفعه', 'Lifted'), 'EXPIRED': tr('منتهي', 'Expired')},
          (v) { setState(() => status = v); reload(); }),
    ], builder: (rows) => rows.map((b) => staffCard(b.user?.label ?? 'ID ${b.userId}',
      leading: b.user == null ? null : staffAvatar(b.user!),
      subtitle: tr('المدة: ${banDurations[b.duration] ?? b.duration} • السبب: ${b.reason}\n'
          'حظره: ${b.bannedBy?.label ?? 'ID ${b.bannedById}'} • ${dateLabel(b.startedAt)}\n'
          'النهاية: ${b.expiresAt == null ? 'أبدي' : dateLabel(b.expiresAt)} • ${b.active ? 'ساري' : statusLabel(b.status)}', 'Duration: ${banDurations[b.duration] ?? b.duration} • Reason: ${b.reason}\nBanned by: ${b.bannedBy?.label ?? 'ID ${b.bannedById}'} • ${dateLabel(b.startedAt)}\nExpires: ${b.expiresAt == null ? 'Permanent' : dateLabel(b.expiresAt)} • ${b.active ? 'Active' : statusLabel(b.status)}'),
      trailing: b.active ? TextButton(onPressed: busy ? null : () async {
        if (!await staffConfirm(context, tr('رفع الحظر', 'Lift ban'), b.user?.label ?? 'ID ${b.userId}') || !mounted) return;
        await act(() => service.unban(b.userId), message: tr('تم رفع الحظر', 'Ban lifted'));
      }, child: Text(tr('رفع الحظر', 'Lift ban'))) : null)).toList()));
}

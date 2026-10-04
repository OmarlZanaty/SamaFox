import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';

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
    if (why.isEmpty) { staffSnack(context, 'سبب الحظر مطلوب'); return; }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => Directionality(textDirection: TextDirection.rtl,
      child: AlertDialog(title: const Text('تأكيد الحظر'), content: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ID المستخدم: ${target.displayId ?? target.id}'),
          Text('اسم المستخدم: ${target.name}'),
          Text('مدة الحظر: ${banDurations[duration]}'),
          Text('سبب الحظر: $why'),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الحظر')),
        ]))) ?? false;
    if (!ok || !mounted) return;
    final done = await act(() async { await service.ban(target.id, duration, why); }, message: 'تم حظر ${target.name}');
    if (done) setState(() { reason.clear(); user = null; });
  }

  @override
  Widget build(BuildContext context) => StaffScreen(title: '🚫 نظام الحظر', allowed: (a) => a.ban,
    child: StaffLoad<List<StaffBan>>(revision: revision, load: () => service.bans(status: status.isEmpty ? null : status), header: [
      StaffUserLookup(onSelected: (v) => setState(() => user = v)),
      if (user?.staffRole != null) Text('تنبيه: هذا الحساب ${staffRoles[user!.staffRole!.role]} — لا يمكن حظر إداري من نفس الرتبة أو أعلى.'),
      staffSelect('مدة الحظر', duration, banDurations, (v) => setState(() => duration = v)),
      TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'سبب الحظر (مطلوب)')),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          onPressed: busy || user == null ? null : confirmBan, child: Text(busy ? 'جارٍ الحظر…' : 'حظر')),
      const Divider(),
      staffSelect('سجل الحظر', status, {'': 'الكل', 'ACTIVE': 'ساري', 'LIFTED': 'تم رفعه', 'EXPIRED': 'منتهي'},
          (v) { setState(() => status = v); reload(); }),
    ], builder: (rows) => rows.map((b) => staffCard(b.user?.label ?? 'ID ${b.userId}',
      leading: b.user == null ? null : staffAvatar(b.user!),
      subtitle: 'المدة: ${banDurations[b.duration] ?? b.duration} • السبب: ${b.reason}\n'
          'حظره: ${b.bannedBy?.label ?? 'ID ${b.bannedById}'} • ${dateLabel(b.startedAt)}\n'
          'النهاية: ${b.expiresAt == null ? 'أبدي' : dateLabel(b.expiresAt)} • ${b.active ? 'ساري' : statusLabel(b.status)}',
      trailing: b.active ? TextButton(onPressed: busy ? null : () async {
        if (!await staffConfirm(context, 'رفع الحظر', b.user?.label ?? 'ID ${b.userId}') || !mounted) return;
        await act(() => service.unban(b.userId), message: 'تم رفع الحظر');
      }, child: const Text('رفع الحظر')) : null)).toList()));
}

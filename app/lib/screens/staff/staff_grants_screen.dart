import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';

const _itemKinds = {'frame': ('🖼️ إطار', 'grant_frame'), 'entry': ('🚪 دخولية', 'grant_entry'), 'bubble': ('💬 فقاعة دردشة', 'grant_bubble')};

/// منح VIP (1–5) / Level (1–20) / منتج — always 7 days; the server ends it on
/// its own and puts the user back to what he had (spec 3, 4, 8).
class StaffGrantScreen extends ConsumerStatefulWidget {
  const StaffGrantScreen({super.key, required this.kind});
  /// 'vip' | 'level' | 'item'
  final String kind;
  @override
  ConsumerState<StaffGrantScreen> createState() => _StaffGrantScreenState();
}

class _StaffGrantScreenState extends StaffActionState<StaffGrantScreen> {
  StaffUser? user;
  int level = 1;
  String itemKind = '';
  StaffItem? item;

  String get title => switch (widget.kind) { 'vip' => '💎 منح VIP', 'level' => '⭐ منح Level', _ => '🎁 منح المنتجات' };

  bool allowed(StaffAccess a) => a.rolePanel && switch (widget.kind) {
    'vip' => a.has('grant_vip'),
    'level' => a.has('grant_level'),
    _ => _itemKinds.values.any((k) => a.has(k.$2)),
  };

  Future<void> submit() async {
    final target = user!;
    final what = switch (widget.kind) { 'vip' => 'VIP $level', 'level' => 'Level $level', _ => item!.name };
    if (!await staffConfirm(context, 'تأكيد المنح', 'منح ${target.label}\n$what\nالمدة: ٧ أيام — تُسحب تلقائياً بعدها') || !mounted) return;
    StaffGrant? grant;
    final ok = await act(() async {
      grant = switch (widget.kind) {
        'vip' => await service.grantVip(target.id, level),
        'level' => await service.grantLevel(target.id, level),
        _ => await service.grantItem(target.id, item!.id),
      };
    }, message: 'تم المنح لمدة ٧ أيام');
    // The server says when the user already owns the product permanently.
    if (ok && mounted && grant?.message != null && grant!.message != 'تم منح المنتج') staffSnack(context, grant!.message!);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    final kinds = {for (final e in _itemKinds.entries) if (me?.has(e.value.$2) == true) e.key: e.value.$1};
    if (widget.kind == 'item' && itemKind.isEmpty && kinds.isNotEmpty) itemKind = kinds.keys.first;
    return StaffScreen(title: title, allowed: allowed,
      child: StaffLoad<List<StaffItem>>(revision: revision,
        load: () async => widget.kind == 'item' && itemKind.isNotEmpty ? await service.grantable(type: itemKind) : <StaffItem>[],
        header: [
          StaffUserLookup(onSelected: (v) => setState(() => user = v)),
          if (widget.kind != 'item') staffSelect(widget.kind == 'vip' ? 'مستوى VIP' : 'المستوى', '$level',
              {for (var i = 1; i <= (widget.kind == 'vip' ? 5 : 20); i++) '$i': widget.kind == 'vip' ? 'VIP $i' : 'Level $i'},
              (v) => setState(() => level = int.parse(v))),
          if (widget.kind == 'item') staffSelect('نوع المنتج', itemKind, kinds, (v) { setState(() { itemKind = v; item = null; }); reload(); }),
          const Text('المدة: ٧ أيام فقط. إن كان لدى المستخدم مستوى أعلى أصلاً يرفض السيرفر المنحة، ولا يُفقد المستخدم ما يملكه بعد انتهائها.'),
        ],
        builder: (items) => [
          if (widget.kind == 'item') ...[
            if (items.isEmpty) const Text('لا توجد منتجات مسموح لك بمنحها من هذا النوع'),
            ...items.map((i) => ListTile(title: Text(i.name), leading: staffThumbnail(i), selected: item?.id == i.id,
              trailing: Icon(item?.id == i.id ? Icons.radio_button_checked : Icons.radio_button_off, color: staffGold),
              onTap: () => setState(() => item = i))),
          ],
          FilledButton(onPressed: busy || user == null || (widget.kind == 'item' && item == null) ? null : submit,
              child: Text(busy ? 'جارٍ المنح…' : 'تأكيد المنح — ٧ أيام')),
          OutlinedButton(onPressed: () => openStaff(context, const StaffGrantsListScreen()), child: const Text('المنح السابقة')),
        ]));
  }
}

/// The grants this staff member (and his team) made, with the term and status.
class StaffGrantsListScreen extends ConsumerStatefulWidget {
  const StaffGrantsListScreen({super.key});
  @override
  ConsumerState<StaffGrantsListScreen> createState() => _StaffGrantsListScreenState();
}

class _StaffGrantsListScreenState extends StaffActionState<StaffGrantsListScreen> {
  String status = 'ACTIVE';
  String describe(StaffGrant g) => switch (g.type) {
    'VIP' => 'VIP ${g.value}',
    'LEVEL' => 'Level ${g.value}',
    _ => g.item?.name ?? 'منتج',
  };
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    return StaffScreen(title: '🎁 المنح المؤقتة', allowed: (a) => a.rolePanel,
      child: StaffLoad<List<StaffGrant>>(revision: revision,
        load: () => service.grants(status: status.isEmpty ? null : status),
        header: [staffSelect('الحالة', status, {'': 'الكل', 'ACTIVE': '🟢 سارية', 'EXPIRED': '🔴 منتهية', 'REVOKED': 'مسحوبة'},
            (v) { setState(() => status = v); reload(); })],
        builder: (rows) => rows.where((g) => g.source == 'GRANT').map((g) => staffCard(
          '${describe(g)} ← ${g.user?.label ?? 'ID ${g.userId}'}',
          subtitle: 'منحها: ${g.grantedBy?.label ?? '—'}\nمن ${dateLabel(g.startedAt)} إلى ${dateLabel(g.expiresAt)} • ${g.active ? '🟢 سارية' : statusLabel(g.status)}',
          trailing: g.active && me?.has(g.permission) == true ? TextButton(onPressed: busy ? null : () async {
            if (!await staffConfirm(context, 'سحب المنحة', '${describe(g)} من ${g.user?.label ?? 'ID ${g.userId}'}') || !mounted) return;
            await act(() => service.revokeGrant(g.id), message: 'تم سحب المنحة');
          }, child: const Text('سحب')) : null)).toList()));
  }
}

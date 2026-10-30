import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';
import '../../l10n/tr.dart';

Map<String, (String, String)> get _itemKinds => {'frame': (tr('🖼️ إطار', '🖼️ Frame'), 'grant_frame'), 'entry': (tr('🚪 دخولية', '🚪 Entrance'), 'grant_entry'), 'bubble': (tr('💬 فقاعة دردشة', '💬 Chat bubble'), 'grant_bubble')};

/// منح VIP / Level حسب حدود السيرفر / منتج — always 7 days; the server ends it on
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

  String get title => switch (widget.kind) { 'vip' => tr('💎 منح VIP', '💎 Grant VIP'), 'level' => tr('⭐ منح Level', '⭐ Grant level'), _ => tr('🎁 منح المنتجات', '🎁 Grant products') };

  bool allowed(StaffAccess a) => a.rolePanel && switch (widget.kind) {
    'vip' => a.has('grant_vip'),
    'level' => a.has('grant_level'),
    _ => _itemKinds.values.any((k) => a.has(k.$2)),
  };

  Future<void> submit() async {
    final target = user!;
    final what = switch (widget.kind) { 'vip' => 'VIP $level', 'level' => 'Level $level', _ => item!.name };
    if (!await staffConfirm(context, tr('تأكيد المنح', 'Confirm grant'), tr('منح ${target.label}\n$what\nالمدة: ٧ أيام — تُسحب تلقائياً بعدها', 'Grant to ${target.label}\n$what\nDuration: 7 days — removed automatically afterward')) || !mounted) return;
    StaffGrant? grant;
    final ok = await act(() async {
      grant = switch (widget.kind) {
        'vip' => await service.grantVip(target.id, level),
        'level' => await service.grantLevel(target.id, level),
        _ => await service.grantItem(target.id, item!.id),
      };
    }, message: tr('تم المنح لمدة ٧ أيام', 'Granted for 7 days'));
    // The server says when the user already owns the product permanently.
    if (ok && mounted && grant?.message != null && grant!.message != 'تم منح المنتج' /* i18n: compared with server data */) staffSnack(context, grant!.message!);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffPanelAccessProvider).valueOrNull;
    final cap = widget.kind == 'vip' ? me?.vipCap ?? 5 : me?.levelCap ?? 20;
    final kinds = {for (final e in _itemKinds.entries) if (me?.has(e.value.$2) == true) e.key: e.value.$1};
    if (widget.kind == 'item' && itemKind.isEmpty && kinds.isNotEmpty) itemKind = kinds.keys.first;
    return StaffScreen(title: title, allowed: allowed,
      child: StaffLoad<List<StaffItem>>(revision: revision,
        load: () async => widget.kind == 'item' && itemKind.isNotEmpty ? await service.grantable(type: itemKind) : <StaffItem>[],
        header: [
          StaffUserLookup(onSelected: (v) => setState(() => user = v)),
          if (widget.kind != 'item') staffSelect(widget.kind == 'vip' ? tr('مستوى VIP', 'VIP level') : tr('المستوى', 'Level'), '$level',
              {for (var i = 1; i <= cap; i++) '$i': widget.kind == 'vip' ? 'VIP $i' : 'Level $i'},
              (v) => setState(() => level = int.parse(v))),
          if (widget.kind == 'item') staffSelect(tr('نوع المنتج', 'Product type'), itemKind, kinds, (v) { setState(() { itemKind = v; item = null; }); reload(); }),
          Text(tr('المدة: ٧ أيام فقط. إن كان لدى المستخدم مستوى أعلى أصلاً يرفض السيرفر المنحة، ولا يُفقد المستخدم ما يملكه بعد انتهائها.', 'Duration: 7 days only. If the user already has a higher level, the server rejects the grant. The user keeps their existing items when it expires.')),
        ],
        builder: (items) => [
          if (widget.kind == 'item') ...[
            if (items.isEmpty) Text(tr('لا توجد منتجات مسموح لك بمنحها من هذا النوع', 'You have no products of this type available to grant')),
            ...items.map((i) => ListTile(title: Text(i.name), leading: staffThumbnail(i), selected: item?.id == i.id,
              trailing: Icon(item?.id == i.id ? Icons.radio_button_checked : Icons.radio_button_off, color: staffGold),
              onTap: () => setState(() => item = i))),
          ],
          FilledButton(onPressed: busy || user == null || (widget.kind == 'item' && item == null) ? null : submit,
              child: Text(busy ? tr('جارٍ المنح…', 'Granting…') : tr('تأكيد المنح — ٧ أيام', 'Confirm grant — 7 days'))),
          OutlinedButton(onPressed: () => openStaff(context, const StaffGrantsListScreen()), child: Text(tr('المنح السابقة', 'Previous grants'))),
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
    _ => g.item?.name ?? tr('منتج', 'Product'),
  };
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffPanelAccessProvider).valueOrNull;
    return StaffScreen(title: tr('🎁 المنح المؤقتة', '🎁 Temporary grants'), allowed: (a) => a.rolePanel,
      child: StaffPagedLoad<StaffGrant>(revision: revision,
        load: (page) => service.grants(page: page, status: status.isEmpty ? null : status),
        header: [staffSelect(tr('الحالة', 'Status'), status, {'': tr('الكل', 'All'), 'ACTIVE': tr('🟢 سارية', '🟢 Active'), 'EXPIRED': tr('🔴 منتهية', '🔴 Expired'), 'REVOKED': tr('مسحوبة', 'Revoked')},
            (v) { setState(() => status = v); reload(); })],
        builder: (rows) => rows.where((g) => g.source == 'GRANT').map((g) => staffCard(
          '${describe(g)} ← ${g.user?.label ?? 'ID ${g.userId}'}',
          subtitle: tr('منحها: ${g.grantedBy?.label ?? '—'}\nمن ${dateLabel(g.startedAt)} إلى ${dateLabel(g.expiresAt)} • ${g.active ? '🟢 سارية' : statusLabel(g.status)}', 'Granted by: ${g.grantedBy?.label ?? '—'}\nFrom ${dateLabel(g.startedAt)} to ${dateLabel(g.expiresAt)} • ${g.active ? '🟢 Active' : statusLabel(g.status)}'),
          trailing: g.active && me?.has(g.permission) == true ? TextButton(onPressed: busy ? null : () async {
            if (!await staffConfirm(context, tr('سحب المنحة', 'Revoke grant'), tr('${describe(g)} من ${g.user?.label ?? 'ID ${g.userId}'}', '${describe(g)} from ${g.user?.label ?? 'ID ${g.userId}'}')) || !mounted) return;
            await act(() => service.revokeGrant(g.id), message: tr('تم سحب المنحة', 'Grant revoked'));
          }, child: Text(tr('سحب', 'Revoke'))) : null)).toList()));
  }
}

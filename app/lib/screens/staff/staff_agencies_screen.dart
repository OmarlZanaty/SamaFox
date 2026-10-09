import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';

String _coins(num n) {
  final s = n.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

Widget agencyCard(BuildContext context, StaffAgency agency, {bool canOpen = true}) => staffCard(
  '🏢 ${agency.name} (#${agency.id})',
  subtitle: 'الوكيل: ${agency.owner.label}\n'
      'المضيفون: ${agency.membersCount} • الإنتاج: ${_coins(agency.production)} كوينز\n'
      'أنشأها: ${agency.creator?.label ?? '—'}'
      '${agency.followers.isEmpty ? '' : '\nالمتابعون: ${agency.followers.map((u) => u.name).join('، ')}'}',
  trailing: canOpen ? const Icon(Icons.chevron_left) : null,
  onTap: canOpen ? () => openStaff(context, StaffAgencyScreen(agencyId: agency.id)) : null,
);

/// وكالات المضيفين — only hosting agencies inside the caller's scope; the
/// server answers 403 for anything else (spec 22).
class StaffAgenciesScreen extends ConsumerStatefulWidget {
  const StaffAgenciesScreen({super.key});
  @override
  ConsumerState<StaffAgenciesScreen> createState() => _StaffAgenciesScreenState();
}

class _StaffAgenciesScreenState extends StaffActionState<StaffAgenciesScreen> {
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    final canCreate = me?.has('manage_host_agency') == true;
    final canFollow = me?.has('follow_agencies') == true;
    return StaffScreen(title: '🏢 وكالات المضيفين',
      allowed: (a) => a.rolePanel && (a.has('follow_agencies') || a.has('manage_host_agency')),
      child: StaffLoad<List<StaffAgency>>(revision: revision,
        load: () async => canFollow ? await service.agencies() : <StaffAgency>[],
        header: [
          if (canCreate) FilledButton.icon(icon: const Icon(Icons.add_business),
            onPressed: () async { await openStaff(context, const StaffAgencyCreateScreen()); reload(); },
            label: const Text('إنشاء / تفعيل وكالة مضيفين')),
          const Text('وكالات مضيفين فقط — لا تشمل وكالات الشحن أو الكوينزات.'),
          if (!canFollow) const Text('متابعة الوكالات غير مفعلة لحسابك.'),
        ],
        builder: (rows) => rows.map((a) => agencyCard(context, a, canOpen: canFollow)).toList()));
  }
}

class StaffAgencyCreateScreen extends ConsumerStatefulWidget {
  const StaffAgencyCreateScreen({super.key});
  @override
  ConsumerState<StaffAgencyCreateScreen> createState() => _StaffAgencyCreateScreenState();
}

class _StaffAgencyCreateScreenState extends StaffActionState<StaffAgencyCreateScreen> {
  final name = TextEditingController();
  StaffUser? owner;
  @override
  void dispose() { name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => StaffScreen(title: 'إنشاء وكالة مضيفين',
    allowed: (a) => a.rolePanel && a.has('manage_host_agency'),
    child: StaffRefreshList(onRefresh: () async => ref.refresh(staffMeProvider.future), children: [
      const Text('ID الوكيل (المسؤول عن الوكالة):'),
      StaffUserLookup(onSelected: (v) => setState(() => owner = v)),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الوكالة')),
      FilledButton(onPressed: busy || owner == null ? null : () async {
        final agencyName = name.text.trim();
        if (agencyName.isEmpty) { staffSnack(context, 'اكتب اسم الوكالة'); return; }
        final target = owner!;
        if (!await staffConfirm(context, 'تأكيد إنشاء الوكالة', '«$agencyName»\nالوكيل: ${target.label}') || !mounted) return;
        final ok = await act(() async { await service.createAgency(target.id, agencyName); }, message: 'تم إنشاء الوكالة وتفعيلها');
        if (ok && context.mounted) Navigator.pop(context);
      }, child: Text(busy ? 'جارٍ الإنشاء…' : 'إنشاء الوكالة')),
    ]));
}

class StaffAgencyScreen extends ConsumerStatefulWidget {
  const StaffAgencyScreen({super.key, required this.agencyId});
  final int agencyId;
  @override
  ConsumerState<StaffAgencyScreen> createState() => _StaffAgencyScreenState();
}

class _StaffAgencyScreenState extends StaffActionState<StaffAgencyScreen> {
  Future<void> addFollower() async {
    final value = await staffPrompt(context, 'تعيين متابع للوكالة', label: 'ID الإداري (Super Admin / Admin)', numeric: true);
    final id = int.tryParse(value ?? '');
    if (id == null || !mounted) return;
    // Followers are addressed by account id; the lookup takes the visible ID
    // and says whether he holds a role at all.
    StaffUser user;
    try {
      user = await service.lookup(id);
    } catch (e) {
      if (mounted) staffSnack(context, staffError(e));
      return;
    }
    if (!mounted) return;
    if (user.staffRole == null) { staffSnack(context, 'هذا المستخدم ليس إدارياً'); return; }
    await act(() => service.addFollower(widget.agencyId, user.id), message: 'تم تعيين المتابع');
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(staffMeProvider).valueOrNull;
    final canAssign = me?.manages == true && me?.has('manage_host_agency') == true;
    return StaffScreen(title: 'تفاصيل الوكالة', allowed: (a) => a.rolePanel && a.has('follow_agencies'),
      child: StaffLoad<StaffAgency>(revision: revision, load: () => service.agency(widget.agencyId), builder: (a) => [
        agencyCard(context, a, canOpen: false),
        staffHeading('المتابعون'),
        if (a.followers.isEmpty) const Text('لا يوجد متابعون معيّنون'),
        ...a.followers.map((u) => staffCard(u.label, leading: staffAvatar(u),
          trailing: canAssign ? TextButton(onPressed: busy ? null : () async {
            if (!await staffConfirm(context, 'إزالة المتابع', u.label) || !mounted) return;
            await act(() => service.removeFollower(a.id, u.id), message: 'تمت الإزالة');
          }, child: const Text('إزالة')) : null)),
        if (canAssign) OutlinedButton.icon(icon: const Icon(Icons.person_add_alt),
            onPressed: busy ? null : addFollower, label: const Text('تعيين Super Admin / Admin لمتابعتها')),
        staffHeading('المضيفون — الإنتاج هذا الشهر'),
        if (a.hosts.isEmpty) const Text('لا يوجد مضيفون'),
        ...a.hosts.map((h) => staffCard(h.user.label, leading: staffAvatar(h.user),
          subtitle: 'التارجت: ${_coins(h.target)} كوينز • ساعات البث هذا الشهر: ${h.broadcastHours.toStringAsFixed(1)}')),
      ]));
  }
}

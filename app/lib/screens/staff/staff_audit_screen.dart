import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';

const staffAuditActions = {
  '': 'كل العمليات',
  'STAFF_APPOINT': 'تعيين', 'STAFF_EXTEND': 'تمديد', 'STAFF_RENEW': 'تجديد',
  'STAFF_REVOKE': 'سحب الإدارة', 'STAFF_EXPIRED': 'انتهاء الإدارة',
  'STAFF_PERMISSION_GRANT': 'منح صلاحية', 'STAFF_PERMISSION_REVOKE': 'سحب صلاحية',
  'STAFF_PERMISSION_EXPIRED': 'انتهاء صلاحية',
  'STAFF_ALLOWED_ITEMS_SET': 'المنتجات المسموحة', 'STAFF_REWARD_ITEMS_SET': 'مكافآت الإداري',
  'STAFF_ROLE_REWARDS_CONFIG': 'مكافآت الإدارة', 'STAFF_GRANTABLE_POOL_SET': 'قائمة منتجات المنح',
  'STAFF_REPARENT': 'تغيير المسؤول',
  'STAFF_GRANT_VIP': 'منح VIP', 'STAFF_GRANT_LEVEL': 'منح Level', 'STAFF_GRANT_ITEM': 'منح منتج',
  'STAFF_GRANT_REVOKE': 'سحب منحة', 'STAFF_GRANT_EXPIRED': 'انتهاء منحة',
  'STAFF_AGENCY_CREATE': 'إنشاء وكالة', 'STAFF_AGENCY_FOLLOWER_ADD': 'إضافة متابع لوكالة',
  'STAFF_AGENCY_FOLLOWER_REMOVE': 'إزالة متابع وكالة',
  'STAFF_BAN': 'حظر', 'STAFF_UNBAN': 'رفع الحظر', 'STAFF_BAN_EXPIRED': 'انتهاء الحظر',
};

const _itemTypes = {
  'FRAME': 'إطار', 'ENTRANCE_BANNER': 'دخولية', 'ENTRANCE_EFFECT': 'دخولية',
  'CHAT_BUBBLE': 'فقاعة دردشة', 'BADGE': 'شارة',
};

String _who(StaffUser? user, int? id) {
  if (id == 0) return 'النظام';
  if (user != null) return '${user.name} (ID ${user.displayId ?? user.id})';
  return id == null ? '—' : 'ID $id';
}

dynamic _field(dynamic json, String key) {
  if (json is Map) return json[key];
  if (json is List && json.isNotEmpty && json.first is Map) return (json.first as Map)[key];
  return null;
}

const _grantTypes = {'VIP': 'VIP', 'LEVEL': 'Level', 'ITEM': 'منتج'};
String _grantType(dynamic json) => _grantTypes[_field(json, 'type')] ?? '';

String _date(dynamic value) => value is String ? dateLabel(DateTime.tryParse(value)) : '—';

/// One audit row as a sentence, in the shape of the spec's examples:
/// «Manager … قام بتعيين … كـSuper Admin — المدة … — الانتهاء …».
String staffAuditSentence(StaffAudit a) {
  final actor = _who(a.actor, a.actorId);
  final target = _who(a.targetUser, a.targetUserId);
  final after = a.after, before = a.before;
  String role(dynamic json) => staffRoles[_field(json, 'role')] ?? '';
  String perm(dynamic json) => permissionLabels[_field(json, 'permission')] ?? (_field(json, 'permission')?.toString() ?? '');
  switch (a.action) {
    case 'STAFF_APPOINT':
      return '$actor قام بتعيين $target كـ${role(after)} — تاريخ الانتهاء: ${_date(_field(after, 'expiresAt'))}';
    case 'STAFF_EXTEND':
      return '$actor مدّد إدارة $target — من ${_date(_field(before, 'expiresAt'))} إلى ${_date(_field(after, 'expiresAt'))}';
    case 'STAFF_RENEW':
      return '$actor جدّد إدارة $target كـ${role(after)} — المدة القديمة حتى ${_date(_field(after, 'oldExpiresAt'))}، الجديدة حتى ${_date(_field(after, 'newExpiresAt'))}';
    case 'STAFF_REVOKE':
      return '$actor سحب إدارة $target${a.reason == null ? '' : ' — السبب: ${a.reason}'}';
    case 'STAFF_EXPIRED':
      return 'انتهت مدة إدارة $target تلقائياً';
    case 'STAFF_PERMISSION_GRANT':
      return '$actor منح $target صلاحية ${perm(after)}${_field(after, 'expiresAt') == null ? '' : ' حتى ${_date(_field(after, 'expiresAt'))}'}';
    case 'STAFF_PERMISSION_REVOKE':
      return '$actor سحب صلاحية ${perm(before)} من $target';
    case 'STAFF_PERMISSION_EXPIRED':
      return 'انتهت صلاحية ${perm(before)} لـ $target';
    case 'STAFF_GRANT_VIP':
      return '$actor منح $target VIP ${_field(after, 'value')} — المدة: ٧ أيام';
    case 'STAFF_GRANT_LEVEL':
      return '$actor منح $target Level ${_field(after, 'value')} — المدة: ٧ أيام';
    case 'STAFF_GRANT_ITEM':
      final source = _field(after, 'source') == 'ROLE_REWARD' ? ' (مكافأة إدارة)' : ' — المدة: ٧ أيام';
      return '$actor منح $target ${_itemTypes[_field(after, 'itemType')] ?? 'منتجاً'}$source';
    case 'STAFF_GRANT_REVOKE':
      return '$actor سحب منحة ${_grantType(before)} من $target';
    case 'STAFF_GRANT_EXPIRED':
      return 'انتهت منحة ${_grantType(before)} لـ $target تلقائياً';
    case 'STAFF_AGENCY_CREATE':
      return '$actor أنشأ وكالة المضيفين «${_field(after, 'agencyName') ?? ''}» ووكيلها $target';
    case 'STAFF_AGENCY_FOLLOWER_ADD':
      return '$actor كلّف $target بمتابعة الوكالة #${a.targetId}';
    case 'STAFF_AGENCY_FOLLOWER_REMOVE':
      return '$actor أزال $target من متابعة الوكالة #${a.targetId}';
    case 'STAFF_BAN':
      return '$actor حظر $target — المدة: ${banDurations[_field(after, 'duration')] ?? ''} — السبب: ${_field(after, 'reason') ?? ''}';
    case 'STAFF_UNBAN':
      return '$actor رفع الحظر عن $target';
    case 'STAFF_BAN_EXPIRED':
      return 'انتهى حظر $target';
    case 'STAFF_REPARENT':
      return '$actor غيّر المسؤول المباشر عن $target';
    case 'STAFF_ALLOWED_ITEMS_SET':
      return '$actor عدّل المنتجات المسموحة لـ $target';
    case 'STAFF_REWARD_ITEMS_SET':
      return '$actor عدّل مكافآت الإداري $target';
    case 'STAFF_ROLE_REWARDS_CONFIG':
      return '$actor عدّل مكافآت الإدارة';
    case 'STAFF_GRANTABLE_POOL_SET':
      return '$actor عدّل قائمة المنتجات المسموح بمنحها';
    default:
      return '$actor — ${staffAuditActions[a.action] ?? a.action} — $target';
  }
}

Widget staffAuditCard(StaffAudit a) => staffCard(staffAuditSentence(a),
    subtitle: '${staffAuditActions[a.action] ?? a.action} • ${dateLabel(a.createdAt)}');

/// سجل العمليات — read-only; the server never deletes these rows.
class StaffAuditScreen extends ConsumerStatefulWidget {
  const StaffAuditScreen({super.key, this.actorId});
  final int? actorId;
  @override
  ConsumerState<StaffAuditScreen> createState() => _StaffAuditScreenState();
}

class _StaffAuditScreenState extends StaffActionState<StaffAuditScreen> {
  String action = '';
  int page = 1;
  @override
  Widget build(BuildContext context) => StaffScreen(title: '📜 سجل العمليات', allowed: (a) => a.rolePanel || a.ban,
    child: StaffLoad<StaffAuditPage>(revision: revision,
      load: () => service.audit(page: page, actorId: widget.actorId, action: action.isEmpty ? null : action),
      header: [staffSelect('العملية', action, staffAuditActions, (v) { setState(() { action = v; page = 1; }); reload(); })],
      builder: (data) {
        final pages = (data.total / data.pageSize).ceil().clamp(1, 1 << 30);
        return [
          ...data.rows.map(staffAuditCard),
          if (data.rows.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: data.page > 1 ? () { setState(() => page = data.page - 1); reload(); } : null, child: const Text('السابق')),
            Text('صفحة ${data.page} من $pages • ${data.total} عملية'),
            TextButton(onPressed: data.page < pages ? () { setState(() => page = data.page + 1); reload(); } : null, child: const Text('التالي')),
          ]),
        ];
      }));
}

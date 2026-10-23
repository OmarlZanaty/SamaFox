import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/staff_service.dart';
import 'staff_widgets.dart';
import '../../l10n/tr.dart';

Map<String, String> get staffAuditActions => {
  '': tr('كل العمليات', 'All actions'),
  'STAFF_APPOINT': tr('تعيين', 'Appoint'), 'STAFF_EXTEND': tr('تمديد', 'Extend'), 'STAFF_RENEW': tr('تجديد', 'Renew'),
  'STAFF_REVOKE': tr('سحب الإدارة', 'Revoke role'), 'STAFF_EXPIRED': tr('انتهاء الإدارة', 'Role expired'),
  'STAFF_PERMISSION_GRANT': tr('منح صلاحية', 'Grant permission'), 'STAFF_PERMISSION_REVOKE': tr('سحب صلاحية', 'Revoke permission'),
  'STAFF_PERMISSION_EXPIRED': tr('انتهاء صلاحية', 'Permission expired'),
  'STAFF_ALLOWED_ITEMS_SET': tr('المنتجات المسموحة', 'Allowed products'), 'STAFF_REWARD_ITEMS_SET': tr('مكافآت الإداري', 'Staff rewards'),
  'STAFF_ROLE_REWARDS_CONFIG': tr('مكافآت الإدارة', 'Management rewards'), 'STAFF_GRANTABLE_POOL_SET': tr('قائمة منتجات المنح', 'Grantable products'),
  'STAFF_REPARENT': tr('تغيير المسؤول', 'Change supervisor'),
  'STAFF_GRANT_VIP': tr('منح VIP', 'Grant VIP'), 'STAFF_GRANT_LEVEL': tr('منح Level', 'Grant level'), 'STAFF_GRANT_ITEM': tr('منح منتج', 'Grant product'),
  'STAFF_GRANT_REVOKE': tr('سحب منحة', 'Revoke grant'), 'STAFF_GRANT_EXPIRED': tr('انتهاء منحة', 'Grant expired'),
  'STAFF_AGENCY_CREATE': tr('إنشاء وكالة', 'Create agency'), 'STAFF_AGENCY_FOLLOWER_ADD': tr('إضافة متابع لوكالة', 'Add agency follower'),
  'STAFF_AGENCY_FOLLOWER_REMOVE': tr('إزالة متابع وكالة', 'Remove agency follower'),
  'STAFF_BAN': tr('حظر', 'Block'), 'STAFF_UNBAN': tr('رفع الحظر', 'Lift ban'), 'STAFF_BAN_EXPIRED': tr('انتهاء الحظر', 'Ban expired'),
};

Map<String, String> get _itemTypes => {
  'FRAME': tr('إطار', 'Frame'), 'ENTRANCE_BANNER': tr('دخولية', 'Entrance'), 'ENTRANCE_EFFECT': tr('دخولية', 'Entrance'),
  'CHAT_BUBBLE': tr('فقاعة دردشة', 'Chat bubble'), 'BADGE': tr('شارة', 'Badge'),
};

String _who(StaffUser? user, int? id) {
  if (id == 0) return tr('النظام', 'System');
  if (user != null) return '${user.name} (ID ${user.displayId ?? user.id})';
  return id == null ? '—' : 'ID $id';
}

dynamic _field(dynamic json, String key) {
  if (json is Map) return json[key];
  if (json is List && json.isNotEmpty && json.first is Map) return (json.first as Map)[key];
  return null;
}

Map<String, String> get _grantTypes => {'VIP': 'VIP', 'LEVEL': tr('المستوى', 'Level'), 'ITEM': tr('منتج', 'Product')};
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
      return tr('$actor قام بتعيين $target كـ${role(after)} — تاريخ الانتهاء: ${_date(_field(after, 'expiresAt'))}', '$actor appointed $target as ${role(after)} — expires: ${_date(_field(after, 'expiresAt'))}');
    case 'STAFF_EXTEND':
      return tr('$actor مدّد إدارة $target — من ${_date(_field(before, 'expiresAt'))} إلى ${_date(_field(after, 'expiresAt'))}', '$actor extended the role of $target — from ${_date(_field(before, 'expiresAt'))} to ${_date(_field(after, 'expiresAt'))}');
    case 'STAFF_RENEW':
      return tr('$actor جدّد إدارة $target كـ${role(after)} — المدة القديمة حتى ${_date(_field(after, 'oldExpiresAt'))}، الجديدة حتى ${_date(_field(after, 'newExpiresAt'))}', '$actor renewed the role of $target as ${role(after)} — previous expiry: ${_date(_field(after, 'oldExpiresAt'))}, new expiry: ${_date(_field(after, 'newExpiresAt'))}');
    case 'STAFF_REVOKE':
      return tr('$actor سحب إدارة $target${a.reason == null ? '' : ' — السبب: ${a.reason}'}', '$actor revoked the role of $target${a.reason == null ? '' : ' — reason: ${a.reason}'}');
    case 'STAFF_EXPIRED':
      return tr('انتهت مدة إدارة $target تلقائياً', 'The role of $target expired automatically');
    case 'STAFF_PERMISSION_GRANT':
      return tr('$actor منح $target صلاحية ${perm(after)}${_field(after, 'expiresAt') == null ? '' : ' حتى ${_date(_field(after, 'expiresAt'))}'}', '$actor granted $target permission ${perm(after)}${_field(after, 'expiresAt') == null ? '' : ' until ${_date(_field(after, 'expiresAt'))}'}');
    case 'STAFF_PERMISSION_REVOKE':
      return tr('$actor سحب صلاحية ${perm(before)} من $target', '$actor revoked permission ${perm(before)} from $target');
    case 'STAFF_PERMISSION_EXPIRED':
      return tr('انتهت صلاحية ${perm(before)} لـ $target', 'Permission ${perm(before)} expired for $target');
    case 'STAFF_GRANT_VIP':
      return tr('$actor منح $target VIP ${_field(after, 'value')} — المدة: ٧ أيام', '$actor granted $target VIP ${_field(after, 'value')} — duration: 7 days');
    case 'STAFF_GRANT_LEVEL':
      return tr('$actor منح $target Level ${_field(after, 'value')} — المدة: ٧ أيام', '$actor granted $target level ${_field(after, 'value')} — duration: 7 days');
    case 'STAFF_GRANT_ITEM':
      final source = _field(after, 'source') == 'ROLE_REWARD' ? tr(' (مكافأة إدارة)', ' (role reward)') : tr(' — المدة: ٧ أيام', ' — duration: 7 days');
      return tr('$actor منح $target ${_itemTypes[_field(after, 'itemType')] ?? 'منتجاً'}$source', '$actor granted $target ${_itemTypes[_field(after, 'itemType')] ?? 'a product'}$source');
    case 'STAFF_GRANT_REVOKE':
      return tr('$actor سحب منحة ${_grantType(before)} من $target', '$actor revoked grant ${_grantType(before)} from $target');
    case 'STAFF_GRANT_EXPIRED':
      return tr('انتهت منحة ${_grantType(before)} لـ $target تلقائياً', 'Grant ${_grantType(before)} expired automatically for $target');
    case 'STAFF_AGENCY_CREATE':
      return tr('$actor أنشأ وكالة المضيفين «${_field(after, 'agencyName') ?? ''}» ووكيلها $target', '$actor created hosting agency «${_field(after, 'agencyName') ?? ''}» with agent $target');
    case 'STAFF_AGENCY_FOLLOWER_ADD':
      return tr('$actor كلّف $target بمتابعة الوكالة #${a.targetId}', '$actor assigned $target to follow agency #${a.targetId}');
    case 'STAFF_AGENCY_FOLLOWER_REMOVE':
      return tr('$actor أزال $target من متابعة الوكالة #${a.targetId}', '$actor removed $target from following agency #${a.targetId}');
    case 'STAFF_BAN':
      return tr('$actor حظر $target — المدة: ${banDurations[_field(after, 'duration')] ?? ''} — السبب: ${_field(after, 'reason') ?? ''}', '$actor banned $target — duration: ${banDurations[_field(after, 'duration')] ?? ''} — reason: ${_field(after, 'reason') ?? ''}');
    case 'STAFF_UNBAN':
      return tr('$actor رفع الحظر عن $target', '$actor lifted the ban on $target');
    case 'STAFF_BAN_EXPIRED':
      return tr('انتهى حظر $target', 'The ban on $target expired');
    case 'STAFF_REPARENT':
      return tr('$actor غيّر المسؤول المباشر عن $target', '$actor changed the direct supervisor of $target');
    case 'STAFF_ALLOWED_ITEMS_SET':
      return tr('$actor عدّل المنتجات المسموحة لـ $target', '$actor updated allowed products for $target');
    case 'STAFF_REWARD_ITEMS_SET':
      return tr('$actor عدّل مكافآت الإداري $target', '$actor updated staff rewards for $target');
    case 'STAFF_ROLE_REWARDS_CONFIG':
      return tr('$actor عدّل مكافآت الإدارة', '$actor updated management rewards');
    case 'STAFF_GRANTABLE_POOL_SET':
      return tr('$actor عدّل قائمة المنتجات المسموح بمنحها', '$actor updated grantable products');
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
  Widget build(BuildContext context) => StaffScreen(title: tr('📜 سجل العمليات', '📜 Activity log'), allowed: (a) => a.rolePanel || a.ban,
    child: StaffLoad<StaffAuditPage>(revision: revision,
      load: () => service.audit(page: page, actorId: widget.actorId, action: action.isEmpty ? null : action),
      header: [staffSelect(tr('العملية', 'Action'), action, staffAuditActions, (v) { setState(() { action = v; page = 1; }); reload(); })],
      builder: (data) {
        final pages = (data.total / data.pageSize).ceil().clamp(1, 1 << 30);
        return [
          ...data.rows.map(staffAuditCard),
          if (data.rows.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: data.page > 1 ? () { setState(() => page = data.page - 1); reload(); } : null, child: Text(tr('السابق', 'Previous'))),
            Text(tr('صفحة ${data.page} من $pages • ${data.total} عملية', 'Page ${data.page} of $pages • ${data.total} actions')),
            TextButton(onPressed: data.page < pages ? () { setState(() => page = data.page + 1); reload(); } : null, child: Text(tr('التالي', 'Next'))),
          ]),
        ];
      }));
}

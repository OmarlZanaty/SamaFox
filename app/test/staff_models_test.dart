import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/services/staff_service.dart';

/// Every staff screen parses one of these. The fixtures are real responses
/// captured from the server (tests/e2e/staff.e2e.ts data), so a field the app
/// expects with the wrong name or type fails here instead of hiding a whole
/// section of Settings on a phone.
dynamic fixture(String name) {
  final body = jsonDecode(File('test/fixtures/staff/$name.json').readAsStringSync()) as Map;
  expect(body['success'], true, reason: name);
  return body['data'];
}

void main() {
  test('me (Manager) → the admin systems shown in Settings', () {
    final me = StaffAccess.fromJson(staffJson(fixture('me')));
    expect(me.role, 'MANAGER');
    expect(me.manager, isTrue);
    expect(me.rolePanel, isTrue);
    expect(me.ban, isTrue);
    expect(me.manages, isTrue);
    expect(me.maxDays, 365);
    expect(me.has('grant_vip'), isTrue);
  });

  test('catalog, lookup, members and a staff file', () {
    final catalog = staffList(fixture('permissions_catalog'), StaffPermissionDefinition.fromJson);
    expect(catalog.map((d) => d.key), contains('ban_users'));
    final user = StaffUser.fromJson(staffJson(fixture('users_lookup_id_100004')));
    expect(user.displayId, 100004);
    final members = staffList(fixture('members'), StaffRole.fromJson);
    expect(members, isNotEmpty);
    expect(members.first.user, isNotNull);
    final file = StaffFile.fromJson(staffJson(fixture('members_5')));
    expect(file.role.role, 'SUPER_ADMIN');
    expect(file.permissions, isNotEmpty);
  });

  test('grants, bans, audit, agencies, items', () {
    final grants = staffList(fixture('grants'), StaffGrant.fromJson);
    expect(grants.first.user, isNotNull);
    expect(grants.where((g) => g.type == 'ITEM').first.item, isNotNull);
    final bans = staffList(fixture('bans'), StaffBan.fromJson);
    expect(bans.first.user?.name, isNotEmpty);
    final audit = StaffAuditPage.fromJson(staffJson(fixture('audit')));
    expect(audit.rows, isNotEmpty);
    expect(audit.rows.any((r) => r.actor != null), isTrue);
    final agencies = staffList(fixture('agencies'), StaffAgency.fromJson);
    expect(agencies.first.owner.name, isNotEmpty);
    final agency = StaffAgency.fromJson(staffJson(fixture('agencies_1')));
    expect(agency.hosts, isNotEmpty);
    expect(staffList(fixture('items_pool'), StaffItem.fromJson), isNotEmpty);
    expect(staffList(fixture('items_grantable'), StaffItem.fromJson), isNotEmpty);
    expect(staffList(fixture('ban-holders'), StaffPermission.fromJson), isEmpty);
    expect(staffJson(fixture('config_role-rewards'))['ADMIN'], ['badge1']);
  });
}

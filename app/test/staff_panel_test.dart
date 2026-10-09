import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/providers/staff_provider.dart';
import 'package:samafox/screens/staff/staff_panel_screen.dart';
import 'package:samafox/services/staff_service.dart';

StaffAccess access(String role, List<String> permissions) => StaffAccess.fromJson({
      'role': role,
      'roleId': 1,
      'status': 'ACTIVE',
      'startedAt': DateTime.now().toIso8601String(),
      'expiresAt': DateTime.now().add(const Duration(days: 20)).toIso8601String(),
      'assignedBy': {'id': 2, 'name': 'm', 'displayId': 100002},
      'permissions': permissions,
      'banSystem': permissions.contains('ban_users'),
      'panels': {
        'manager': role == 'MANAGER',
        'superAdmin': role == 'SUPER_ADMIN' && permissions.contains('role_panel'),
        'admin': role == 'ADMIN' && permissions.contains('role_panel'),
        'ban': permissions.contains('ban_users'),
      },
      'allowedItemIds': <String>[],
      'rank': 1,
    });

Future<void> pumpPanel(WidgetTester tester, StaffAccess me) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [staffMeProvider.overrideWith((ref) async => me)],
    child: const MaterialApp(home: StaffPanelScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const all = ['role_panel', 'manage_admins', 'grant_vip', 'grant_level', 'grant_frame', 'grant_entry',
    'grant_bubble', 'manage_host_agency', 'follow_agencies', 'ban_users'];

  testWidgets('Manager sees every section, including appointing a Super Admin', (tester) async {
    await pumpPanel(tester, access('MANAGER', all));
    expect(find.text('👑 نظام إدارة Manager'), findsOneWidget);
    for (final t in ['👥 الإداريون', '💎 تعيين Super Admin', '🛡️ تعيين Admin', '🔐 صلاحيات الإدارة',
      '💎 منح VIP', '⭐ منح Level', '🎁 منح المنتجات', '🏢 وكالات المضيفين', '📜 سجل العمليات']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('Super Admin appoints Admins only, and only what he holds is shown', (tester) async {
    await pumpPanel(tester, access('SUPER_ADMIN', ['role_panel', 'manage_admins', 'grant_vip', 'follow_agencies']));
    expect(find.text('💎 نظام إدارة Super Admin'), findsOneWidget);
    expect(find.text('🛡️ تعيين Admin'), findsOneWidget);
    expect(find.text('💎 تعيين Super Admin'), findsNothing);
    expect(find.text('💎 منح VIP'), findsOneWidget);
    expect(find.text('⭐ منح Level'), findsNothing);
    expect(find.text('🎁 منح المنتجات'), findsNothing);
    expect(find.text('🏢 وكالات المضيفين'), findsOneWidget);
  });

  testWidgets('Admin: hosting agencies and his own log, no staff management, no grants', (tester) async {
    await pumpPanel(tester, access('ADMIN', ['role_panel', 'manage_host_agency', 'follow_agencies']));
    expect(find.text('🛡️ نظام إدارة Admin'), findsOneWidget);
    expect(find.text('👥 الإداريون'), findsNothing);
    expect(find.text('🛡️ تعيين Admin'), findsNothing);
    expect(find.text('🔐 صلاحيات الإدارة'), findsNothing);
    expect(find.text('💎 منح VIP'), findsNothing);
    expect(find.text('🏢 وكالات المضيفين'), findsOneWidget);
    expect(find.text('📜 سجل العمليات'), findsOneWidget);
  });

  testWidgets('a Super Admin without manage_admins cannot reach staff management', (tester) async {
    await pumpPanel(tester, access('SUPER_ADMIN', ['role_panel', 'grant_level']));
    expect(find.text('👥 الإداريون'), findsNothing);
    expect(find.text('🛡️ تعيين Admin'), findsNothing);
    expect(find.text('⭐ منح Level'), findsOneWidget);
  });
}

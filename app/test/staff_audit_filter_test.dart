import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/providers/staff_provider.dart';
import 'package:samafox/screens/staff/staff_audit_screen.dart';
import 'package:samafox/services/staff_service.dart';

/// Records what the audit screen asks the server for.
class _FakeStaffService extends StaffService {
  _FakeStaffService() : super(dio: Dio());
  final calls = <String?>[];
  @override
  Future<StaffAuditPage> audit({int page = 1, int? actorId, String? action}) async {
    calls.add(action);
    final body = jsonDecode(File('test/fixtures/staff/audit.json').readAsStringSync()) as Map;
    return StaffAuditPage.fromJson(staffJson(body['data']));
  }
}

void main() {
  testWidgets('choosing an action in سجل العمليات filters the request', (tester) async {
    final service = _FakeStaffService();
    final me = StaffAccess.fromJson(staffJson(
        (jsonDecode(File('test/fixtures/staff/me.json').readAsStringSync()) as Map)['data']));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        staffServiceProvider.overrideWithValue(service),
        staffMeProvider.overrideWith((ref) async => me),
      ],
      child: const MaterialApp(home: StaffAuditScreen()),
    ));
    await tester.pumpAndSettle();
    expect(service.calls, [null]);

    await tester.tap(find.text('كل العمليات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تمديد').last);
    await tester.pumpAndSettle();

    expect(service.calls.last, 'STAFF_EXTEND');
  });
}

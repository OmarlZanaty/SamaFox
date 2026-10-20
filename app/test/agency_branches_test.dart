import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/screens/agency_branches_screen.dart';
import 'package:samafox/services/agency_branch_service.dart';

Map<String, dynamic> branch({String status = 'ACTIVE'}) => {
      'id': 7,
      'parentAgencyId': 3,
      'ownerUserId': 42,
      'name': 'فرع القاهرة',
      'status': status,
      'createdAt': '2026-10-20T12:00:00Z',
      'owner': {'id': 42, 'displayId': 900042, 'name': 'مالك الفرع'},
    };

Map<String, dynamic> transfer(int id) => {
      'id': id,
      'parentAgencyId': 3,
      'branchId': 7,
      'branch': {'id': 7, 'name': 'فرع القاهرة'},
      'actorUserId': 42,
      'toUser': {'id': 81, 'name': 'المستلم'},
      'amount': 500,
      'coins': 500,
      'transactionId': 1000 + id,
      'createdAt': '2026-10-20T12:00:00Z',
    };

class FakeBranches extends AgencyBranchService {
  FakeBranches() : super(dio: Dio());
  List<Map<String, dynamic>> rows = [branch()];
  List<Map<String, dynamic>> ledger = [transfer(100)];
  final reads = <(int?, int?)>[];
  final mutations = <Map<String, dynamic>>[];
  Object? failure;
  Completer<List<Map<String, dynamic>>>? pending;

  @override
  Future<List<Map<String, dynamic>>> branches(int agencyId) async {
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return rows;
  }

  @override
  Future<Map<String, dynamic>> resolveOwner(
    String value, {
    required bool internalId,
  }) async {
    return {'id': 42, 'displayId': 900042, 'name': 'مالك الفرع'};
  }

  @override
  Future<void> create(int agencyId, String name, int ownerUserId) async {
    mutations
        .add({'agencyId': agencyId, 'name': name, 'ownerUserId': ownerUserId});
    rows = [branch()..['name'] = name];
  }

  @override
  Future<void> update(
    int agencyId,
    int branchId, {
    String? name,
    String? status,
  }) async {
    mutations.add({
      'agencyId': agencyId,
      'branchId': branchId,
      'name': name,
      'status': status,
    });
    rows = [
      branch(status: status ?? 'ACTIVE')..['name'] = name ?? 'فرع القاهرة',
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> transfers(
    int agencyId, {
    int? branchId,
    int? beforeId,
  }) async {
    reads.add((branchId, beforeId));
    if (failure != null) throw failure!;
    return beforeId == null ? ledger : [transfer(beforeId - 1)];
  }
}

Future<void> pumpBranches(
  WidgetTester tester,
  FakeBranches service, {
  bool owner = true,
  Size size = const Size(360, 640),
  bool dark = true,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: AgencyBranchesScreen(
        agencyId: 3,
        agencyName: 'وكالة سما',
        isOwner: owner,
        service: service,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  test('branch API uses exact agency, branch, cursor and mutation contracts',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          handler.resolve(
            Response(
              requestOptions: request,
              data: {'success': true, 'data': <dynamic>[]},
            ),
          );
        },
      ),
    );
    final service = AgencyBranchService(dio: dio);
    await service.branches(3);
    await service.transfers(3, branchId: 7, beforeId: 99);
    await service.transfers(3);
    await service.create(3, ' فرع جديد ', 42);
    await service.update(3, 7, name: ' اسم جديد ', status: 'SUSPENDED');
    expect(requests.map((r) => r.path), [
      '/agencies/3/branches',
      '/agencies/3/branches/7/transfers',
      '/agencies/3/transfers',
      '/agencies/3/branches',
      '/agencies/3/branches/7',
    ]);
    expect(requests[1].queryParameters, {'beforeId': 99});
    expect(requests[3].method, 'POST');
    expect(requests[3].data, {'name': 'فرع جديد', 'ownerUserId': 42});
    expect(requests[4].method, 'PATCH');
    expect(requests[4].data, {'name': 'اسم جديد', 'status': 'SUSPENDED'});
  });

  test('display ID lookup ignores name matches; internal ID is explicit',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          handler.resolve(
            Response(
              requestOptions: request,
              data: request.path.startsWith('/users/')
                  ? {
                      'success': true,
                      'user': {'id': 42, 'displayId': 900042, 'name': 'المالك'},
                    }
                  : {
                      'success': true,
                      'data': [
                        {'id': 91, 'name': '900042', 'displayId': 123},
                        {'id': 42, 'name': 'المالك', 'displayId': 900042},
                      ],
                    },
            ),
          );
        },
      ),
    );
    final service = AgencyBranchService(dio: dio);
    expect((await service.resolveOwner('900042', internalId: false))['id'], 42);
    await expectLater(
      service.resolveOwner('91', internalId: false),
      throwsA(isA<AgencyBranchException>()),
    );
    expect(
      (await service.resolveOwner('42', internalId: true))['displayId'],
      900042,
    );
    expect(requests.last.path, '/users/42');
    expect(requests.first.queryParameters['agencyType'], 'CHARGING');
  });

  test(
      'server Arabic messages are preserved, including success:false responses',
      () async {
    const message = 'لا تملك صلاحية الوصول إلى هذا الفرع';
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response(
              requestOptions: request,
              data: {'success': false, 'message': message},
            ),
          );
        },
      ),
    );
    await expectLater(
      AgencyBranchService(dio: dio).branches(3),
      throwsA(
        isA<AgencyBranchException>()
            .having((e) => e.message, 'message', message),
      ),
    );
    final request = RequestOptions(path: '/agencies/3/branches/8/transfers');
    expect(
      AgencyBranchService.errorMessage(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 403,
            data: {'message': message},
          ),
        ),
      ),
      message,
    );
  });

  for (final size in [
    const Size(360, 640),
    const Size(393, 873),
    const Size(412, 915),
  ]) {
    testWidgets('owner and transfer layout at $size', (tester) async {
      final service = FakeBranches();
      await pumpBranches(tester, service, size: size, dark: size.width != 393);
      expect(find.text('رقم الفرع: 7'), findsOneWidget);
      expect(find.text('المالك: مالك الفرع'), findsOneWidget);
      expect(find.text('رقم المستخدم: 900042'), findsOneWidget);
      expect(find.text('الحالة: نشط'), findsOneWidget);
      expect(find.text('إنشاء فرع'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('عمليات الشحن'));
      await tester.pumpAndSettle();
      expect(service.reads, [(7, null)]);
      expect(find.text('الفرع: فرع القاهرة (#7)'), findsOneWidget);
      expect(find.text('المستخدم: المستلم (#81)'), findsOneWidget);
      expect(find.text('المبلغ: 500 كوينز'), findsOneWidget);
      expect(find.text('رقم المعاملة: 1100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'branch owner sees suspended branch without management or combined ledger',
      (tester) async {
    final service = FakeBranches()..rows = [branch(status: 'SUSPENDED')];
    await pumpBranches(tester, service, owner: false);
    expect(find.text('الحالة: موقوف'), findsOneWidget);
    for (final text in [
      'إنشاء فرع',
      'كل عمليات الشحن',
      'تغيير الاسم',
      'تفعيل',
    ]) {
      expect(find.text(text), findsNothing);
    }
    await tester.tap(find.text('عمليات الشحن'));
    await tester.pumpAndSettle();
    expect(service.reads, [(7, null)]);
  });

  testWidgets('create verifies owner and submits resolved internal ID',
      (tester) async {
    final service = FakeBranches()..rows = [];
    await pumpBranches(tester, service);
    await tester.tap(find.text('إنشاء فرع'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'حفظ'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'فرع جديد');
    await tester.enterText(find.byType(TextFormField).at(1), '900042');
    await tester.tap(find.text('تحقق من المستخدم'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('حفظ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(
      service.mutations.single,
      {'agencyId': 3, 'name': 'فرع جديد', 'ownerUserId': 42},
    );
    expect(find.text('فرع جديد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename and suspend/activate wait for server confirmation',
      (tester) async {
    final service = FakeBranches();
    await pumpBranches(tester, service);
    await tester.tap(find.text('تغيير الاسم'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'اسم جديد');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(service.mutations.last['name'], 'اسم جديد');
    await tester.tap(find.text('إيقاف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('الحالة: موقوف'), findsOneWidget);
    expect(service.mutations.last['status'], 'SUSPENDED');
    await tester.tap(find.text('تفعيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(service.mutations.last['status'], 'ACTIVE');
  });

  testWidgets('loading, empty and server error with retry', (tester) async {
    final service = FakeBranches()..pending = Completer();
    await pumpBranches(tester, service, settle: false);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    service.pending!.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('لا توجد فروع حالياً'), findsOneWidget);
    service.failure = const AgencyBranchException('وكالة الشحن غير متاحة');
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('وكالة الشحن غير متاحة'), findsWidgets);
    service.failure = null;
    service.pending = null;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('رقم الفرع: 7'), findsOneWidget);
  });

  testWidgets(
      'pagination uses last transfer ID and clears ledger on denied access',
      (tester) async {
    final service = FakeBranches()
      ..ledger = List.generate(100, (i) => transfer(200 - i));
    await pumpBranches(tester, service, owner: false);
    await tester.tap(find.text('عمليات الشحن'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('تحميل المزيد'), 2000);
    await tester.tap(find.text('تحميل المزيد'));
    await tester.pumpAndSettle();
    expect(service.reads, [(7, null), (7, 101)]);
    expect(find.text('تحميل المزيد'), findsNothing);
    service.failure =
        const AgencyBranchException('لا تملك صلاحية الوصول إلى هذا الفرع');
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator).last);
    await refresh.onRefresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('رقم المعاملة:'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
      'owner ledger distinguishes main agency and unattributed legacy records',
      (tester) async {
    final service = FakeBranches()
      ..ledger = [
        transfer(2)..['branchId'] = null,
        transfer(1)
          ..['branchId'] = null
          ..['actorUserId'] = null
          ..['transactionId'] = null,
      ];
    await pumpBranches(tester, service);
    await tester.tap(find.text('كل عمليات الشحن'));
    await tester.pumpAndSettle();
    expect(service.reads, [(null, null)]);
    expect(find.text('الفرع: الوكالة الرئيسية'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('رقم المعاملة: غير مسجل'), 200);
    expect(find.text('الفرع: غير منسوب (سجل قديم)'), findsOneWidget);
    expect(find.text('رقم المعاملة: غير مسجل'), findsOneWidget);
  });
}

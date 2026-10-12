import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/models/user.dart';
import 'package:samafox/providers/auth_provider.dart';
import 'package:samafox/repositories/fruit_jackpot_repository.dart';
import 'package:samafox/screens/games/fruit_jackpot_engine.dart';
import 'package:samafox/screens/games/fruit_jackpot_screen.dart';
import 'fruit_jackpot_engine_test.dart' show fruitFixture;

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth()
    : super(AuthState(user: User(id: 701, name: 'Test', coinsBalance: 50000)));
  @override
  void updateCoinsBalance(int b) =>
      state = state.copyWith(user: state.user!.copyWith(coinsBalance: b));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo extends FruitJackpotRepository {
  int calls = 0, balance = 50000;
  Completer<FruitJackpotRound>? pending;
  bool fail = false;
  final keys = <String?>[];
  @override
  Future<Map<String, dynamic>> fetchState() async => {
    'balance': balance,
    'history': [],
    'roundCount': 0,
    'rank': null,
    'resetAt': '2026-10-08T21:00:00Z',
    'serverTime': '2026-10-07T12:00:00Z',
    'layout': {'minBet': 100, 'maxBet': 100000, 'enabled': true},
  };
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? data,
    String? requestId,
  }) async => {};
  @override
  Future<FruitJackpotRound> spin(
    int betPerLine,
    int activeLines, {
    String? requestId,
  }) async {
    calls++;
    keys.add(requestId);
    if (fail) {
      fail = false;
      throw const FruitJackpotException('NETWORK');
    }
    if (pending != null) return pending!.future;
    balance -= betPerLine;
    return FruitJackpotRound.fromJson(
      fruitFixture(number: calls, balance: balance),
    );
  }
}

Future<void> mount(
  WidgetTester t,
  _Repo repo, {
  bool arabic = true,
  bool motion = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'fruit_jackpot.701.sound': false,
    'fruit_jackpot.701.motion': motion,
    'fruit_jackpot.701.arabic': arabic,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((_) => _Auth())],
      child: MaterialApp(
        home: RepaintBoundary(
          key: const Key('capture'),
          child: FruitJackpotScreen(repository: repo),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final ar in [true, false]) {
    for (final width in [320.0, 360.0, 390.0, 768.0]) {
      testWidgets('layout ${ar ? 'RTL' : 'LTR'} $width', (t) async {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await mount(t, _Repo(), arabic: ar);
        final direction = find
            .descendant(
              of: find.byType(FruitJackpotScreen),
              matching: find.byType(Directionality),
            )
            .first;
        expect(
          t.widget<Directionality>(direction).textDirection,
          ar ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(t.takeException(), isNull);
        if (width == 390 && ar) {
          await t.runAsync(() async {
            final boundary = t.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('capture')),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('build').create(recursive: true);
            await File(
              'build/fruit-jackpot-screen.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'single debit and no second spin while request pending; STOP keeps result',
    (t) async {
      final repo = _Repo()..pending = Completer<FruitJackpotRound>();
      await mount(t, repo, arabic: false);
      final spin = find.byKey(const Key('fruit-spin'));
      await t.ensureVisible(spin);
      await t.tap(spin);
      await t.pump();
      await t.tap(spin);
      await t.pump();
      expect(repo.calls, 1);
      await t.tap(find.byKey(const Key('fruit-stop')));
      repo.pending!.complete(FruitJackpotRound.fromJson(fruitFixture()));
      await t.pumpAndSettle();
      expect(find.text('Balance: 49900 🪙'), findsOneWidget);
      expect(repo.calls, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('ambiguous network retry retains idempotency key', (t) async {
    final repo = _Repo()..fail = true;
    await mount(t, repo, arabic: false);
    final spin = find.byKey(const Key('fruit-spin'));
    await t.ensureVisible(spin);
    await t.tap(spin);
    await t.pumpAndSettle();
    await t.tap(spin);
    await t.pumpAndSettle();
    expect(repo.keys.length, 2);
    expect(repo.keys[0], repo.keys[1]);
    expect(repo.balance, 49900);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('insufficient balance blocks spin', (t) async {
    final repo = _Repo()..balance = 50;
    await mount(t, repo, arabic: false);
    await t.ensureVisible(find.byKey(const Key('fruit-spin')));
    await t.tap(find.byKey(const Key('fruit-spin')));
    await t.pumpAndSettle();
    expect(repo.calls, 0);
    expect(find.text('Insufficient balance'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

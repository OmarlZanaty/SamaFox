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
import 'package:samafox/repositories/yummy_repository.dart';
import 'package:samafox/screens/games/yummy_engine.dart';
import 'package:samafox/screens/games/yummy_screen.dart';
import 'package:samafox/screens/games/yummy_symbols.dart';
import 'package:samafox/screens/games/yummy_grid.dart';
import 'yummy_engine_test.dart' show yummyFixture;
import 'yummy_v2_test.dart' show v2Fixture;

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth()
      : super(
          AuthState(user: User(id: 701, name: 'Test', coinsBalance: 50000)),
        );
  @override
  void updateCoinsBalance(int newBalance) => state =
      state.copyWith(user: state.user!.copyWith(coinsBalance: newBalance));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository extends YummyRepository {
  int calls = 0, balance = 50000;
  bool bonus = false;

  /// Rounds (1-based) that trigger free spins.
  Set<int> bonusOn = {};
  int prize = 0;
  Completer<YummyRound>? pending;
  @override
  Future<Map<String, dynamic>> fetchState() async => {
        'balance': balance,
        'history': [],
        'layout': {
          'betSteps': [10, 20, 50, 100, 200, 500, 1000],
          'minBet': 10,
          'maxBet': 9000,
          'enabled': true,
          'paytable': yummyPaytable,
        },
      };
  @override
  Future<List<Map<String, dynamic>>> feed() async => [];
  @override
  Future<Map<String, dynamic>> leaderboard() async => {
        'weekStart': '2026-10-03',
        'entries': [
          {
            'rank': 1,
            'userId': 9,
            'name': 'Karim',
            'avatar': null,
            'won': 410000,
          },
          {
            'rank': 2,
            'userId': 701,
            'name': 'Test',
            'avatar': null,
            'won': 1200,
          },
        ],
        'me': {'rank': 2, 'won': 1200},
      };
  @override
  Future<Map<String, dynamic>> missions() async => {
        'day': '2026-10-07',
        'missions': [
          {
            'key': 'spin20',
            'target': 20,
            'xp': 50,
            'progress': 20,
            'claimed': false,
          },
          {
            'key': 'win5',
            'target': 5,
            'xp': 60,
            'progress': 1,
            'claimed': false,
          },
        ],
      };
  @override
  Future<YummyRound> spin(
    int betPerLine,
    int activeLines, {
    String? requestId,
  }) async {
    calls++;
    if (pending != null) return pending!.future;
    balance -= betPerLine * activeLines;
    final fixture = yummyFixture(nonce: calls, prize: 0, balance: balance);
    final spin = fixture['spin'] as Map;
    spin['grid'] = List.generate(15, (index) => yummySymbolIds[index % 8]);
    spin['wins'] = [];
    spin['betPerLine'] = betPerLine;
    spin['activeLines'] = activeLines;
    spin['totalBet'] = betPerLine * activeLines;
    if (bonus || bonusOn.contains(calls)) {
      final v2 = v2Fixture();
      final v2spin = v2['spin'] as Map;
      v2spin['betPerLine'] = betPerLine;
      v2spin['activeLines'] = activeLines;
      v2spin['totalBet'] = betPerLine * activeLines;
      balance += v2spin['totalPrize'] as int;
      v2['balance'] = balance;
      v2['nonce'] = calls;
      v2['id'] = 'round-$calls';
      return YummyRound.fromJson(v2);
    }
    if (prize > 0) {
      balance += prize;
      fixture['balance'] = balance;
      spin['totalPrize'] = prize;
      spin['requestedPrize'] = prize;
    }
    return YummyRound.fromJson(fixture);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Repository repository, {
  bool arabic = true,
  bool motion = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'yummy.701.sound': false,
    'yummy.701.motion': motion,
    'yummy.701.arabic': arabic,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => _Auth())],
      child: MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: YummyScreen(repository: repository),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('12 renders RTL and LTR and persists the language toggle',
      (tester) async {
    final repository = _Repository();
    await _mount(tester, repository);
    final direction = find
        .descendant(
          of: find.byType(YummyScreen),
          matching: find.byType(Directionality),
        )
        .first;
    expect(
      tester.widget<Directionality>(direction).textDirection,
      TextDirection.rtl,
    );
    await tester.tap(find.byTooltip('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool('yummy.701.arabic'),
      isFalse,
    );
    await tester.tap(find.byTooltip('إغلاق'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Directionality>(direction).textDirection,
      TextDirection.ltr,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final arabic in [true, false]) {
    for (final width in [360.0, 390.0, 768.0, 1440.0]) {
      testWidgets('RTL/LTR layout ${arabic ? 'AR' : 'EN'} at $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _mount(tester, _Repository(), arabic: arabic);
        final screenDirection = find
            .descendant(
              of: find.byType(YummyScreen),
              matching: find.byType(Directionality),
            )
            .first;
        expect(
          tester.widget<Directionality>(screenDirection).textDirection,
          arabic ? TextDirection.rtl : TextDirection.ltr,
        );
        final semantics = tester.ensureSemantics();
        expect(find.byType(YummyMachine), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            RegExp(
              '^(Strawberry|Cherry|Orange|Lemon|Watermelon|Grapes|Candy|Diamond|'
              'فراولة|كرز|برتقال|ليمون|بطيخ|عنب|حلوى|ماس)\$',
            ),
          ),
          findsWidgets,
        );
        semantics.dispose();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('twenty spins update shared balance; maximum bet never spins',
      (tester) async {
    final repository = _Repository();
    await _mount(tester, repository, arabic: false);
    for (var index = 0; index < 20; index++) {
      await tester.ensureVisible(find.text('SPIN'));
      await tester.tap(find.text('SPIN'));
      await tester.pumpAndSettle();
    }
    expect(repository.calls, 20);
    expect(find.text('32000'), findsOneWidget);
    await tester.tap(find.text('MAXIMUM BET'));
    await tester.pumpAndSettle();
    expect(repository.calls, 20);
    expect(find.text('9000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'STOP before server response preserves result and prevents another request',
      (tester) async {
    final repository = _Repository()..pending = Completer<YummyRound>();
    await _mount(tester, repository, arabic: false, motion: true);
    await tester.ensureVisible(find.text('SPIN'));
    await tester.tap(find.text('SPIN'));
    await tester.pump();
    await tester.tap(find.text('STOP'));
    await tester.pump();
    expect(repository.calls, 1);
    repository.pending!
        .complete(YummyRound.fromJson(yummyFixture(prize: 0, balance: 49100)));
    await tester.pumpAndSettle();
    expect(find.text('49100'), findsOneWidget);
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('help, history, statistics, settings and bonus open and close',
      (tester) async {
    final repository = _Repository();
    await _mount(tester, repository, arabic: false);
    for (final tooltip in [
      'Help & paytable',
      'History',
      'Statistics',
      'Settings',
    ]) {
      await tester.ensureVisible(find.byTooltip(tooltip));
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }
    for (final tooltip in ['Weekly leaderboard', 'Daily missions']) {
      await tester.ensureVisible(find.byTooltip(tooltip));
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('free spins: intro, eight auto-played spins, summary, balance',
      (tester) async {
    final repository = _Repository()..bonus = true;
    await _mount(tester, repository, arabic: false);
    await tester.ensureVisible(find.text('SPIN'));
    await tester.tap(find.text('SPIN'));
    await tester.pumpAndSettle();
    // Intro waits for START (or its own timer).
    expect(find.text('FREE SPINS'), findsWidgets);
    expect(find.text('×2'), findsWidgets);
    expect(find.text('8'), findsWidgets);
    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();
    // All eight spins replayed; the summary shows what they paid.
    expect(find.text('FREE SPINS WIN'), findsWidgets);
    expect(find.text('4800'), findsWidgets);
    expect(repository.calls, 1);
    await tester.tap(find.text('Tap to continue'));
    await tester.pumpAndSettle();
    expect(find.text('FREE SPINS WIN'), findsNothing);
    // 50000 − 900 + 5400.
    expect(find.text('54500'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('free spins intro starts by itself', (tester) async {
    final repository = _Repository()..bonus = true;
    await _mount(tester, repository, arabic: false);
    await tester.ensureVisible(find.text('SPIN'));
    await tester.tap(find.text('SPIN'));
    await tester.pumpAndSettle();
    expect(find.text('START'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('FREE SPINS WIN'), findsWidgets);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('FREE SPINS WIN'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> runAutoplay(
    WidgetTester tester,
    _Repository repository, {
    String? spins,
    String? lossLimit,
  }) async {
    await tester.ensureVisible(find.text('AUTO'));
    await tester.tap(find.text('AUTO'));
    await tester.pumpAndSettle();
    if (spins != null) await tester.tap(find.text(spins).last);
    if (lossLimit != null) await tester.tap(find.text(lossLimit).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start autoplay'));
    for (var i = 0;
        i < 400 && find.text('Autoplay stopped').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('autoplay plays the chosen count, then stops', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository, arabic: false);
    await runAutoplay(tester, repository, spins: '10');
    expect(repository.calls, 10);
    expect(find.text('Autoplay stopped'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('autoplay stops at the loss limit', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository, arabic: false);
    // 10 × 900 total bet: stops once 9000 is lost.
    await runAutoplay(tester, repository, spins: '50', lossLimit: '9000');
    expect(repository.calls, 10);
    expect(find.text('Autoplay stopped'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('autoplay stops when free spins start', (tester) async {
    final repository = _Repository()..bonusOn = {3};
    await _mount(tester, repository, arabic: false);
    await tester.ensureVisible(find.text('AUTO'));
    await tester.tap(find.text('AUTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start autoplay'));
    for (var i = 0;
        i < 400 && find.text('Autoplay stopped').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 500));
      // Let the free spins play out on their own timers.
    }
    await tester.pumpAndSettle();
    expect(repository.calls, 3);
    expect(find.text('Autoplay stopped'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('STOP during autoplay ends it after the current round',
      (tester) async {
    final repository = _Repository()..pending = Completer<YummyRound>();
    await _mount(tester, repository, arabic: false);
    await tester.ensureVisible(find.text('AUTO'));
    await tester.tap(find.text('AUTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start autoplay'));
    await tester.pump();
    expect(find.textContaining('STOP'), findsOneWidget);
    await tester.tap(find.textContaining('STOP'));
    await tester.pump();
    repository.pending!
        .complete(YummyRound.fromJson(yummyFixture(prize: 0, balance: 49100)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.calls, 1);
    expect(find.text('SPIN'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('capture the 390px screen for visual review', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _Repository());
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    // Image encoding runs on real async, which fake-async test time never
    // advances; doing it outside runAsync hangs until the 10-minute timeout.
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build').create(recursive: true);
      await File('build/yummy-screen.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  });
}

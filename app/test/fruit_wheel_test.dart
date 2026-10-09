import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/models/user.dart';
import 'package:samafox/providers/auth_provider.dart';
import 'package:samafox/repositories/fruit_wheel_repository.dart';
import 'package:samafox/screens/games/fruit_wheel_engine.dart';
import 'package:samafox/screens/games/fruit_wheel_screen.dart';
import 'package:samafox/screens/games/fruit_wheel_sheets.dart';

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(int coins)
      : super(AuthState(user: User(id: 701, name: 'Test', coinsBalance: coins)));
  @override
  void updateCoinsBalance(int newBalance) => state =
      state.copyWith(user: state.user!.copyWith(coinsBalance: newBalance));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Plays [outcomes] in order; every spin is answered like the server would.
class _Repository extends FruitWheelRepository {
  int balance, calls = 0, round = 7;
  List<String> outcomes;
  final List<FruitBets> received = [];
  Completer<void>? gate;
  _Repository({this.balance = 50000, this.outcomes = const ['watermelon']});

  @override
  Future<Map<String, dynamic>> fetchState() async => {
        'balance': balance,
        'history': [],
        'rounds': round,
        'today': {
          'totals': {'watermelon': 62000, 'sevens': 54000, 'plum': 21000},
        },
        'layout': {'minBet': 100, 'maxBet': 300000, 'mathRtp': .694},
      };
  @override
  Future<Map<String, dynamic>> leaderboard() async =>
      {'entries': [], 'me': {'rank': 22, 'won': 0}};
  @override
  Future<Map<String, dynamic>> fairness() async =>
      {'fairness': {'serverSeedHash': 'ab', 'clientSeed': 'c', 'nonce': 1}};

  @override
  Future<FruitRound> spin(FruitBets bets, {String? requestId}) async {
    calls++;
    received.add(bets.copy());
    if (gate != null) await gate!.future;
    final outcome = outcomes[(calls - 1) % outcomes.length];
    final segment = fruitSegments.indexOf(outcome);
    var prize = 0, bonusPrize = 0;
    if (outcome == 'bonus') {
      bonusPrize = (bets.total * .1 * 5).floor();
      prize = bonusPrize;
    } else {
      prize = bets[outcome] * fruitMultipliers[outcome]!;
    }
    balance += prize - bets.total;
    round++;
    return FruitRound.fromJson({
      'id': 'r$round',
      'at': DateTime.now().toIso8601String(),
      'round': round,
      'balance': balance,
      'spin': {
        'bets': bets.json,
        'totalBet': bets.total,
        'outcome': outcome,
        'segment': segment,
        'offset': .5,
        'winner': outcome == 'bonus' ? null : outcome,
        'cardPrize': prize - bonusPrize,
        'orbs': outcome == 'bonus' ? [5, 2, 3] : null,
        'bonusPrize': bonusPrize,
        'totalPrize': prize,
      },
    });
  }
}

Future<FruitWheelScreenState> _mount(
  WidgetTester tester,
  _Repository repository, {
  int coins = 50000,
  Map<String, Object> prefs = const {},
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'fruitwheel.701.sound': false,
    'fruitwheel.701.motion': false,
    ...prefs,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => _Auth(coins))],
      child: MaterialApp(home: FruitWheelScreen(repository: repository)),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // With motion on the rim bulbs never stop, so time is stepped instead.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return tester.state<FruitWheelScreenState>(find.byType(FruitWheelScreen));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

int _coins(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(FruitWheelScreen)),
    ).read(authStateProvider).user!.coinsBalance ?? 0;

void main() {
  group('engine', () {
    test('the stop angle puts the chosen point under the pointer', () {
      for (var segment = 0; segment < fruitSegments.length; segment++) {
        for (final offset in [.15, .5, .85]) {
          final angle = fruitStopAngle(1.234, segment, offset, 6);
          expect(fruitSegmentAt(angle), segment);
          expect(angle - 1.234, greaterThanOrEqualTo(6 * 2 * pi));
          expect(angle - 1.234, lessThan(7 * 2 * pi));
        }
      }
    });
    test('spin plans stay within 5–8 turns and 3–4.5 s', () {
      final random = Random(3);
      for (var i = 0; i < 200; i++) {
        final plan = fruitSpinPlan(random);
        expect(plan.turns, inInclusiveRange(5, 8));
        expect(plan.ms, inInclusiveRange(3000, 4500));
      }
    });
    test('bets respect the table maximum', () {
      final bets = FruitBets();
      expect(bets.add('watermelon', 1000, 1500), isTrue);
      expect(bets.add('plum', 1000, 1500), isFalse);
      expect(bets.add('banana', 100, 1500), isFalse);
      expect(bets.total, 1000);
      bets.clear();
      expect(bets.isEmpty, isTrue);
      expect(FruitBets.fromJson({'plum': 'x'}), isNull);
    });
    test('the ticker keeps the newest 12 outcomes', () {
      var ticker = <String>[];
      for (var i = 0; i < 20; i++) {
        ticker = fruitPushTicker(ticker, i.isEven ? 'plum' : 'watermelon');
      }
      expect(ticker.length, 12);
      expect(ticker.first, 'watermelon');
    });
    test('compact numbers', () {
      expect(fruitCompact(950), '950');
      expect(fruitCompact(62000), '62K');
      expect(fruitCompact(1500000), '1.5M');
    });
    test('a corrupt round still parses to safe defaults', () {
      final round = FruitRound.fromJson({'spin': 'nope'});
      expect(round.totalPrize, 0);
      expect(round.bets.isEmpty, isTrue);
    });
  });

  testWidgets('a winning round debits once, pays the card and advances the round',
      (tester) async {
    final repository = _Repository();
    final screen = await _mount(tester, repository);
    expect(find.text('62K'), findsOneWidget);
    expect(find.text('x3'), findsOneWidget);
    expect(find.text('الجولة: 8'), findsOneWidget);
    screen.placeChip('watermelon');
    screen.placeChip('plum');
    await tester.pump();
    expect(screen.bets.total, 200);
    unawaited(screen.spin());
    unawaited(screen.spin()); // a second press while spinning does nothing
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(repository.received.single.json, {'watermelon': 100, 'sevens': 0, 'plum': 100});
    expect(_coins(tester), 50000 - 200 + 200);
    expect(find.text('+200'), findsOneWidget);
    expect(find.text('الجولة: 9'), findsOneWidget);
    expect(screen.phase, FruitPhase.idle);
    await _unmount(tester);
  });

  testWidgets('REPEAT replays the last chips; insufficient coins never call the server',
      (tester) async {
    final repository = _Repository(balance: 1000, outcomes: ['plum']);
    final screen = await _mount(tester, repository, coins: 1000);
    for (var i = 0; i < 3; i++) {
      screen.placeChip('sevens');
    }
    unawaited(screen.spin());
    await tester.pumpAndSettle();
    expect(find.text('كرر'), findsOneWidget);
    await tester.tap(find.text('كرر'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(repository.received.last['sevens'], 300);
    // 1000 − 300 − 300 = 400 left; a third repeat fits, a fourth does not.
    unawaited(screen.spin());
    await tester.pumpAndSettle();
    unawaited(screen.spin());
    await tester.pumpAndSettle();
    expect(repository.calls, 3);
    expect(find.text('رصيدك لا يكفي لهذا الرهان.'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('BONUS opens the orb pick and pays the decided value', (tester) async {
    final repository = _Repository(outcomes: ['bonus']);
    final screen = await _mount(tester, repository);
    screen.placeChip('watermelon');
    unawaited(screen.spin());
    await tester.pumpAndSettle();
    expect(find.byType(FruitBonusDialog), findsOneWidget);
    expect(screen.phase, FruitPhase.bonus);
    await tester.tap(find.bySemanticsLabel('اختر كرة 3'));
    await tester.pumpAndSettle();
    expect(find.text('×5'), findsOneWidget);
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();
    expect(find.byType(FruitBonusDialog), findsNothing);
    expect(_coins(tester), 50000 - 100 + 50);
    await _unmount(tester);
  });

  testWidgets('skipping the animation never changes the result', (tester) async {
    final repository = _Repository(outcomes: ['sevens']);
    final screen = await _mount(
      tester,
      repository,
      prefs: {'fruitwheel.701.motion': true},
      settle: false,
    );
    screen.placeChip('sevens');
    unawaited(screen.spin());
    await tester.pump(const Duration(milliseconds: 300));
    expect(screen.phase, FruitPhase.spinning);
    screen.skip();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(screen.phase, FruitPhase.idle);
    expect(find.text('+300'), findsOneWidget);
    expect(repository.calls, 1);
    await _unmount(tester);
  });

  testWidgets('language switches direction and settings persist', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository);
    Directionality direction() => tester.widget<Directionality>(
          find
              .descendant(
                of: find.byType(FruitWheelScreen),
                matching: find.byType(Directionality),
              )
              .first,
        );
    expect(direction().textDirection, TextDirection.rtl);
    await tester.tap(find.byTooltip('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(direction().textDirection, TextDirection.ltr);
    expect(find.text('FRUIT WHEEL'), findsOneWidget);
    await tester.tap(find.byTooltip('Sound on'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('fruitwheel.701.arabic'), isFalse);
    expect(prefs.getBool('fruitwheel.701.sound'), isTrue);
    await _unmount(tester);
  });

  testWidgets('fits a 320 px phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'fruitwheel.701.sound': false,
      'fruitwheel.701.motion': false,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => _Auth(50000))],
        child: MaterialApp(home: FruitWheelScreen(repository: _Repository())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('x2'), findsNWidgets(2));
    await _unmount(tester);
  });
}

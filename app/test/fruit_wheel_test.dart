import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/models/user.dart';
import 'package:samafox/providers/auth_provider.dart';
import 'package:samafox/repositories/fruit_wheel_repository.dart';
import 'package:samafox/screens/games/fruit_wheel_art.dart';
import 'package:samafox/screens/games/fruit_wheel_engine.dart';
import 'package:samafox/screens/games/fruit_wheel_screen.dart';
import 'package:samafox/screens/games/fruit_wheel_sheets.dart';
import 'package:samafox/screens/games/fruit_wheel_strings.dart';

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth()
      : super(
          AuthState(user: User(id: 701, name: 'Test', coinsBalance: 50000)),
        );
  @override
  void updateCoinsBalance(int n) =>
      state = state.copyWith(user: state.user!.copyWith(coinsBalance: n));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Repository extends FruitWheelRepository {
  int balance = 50000, calls = 0, repeats = 0;
  final Map<String, int> stakes = {};
  final List<String> chips = [];
  Map<String, dynamic> multipliers = Map.of(fruitMultipliers);
  Completer<void>? gate;
  Map<String, dynamic> snapshot = {
    'round': 7,
    'phase': 'betting',
    'msLeft': 30000,
    'history': [],
  };
  Map<String, dynamic> get reply => {
        'round': snapshot['round'],
        'balance': balance,
        'stakes': Map.of(stakes),
      };
  @override
  Future<Map<String, dynamic>> fetchState() async => {
        'balance': balance,
        'layout': {'maxPerKey': 1000, 'multipliers': multipliers},
        'state': {
          ...snapshot,
          'me': {
            'stakes': Map.of(stakes),
            'staked': stakes.values.fold(0, (a, b) => a + b),
            'payout': 0,
          },
        },
      };
  @override
  Future<Map<String, dynamic>> bet(String key, int amount) async {
    calls++;
    if (gate != null) await gate!.future;
    balance -= amount;
    stakes[key] = (stakes[key] ?? 0) + amount;
    chips.add(key);
    return reply;
  }

  @override
  Future<Map<String, dynamic>> undo() async {
    if (chips.isNotEmpty) {
      final key = chips.removeLast();
      stakes[key] = stakes[key]! - 100;
      balance += 100;
    }
    return reply;
  }

  @override
  Future<Map<String, dynamic>> clear() async {
    balance += stakes.values.fold(0, (a, b) => a + b);
    stakes.clear();
    chips.clear();
    return reply;
  }

  @override
  Future<Map<String, dynamic>> repeat() async {
    repeats++;
    return reply;
  }

  @override
  Future<Map<String, dynamic>> ranking() async => {
        'entries': [],
        'me': {'net': 0},
      };
  @override
  Future<List<Map<String, dynamic>>> history() async => [];
}

Future<FruitWheelScreenState> _mount(
  WidgetTester t,
  _Repository repo, {
  Size size = const Size(390, 844),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(
    {'fruitwheel.701.sound': false, 'fruitwheel.701.motion': false},
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((_) => _Auth())],
      child: MaterialApp(home: FruitWheelScreen(repository: repo, live: false)),
    ),
  );
  await t.pumpAndSettle();
  return t.state<FruitWheelScreenState>(find.byType(FruitWheelScreen));
}

void main() {
  test('per-card cap and two distinct cards, 77 pays ×5.6, no crown', () {
    final bets = FruitBets();
    expect(bets.add('watermelon', 1000, 1000), true);
    expect(bets.add('sevens', 1000, 1000), true);
    expect(bets.total, 2000);
    expect(bets.add('plum', 100, 1000), false);
    expect(bets.add('watermelon', 100, 1000), false);
    expect(bets.add('crown', 100, 1000), false);
    expect(fruitMultipliers, {'watermelon': 1.6, 'sevens': 5.6, 'plum': 1.6});
    expect(fruitSegments, [
      'watermelon', 'plum', 'watermelon', 'plum', 'sevens',
      'watermelon', 'plum', 'watermelon', 'plum',
    ]);
    expect(fruitSegments, isNot(contains('crown')));
    expect(fruitSegments.length, 9);
    expect(fruitTickerLength, 10);
  });
  test('server segment and offset land under pointer across all nine wedges',
      () {
    for (var segment = 0; segment < fruitSegments.length; segment++) {
      for (final offset in [.15, .5, .85]) {
        final end = fruitStopAngle(1.7 * pi, segment, offset, 5);
        expect(fruitSegmentAt(end), segment);
        expect(end, greaterThan(10 * pi));
      }
    }
  });
  test('shared state ignores old crown and clamps server geometry', () {
    final s = FruitWheelState.fromJson({
      'round': 3,
      'phase': 'result',
      'result': 'crown',
      'segment': 9,
      'offset': .23,
      'history': ['watermelon', 'bonus', 'crown'],
      'me': {
        'stakes': {'sevens': 100},
        'staked': 100,
        'payout': 0,
      },
    });
    expect(s.result, isNull);
    expect(s.segment, 8);
    expect(s.offset, .23);
    expect(s.history, ['watermelon']);
    expect(s.myStaked, 100);
    expect(s.betting, false);
    expect(FruitWheelState.fromJson({'segment': -1}).segment, 0);
    expect(FruitWheelState.fromJson({'result': 'bonus'}).result, isNull);
    expect(fruitPushTicker(['plum', 'crown', 'bonus'], 'crown'), ['plum']);
  });
  test('adjacent wheel colors differ including the wraparound seam', () {
    for (var i = 0; i < fruitSegments.length; i++) {
      expect(fruitSegmentColor(i),
          isNot(fruitSegmentColor((i + 1) % fruitSegments.length)));
    }
  });
  test('multipliers use valid config values and format without trailing .0', () {
    expect(fruitTableMultipliers(null), fruitMultipliers);
    expect(fruitTableMultipliers({
      'watermelon': 2, 'sevens': 6.5, 'plum': 'invalid', 'crown': 10,
    }), {'watermelon': 2.0, 'sevens': 6.5, 'plum': 1.6});
    expect(fruitTableMultipliers({
      'watermelon': -1, 'sevens': double.nan, 'plum': 0,
    }), fruitMultipliers);
    expect(fruitMultiplierLabel(1.6), '×1.6');
    expect(fruitMultiplierLabel(5.6), '×5.6');
    expect(fruitMultiplierLabel(2.0), '×2');
  });
  testWidgets('card labels prefer multipliers from the existing state config',
      (t) async {
    final repo = _Repository()
      ..multipliers = {'watermelon': 3, 'sevens': 6.5, 'plum': 1.6};
    await _mount(t, repo);
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('×6.5'), findsOneWidget);
    expect(find.text('×1.6'), findsOneWidget);
    expect(find.text('×3.0'), findsNothing);
    expect(t.widgetList<FruitArt>(find.byType(FruitArt))
        .where((art) => art.name == 'crown'), isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('history keeps old crown art and uses a neutral missing result',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: FruitHistory(
        strings: FruitWheelStrings(false),
        rounds: [
          {'round': 1, 'result': 'crown', 'bet': 100, 'prize': 0},
          {'round': 2, 'result': null, 'bet': 100, 'prize': 0},
        ],
      )),
    ));
    expect(t.widgetList<FruitArt>(find.byType(FruitArt))
        .map((art) => art.name), ['crown']);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'countdown replaces spin button and third card shows Arabic notice',
      (t) async {
    final repo = _Repository();
    final game = await _mount(t, repo);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('دوّر'), findsNothing);
    expect(find.text('كرر'), findsNothing);
    expect(find.text('×5.6'), findsOneWidget);
    expect(find.text('×1.6'), findsNWidgets(2));
    game.placeChip('watermelon');
    await t.pumpAndSettle();
    game.placeChip('sevens');
    await t.pumpAndSettle();
    game.placeChip('plum');
    await t.pump();
    expect(repo.calls, 2);
    expect(repo.balance, 49800);
    expect(find.text('تقدر تراهن على خيارين بس في الجولة'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'last five seconds warn, close rejects chips, shared spin is automatic',
      (t) async {
    final repo = _Repository();
    final game = await _mount(t, repo);
    game.applyState({'round': 7, 'phase': 'betting', 'msLeft': 5000});
    await t.pump();
    expect(find.text('الوقت قرب يخلص'), findsOneWidget);
    game.applyState({'round': 7, 'phase': 'closing', 'msLeft': 1000});
    game.placeChip('plum');
    expect(repo.calls, 0);
    game.applyState({
      'round': 7,
      'phase': 'spinning',
      'msLeft': 6000,
      'result': 'sevens',
      'segment': 4,
      'offset': .5,
    });
    await t.pump();
    expect(game.state!.phase, 'spinning');
    game.applyState(
      {
        'round': 7,
        'phase': 'result',
        'msLeft': 5000,
        'result': 'sevens',
        'segment': 4,
        'offset': .5,
        'winners': [
          {'name': 'Winner', 'staked': 100, 'payout': 560},
        ],
        'me': {'staked': 100, 'payout': 560},
      },
      mine: true,
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(FruitWinners), findsOneWidget);
    expect(find.text('حظاً سعيداً'), findsOneWidget);
    expect(find.text('Winner'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.byType(FruitWinners), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'public snapshots retain own stakes; next round clears and stale state is ignored',
      (t) async {
    final repo = _Repository();
    final game = await _mount(t, repo);
    game.placeChip('sevens');
    await t.pumpAndSettle();
    game.applyState(
      {'round': 7, 'phase': 'betting', 'msLeft': 10000, 'me': null},
    );
    expect(game.bets['sevens'], 100);
    game.applyState({'round': 8, 'phase': 'betting', 'msLeft': 30000});
    expect(game.bets.isEmpty, true);
    game.applyState({'round': 7, 'phase': 'result', 'result': 'plum'});
    expect(game.state!.round, 8);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'undo frees third-card slot; repeat places bets without starting a spin',
      (t) async {
    final repo = _Repository();
    final game = await _mount(t, repo);
    game.placeChip('watermelon');
    await t.pumpAndSettle();
    game.placeChip('sevens');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('تراجع'));
    await t.pumpAndSettle();
    game.placeChip('plum');
    await t.pumpAndSettle();
    expect(repo.calls, 3);
    await t.tap(find.byTooltip('إعادة الرهان'));
    await t.pumpAndSettle();
    expect(repo.repeats, 1);
    expect(game.state!.phase, 'betting');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('one-screen layout fits 360 × 640', (t) async {
    await _mount(t, _Repository(), size: const Size(360, 640));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  test('rules disclose fruit odds, multipliers, program share and every-spin card',
      () {
    for (final ar in [true, false]) {
      final s = FruitWheelStrings(ar);
      expect(s.text('odds'), contains('43.75%'));
      expect(s.text('odds'), contains('12.5%'));
      expect(s.text('odds'), contains('×1.6'));
      expect(s.text('odds'), contains('×5.6'));
      expect(s.text('odds'), contains('70%'));
      expect(s.text('odds'), isNot(contains('21.25%')));
      expect(s.text('odds'), isNot(contains(ar ? 'التاج' : 'Crown')));
      expect(s.text('rules'), contains(ar
          ? 'كل لفة تقف على بطاقة فواكه'
          : 'every spin lands on a fruit card'));
      expect(s.text('poolHelp'), contains('30%'));
      expect(s.text('sevens'), '77');
    }
  });
}

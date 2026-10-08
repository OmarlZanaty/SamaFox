import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/models/user.dart';
import 'package:samafox/providers/auth_provider.dart';
import 'package:samafox/repositories/car_wheel_repository.dart';
import 'package:samafox/screens/games/car_wheel_engine.dart';
import 'package:samafox/screens/games/car_wheel_screen.dart';
import 'package:samafox/screens/games/car_wheel_strings.dart';

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth()
      : super(
            AuthState(user: User(id: 701, name: 'Test', coinsBalance: 100000)),);
  @override
  void updateCoinsBalance(int newBalance) => state =
      state.copyWith(user: state.user!.copyWith(coinsBalance: newBalance));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the server: keeps this player's stakes and balance.
class _Repository extends CarWheelRepository {
  int balance = 100000;
  Map<String, int> stakes = {};
  final chips = <Map<String, dynamic>>[];
  final List<String> calls = [];
  Map<String, int> last = {};
  Map<String, dynamic> table(
          {String phase = 'betting', String? result, int payout = 0,}) =>
      {
        'round': 249,
        'phase': phase,
        'msLeft': 20000,
        'seedHash': 'ab' * 32,
        'result': result,
        'totals': {'aurelia': 383000, ...stakes},
        'totalBet': 2286400 + stakes.values.fold(0, (a, b) => a + b),
        'playerCount': 3,
        'players': [
          {'userId': 9, 'name': 'Karim', 'avatarUrl': null, 'staked': 5000},
        ],
        'history': ['aurelia', 'porsenna', 'voltara'],
        'me': {
          'stakes': stakes,
          'staked': stakes.values.fold(0, (a, b) => a + b),
          'payout': payout,
          'chipList': chips,
        },
      };
  Map<String, dynamic> _ok() => {
        'success': true,
        'stakes': stakes,
        'balance': balance,
        'chipList': chips,
      };

  @override
  Future<Map<String, dynamic>> fetchState() async =>
      {'state': table(), 'balance': balance, 'chipList': chips};
  @override
  Future<Map<String, dynamic>> bet(String key, int amount) async {
    calls.add('bet $key $amount');
    if (amount > balance) throw const CarWheelException('INSUFFICIENT_COINS');
    chips.add({'id': chips.length + 1, 'key': key, 'amount': amount});
    balance -= amount;
    stakes[key] = (stakes[key] ?? 0) + amount;
    return _ok();
  }

  @override
  Future<Map<String, dynamic>> clear() async {
    calls.add('clear');
    balance += stakes.values.fold(0, (a, b) => a + b);
    stakes = {};
    chips.clear();
    return _ok();
  }

  @override
  Future<Map<String, dynamic>> undo() async {
    calls.add('undo');
    final c = chips.removeLast();
    final key = c['key'] as String, amount = c['amount'] as int;
    stakes[key] = (stakes[key] ?? 0) - amount;
    balance += amount;
    return _ok();
  }

  @override
  Future<Map<String, dynamic>> repeat() async {
    calls.add('repeat');
    for (final e in last.entries) {
      await bet(e.key, e.value);
    }
    return _ok();
  }

  @override
  Future<List<Map<String, dynamic>>> history() async => [];
  @override
  Future<Map<String, dynamic>> ranking() async => {
        'entries': [],
        'me': {'net': 0, 'best': 0},
      };
}

Future<CarWheelScreenState> _mount(WidgetTester tester, _Repository repository,
    {Size size = const Size(390, 900),}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'carwheel.701.sound': false,
    'carwheel.701.motion': false,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => _Auth())],
      child: MaterialApp(
          home: CarWheelScreen(repository: repository, live: false),),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return tester.state<CarWheelScreenState>(find.byType(CarWheelScreen));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Routes start animating on the frame after they are pushed.
Future<void> _route(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

int _coins(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(CarWheelScreen)))
        .read(authStateProvider)
        .user!
        .coinsBalance ??
    0;

void main() {
  group('engine', () {
    test('table matches server order, weights and total-return payouts', () {
      expect(carWheelSegments.map((s) => s.key), [
        'aurelia',
        'bavaro',
        'stellaro',
        'ferrarion',
        'lambrex',
        'voltara',
        'porsenna',
        'bentara',
      ]);
      expect(carWheelSegments.fold(0, (a, b) => a + b.weight), 8942);
      for (final b in carWheelSegments) {
        expect(b.multiplier * b.weight, 6600);
        expect(carWheelPayout({b.key: 100}, b.key), 100 * b.multiplier);
        expect(carWheelBet(b.key), b);
        for (final other in carWheelSegments.where((s) => s != b)) {
          expect(carWheelPayout({other.key: 100}, b.key), 0);
        }
      }
      expect(carWheelMaxPayout({'aurelia': 1000, 'lambrex': 100}), 8800);
      for (final bad in ['', 'red', 'Aurelia', 'constructor']) {
        expect(carWheelBet(bad), isNull);
      }
    });
    test('compact values and shared state parsing', () {
      expect(carWheelCompact(100), '100');
      expect(carWheelCompact(1000), '1K');
      expect(carWheelCompact(10400), '10.4K');
      expect(carWheelCompact(257000), '257K');
      expect(carWheelCompact(1500000), '1.5M');
      final s = CarWheelState.fromJson({
        'totals': 'x',
        'history': ['aurelia', 7, 'bad'],
        'me': 5,
        'result': 'bad',
      });
      expect(s.totals, isEmpty);
      expect(s.history, ['aurelia']);
      expect(s.result, isNull);
      expect(s.myStaked, 0);
      expect(CarWheelState.fromJson({'history': 3, 'players': 4}).players,
          isEmpty,);
    });
    test(
        'angle hit testing and spin end put every result under the top pointer',
        () {
      for (final (i, b) in carWheelSegments.indexed) {
        final angle = i * pi / 4;
        expect(carWheelKeyAtAngle(angle), b.key);
        expect(
            carWheelKeyAt(
                Offset(200 + sin(angle) * 120, 200 - cos(angle) * 120), 400,),
            b.key,);
        for (final start in [0.0, 2.5, 100.0]) {
          for (final jitter in [-.3, 0.0, .3]) {
            final end = carWheelSpinEnd(start, b.key, jitter: jitter);
            expect(carWheelKeyAtAngle(-end), b.key);
            expect(end - start, greaterThanOrEqualTo(8 * pi));
            expect(carWheelSpinFrame(0, start, end), start);
            expect(carWheelSpinFrame(1, start, end), closeTo(end, .00001));
          }
        }
      }
      expect(carWheelKeyAt(const Offset(200, 200), 400), isNull);
      expect(carWheelKeyAt(Offset.zero, 400), isNull);
    });
    test('both languages have rules, actions and friendly server errors', () {
      for (final ar in [true, false]) {
        final s = CarWheelStrings(ar);
        for (final key in [
          'title',
          'help',
          'paytable',
          'history',
          'ranking',
          'players',
          'settings',
          'rules',
          'rulesPay',
          'rulesFair',
          'renew',
          'undo',
          'clear',
          'rebet',
          'cancel',
          'BETTING_CLOSED',
          'INSUFFICIENT_COINS',
          'MAX_BET',
          'BET_TOO_HIGH',
          'NO_PREVIOUS',
          'PRIZE_POOL_LOW',
        ]) {
          expect(s.text(key), isNot(key), reason: '$ar: $key');
        }
        expect(s.betLabel(carWheelSegments.first), contains('Aurelia'));
        expect(s.winning('lambrex'), contains('x88'));
      }
    });
  });

  testWidgets('chips use server balance; renew undo and clear refund the table',
      (tester) async {
    final repo = _Repository();
    final screen = await _mount(tester, repo);
    expect(find.textContaining('اللعبة 249'), findsOneWidget);
    expect(find.text('0 / 383K'), findsOneWidget);
    screen.placeChip('aurelia');
    screen.placeChip('lambrex');
    await _settle(tester);
    expect(repo.calls, ['bet aurelia 1000', 'bet lambrex 1000']);
    expect(_coins(tester), 98000);
    expect(screen.myStakes, {'aurelia': 1000, 'lambrex': 1000});
    await tester.tap(find.text('تجديد'));
    await _settle(tester);
    await tester.tap(find.text('تراجع'));
    await _settle(tester);
    expect(_coins(tester), 99000);
    await tester.tap(find.text('تجديد'));
    await _settle(tester);
    await tester.tap(find.text('مسح الرهانات'));
    await _settle(tester);
    expect(screen.myStakes, isEmpty);
    expect(_coins(tester), 100000);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
  testWidgets(
      'actual wedge tap resolves the angle and carries accessible labels',
      (tester) async {
    final repo = _Repository();
    await _mount(tester, repo);
    final label = find.text('Aurelia').first;
    await tester.tap(label);
    await _settle(tester);
    expect(repo.calls, ['bet aurelia 1000']);
    expect(find.bySemanticsLabel('راهن على Aurelia بمضاعف 8'), findsOneWidget);
    await _unmount(tester);
  });
  testWidgets(
      'closed bets are blocked; reduced motion lands and announces the server result',
      (tester) async {
    final repo = _Repository();
    final screen = await _mount(tester, repo);
    screen.placeChip('lambrex');
    await _settle(tester);
    screen.applyState(repo.table(phase: 'closing'));
    await _settle(tester);
    screen.placeChip('aurelia');
    await _settle(tester);
    expect(repo.calls.length, 1);
    screen.applyState(repo.table(phase: 'spinning', result: 'lambrex'));
    await _settle(tester);
    screen.applyState(
        repo.table(phase: 'result', result: 'lambrex', payout: 88000),
        mine: true,);
    await _settle(tester);
    expect(find.textContaining('Lambrex فاز'), findsOneWidget);
    expect(find.text('ربحت 88,000'), findsOneWidget);
    await _unmount(tester);
  });
  testWidgets('new round clears stakes and renew repeats; language persists',
      (tester) async {
    final repo = _Repository()..last = {'aurelia': 300};
    final screen = await _mount(tester, repo);
    screen.placeChip('porsenna');
    await _settle(tester);
    repo.stakes = {};
    repo.chips.clear();
    screen.applyState({...repo.table(), 'round': 250});
    await _settle(tester);
    expect(screen.myStakes, isEmpty);
    await tester.tap(find.text('تجديد'));
    await _settle(tester);
    await tester.tap(find.text('إعادة آخر رهان'));
    await _settle(tester);
    expect(screen.myStakes, {'aurelia': 300});
    await tester.tap(find.byTooltip('القائمة'));
    await _route(tester);
    await tester.tap(find.text('الإعدادات'));
    await _route(tester);
    await tester.tap(find.text('English'));
    await _settle(tester);
    expect(find.text('Renew'), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance()).getBool('carwheel.701.arabic'),
        isFalse,);
    await _unmount(tester);
  });
  for (final width in [320.0, 360.0, 720.0]) {
    testWidgets('painted fallback fits ${width.toInt()} pixels',
        (tester) async {
      await _mount(tester, _Repository(), size: Size(width, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('Aurelia'), findsOneWidget);
      await _unmount(tester);
    });
  }
}

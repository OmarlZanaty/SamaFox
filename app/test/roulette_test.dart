import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/models/user.dart';
import 'package:samafox/providers/auth_provider.dart';
import 'package:samafox/repositories/roulette_repository.dart';
import 'package:samafox/screens/games/roulette_engine.dart';
import 'package:samafox/screens/games/roulette_screen.dart';

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(AuthState(user: User(id: 701, name: 'Test', coinsBalance: 100000)));
  @override
  void updateCoinsBalance(int newBalance) =>
      state = state.copyWith(user: state.user!.copyWith(coinsBalance: newBalance));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the server: keeps this player's stakes and balance.
class _Repository extends RouletteRepository {
  int balance = 100000;
  Map<String, int> stakes = {};
  final List<String> calls = [];
  Map<String, int> last = {};
  Map<String, dynamic> table({String phase = 'betting', int? result, int payout = 0}) => {
        'round': 249,
        'phase': phase,
        'msLeft': 20000,
        'seedHash': 'ab' * 32,
        'result': result,
        'totals': {'red': 383000, ...stakes},
        'totalBet': 2286400 + stakes.values.fold(0, (a, b) => a + b),
        'playerCount': 3,
        'players': [
          {'userId': 9, 'name': 'Karim', 'avatarUrl': null, 'staked': 5000},
        ],
        'history': [32, 0, 15],
        'me': {'stakes': stakes, 'staked': stakes.values.fold(0, (a, b) => a + b), 'payout': payout},
      };
  Map<String, dynamic> _ok() => {'success': true, 'stakes': stakes, 'balance': balance};

  @override
  Future<Map<String, dynamic>> fetchState() async => {'state': table(), 'balance': balance};
  @override
  Future<Map<String, dynamic>> bet(String key, int amount) async {
    calls.add('bet $key $amount');
    if (amount > balance) throw const RouletteException('INSUFFICIENT_COINS');
    balance -= amount;
    stakes[key] = (stakes[key] ?? 0) + amount;
    return _ok();
  }

  @override
  Future<Map<String, dynamic>> clear() async {
    calls.add('clear');
    balance += stakes.values.fold(0, (a, b) => a + b);
    stakes = {};
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
  Future<Map<String, dynamic>> ranking() async => {'entries': [], 'me': {'net': 0, 'best': 0}};
}

Future<RouletteScreenState> _mount(WidgetTester tester, _Repository repository, {Size size = const Size(390, 900)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'roulette.701.sound': false,
    'roulette.701.motion': false,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => _Auth())],
      child: MaterialApp(home: RouletteScreen(repository: repository, live: false)),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return tester.state<RouletteScreenState>(find.byType(RouletteScreen));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

int _coins(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RouletteScreen))).read(authStateProvider).user!.coinsBalance ?? 0;

void main() {
  group('engine', () {
    test('European wheel: 37 pockets, one zero, standard order, alternating colours', () {
      expect(rouletteWheel.length, 37);
      expect(rouletteWheel.toSet().length, 37);
      expect(rouletteWheel.take(4), [0, 32, 15, 19]);
      expect(rouletteColor(0), RouletteColor.green);
      for (var i = 1; i < 36; i++) {
        expect(rouletteColor(rouletteWheel[i]), isNot(rouletteColor(rouletteWheel[i + 1])));
      }
    });
    test('keys parse like the server and refuse off-table spots', () {
      expect(rouletteBet('split:17-20')!.numbers, [17, 20]);
      expect(rouletteBet('corner:1-2-4-5')!.numbers, [1, 2, 4, 5]);
      expect(rouletteBet('six:31')!.numbers, [31, 32, 33, 34, 35, 36]);
      for (final bad in ['split:3-4', 'n:37', 'six:34', 'corner:3-4-6-7', 'split:20-17']) {
        expect(rouletteBet(bad), isNull, reason: bad);
      }
    });
    test('payouts include the stake; zero loses outside bets', () {
      expect(roulettePayout({'n:17': 100}, 17), 2600);
      expect(roulettePayout({'red': 500}, 1), 700);
      expect(roulettePayout({'dozen2': 1000}, 13), 2100);
      expect(roulettePayout({'red': 100, 'even': 100, 'low': 100, 'dozen1': 100, 'column1': 100}, 0), 0);
      expect(roulettePayout({'ff': 100}, 0), 650);
    });
    test('taps map to straight, split, corner, street and six line', () {
      expect(rouletteKeyAt(5, 1, .5, .5), 'n:17');
      expect(rouletteKeyAt(5, 1, .95, .5), 'split:17-18');
      expect(rouletteKeyAt(5, 1, .05, .5), 'split:16-17');
      expect(rouletteKeyAt(5, 1, .5, .95), 'split:17-20');
      expect(rouletteKeyAt(5, 1, .95, .95), 'corner:17-18-20-21');
      expect(rouletteKeyAt(5, 0, .05, .5), 'street:16');
      expect(rouletteKeyAt(5, 0, .05, .95), 'six:16');
      expect(rouletteKeyAt(0, 0, .05, .05), 'ff');
      expect(rouletteKeyAt(0, 1, .5, .05), 'split:0-2');
      expect(rouletteKeyAt(11, 2, .95, .95), 'n:36');
      // Every key the table can produce is one the server accepts.
      final random = Random(1);
      for (var i = 0; i < 2000; i++) {
        final key = rouletteKeyAt(random.nextInt(12), random.nextInt(3), random.nextDouble(), random.nextDouble());
        expect(rouletteBet(key), isNotNull, reason: key);
        expect(rouletteAnchor(key), isNotNull, reason: key);
      }
    });
    test('the ball always finishes in the result pocket', () {
      for (final result in [0, 17, 26, 32]) {
        for (final start in [0.0, 2.5, 100.0]) {
          final f = rouletteSpinFrame(u: 1, wheelStart: start, result: result);
          expect(f.radius, 0);
          final relative = (f.ball - f.wheel) % (2 * pi);
          expect(rouletteWheel[(relative / roulettePocketAngle).floor()], result);
        }
      }
      expect(rouletteSpinFrame(u: .2, wheelStart: 0, result: 5).radius, 1);
    });
    test('state parsing tolerates junk', () {
      final s = RouletteState.fromJson({'totals': 'x', 'history': [1, 'a', 2], 'me': 5});
      expect(s.totals, isEmpty);
      expect(s.history, [1, 2]);
      expect(s.myStaked, 0);
    });
  });

  testWidgets('tapping the felt places chips; totals and balance follow', (tester) async {
    final repository = _Repository();
    final screen = await _mount(tester, repository);
    expect(find.text('الجولة: 249'), findsOneWidget);
    expect(find.text('إجمالي الرهانات: 2286400'), findsOneWidget);
    expect(find.text('0/383000'), findsOneWidget); // red: mine / everyone
    screen.placeChip('red');
    screen.placeChip('n:17');
    await _settle(tester);
    expect(repository.calls, ['bet red 1000', 'bet n:17 1000']);
    expect(screen.myStakes, {'red': 1000, 'n:17': 1000});
    expect(find.text('إجمالي رهاني: 2000'), findsOneWidget);
    expect(_coins(tester), 98000);
    await tester.ensureVisible(find.text('مسح'));
    await tester.pump();
    await tester.tap(find.text('مسح'));
    await _settle(tester);
    expect(screen.myStakes, isEmpty);
    expect(_coins(tester), 100000);
    await _unmount(tester);
  });

  testWidgets('a tap on the line between two numbers bets the split', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository);
    final seventeen = find.text('17');
    final eighteen = find.text('18');
    final between = (tester.getCenter(seventeen) + tester.getCenter(eighteen)) / 2;
    await tester.ensureVisible(seventeen);
    await tester.pump();
    await tester.tapAt((tester.getCenter(seventeen) + tester.getCenter(eighteen)) / 2);
    await _settle(tester);
    expect(between.dx, isNonZero);
    expect(repository.calls.single, 'bet split:17-18 1000');
    await _unmount(tester);
  });

  testWidgets('bets are refused once the round closes; the result is announced', (tester) async {
    final repository = _Repository();
    final screen = await _mount(tester, repository);
    screen.placeChip('n:17');
    await _settle(tester);
    screen.applyState(repository.table(phase: 'closing'));
    await _settle(tester);
    screen.placeChip('red');
    await _settle(tester);
    expect(repository.calls.length, 1);
    expect(find.text('الرهانات مغلقة — انتظر النتيجة'), findsWidgets);
    screen.applyState(repository.table(phase: 'result', result: 17, payout: 26000), mine: true);
    await _settle(tester);
    expect(find.textContaining('الرقم الفائز: 17'), findsWidgets);
    expect(find.textContaining('ربحت 26000'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a new round clears my table; Rebet replays the last one', (tester) async {
    final repository = _Repository()..last = {'dozen1': 5000};
    final screen = await _mount(tester, repository);
    screen.placeChip('red');
    await _settle(tester);
    repository.stakes = {};
    screen.applyState({...repository.table(), 'round': 250});
    await _settle(tester);
    expect(screen.myStakes, isEmpty);
    expect(find.text('الجولة: 250'), findsOneWidget);
    await tester.ensureVisible(find.text('إعادة الرهان'));
    await tester.tap(find.text('إعادة الرهان'));
    await _settle(tester);
    expect(repository.calls.last, 'bet dozen1 5000');
    expect(screen.myStakes, {'dozen1': 5000});
    await _unmount(tester);
  });

  testWidgets('switches to English and LTR from settings', (tester) async {
    await _mount(tester, _Repository());
    Directionality direction() => tester.widget<Directionality>(
          find.descendant(of: find.byType(RouletteScreen), matching: find.byType(Directionality)).first,
        );
    expect(direction().textDirection, TextDirection.rtl);
    await tester.tap(find.byTooltip('الإعدادات'));
    await _settle(tester);
    await tester.tap(find.text('English'));
    await _settle(tester);
    expect(direction().textDirection, TextDirection.ltr);
    expect(find.text('ROULETTE'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('roulette.701.arabic'), isFalse);
    await _unmount(tester);
  });

  for (final width in [320.0, 360.0, 720.0]) {
    testWidgets('fits a ${width.toInt()} px screen without overflow', (tester) async {
      await _mount(tester, _Repository(), size: Size(width, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('36'), findsWidgets);
      await _unmount(tester);
    });
  }
}

import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:samafox/screens/games/car_wheel_art.dart';
import 'package:samafox/screens/games/car_wheel_wheel.dart';
import 'package:samafox/screens/games/car_wheel_widgets.dart';
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
          AuthState(user: User(id: 701, name: 'Test', coinsBalance: 100000)),
        );
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
  Map<String, dynamic> table({
    String phase = 'betting',
    String? result,
    int payout = 0,
  }) =>
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

Future<CarWheelScreenState> _mount(
  WidgetTester tester,
  _Repository repository, {
  Size size = const Size(390, 900),
  bool motion = false,
  bool reduced = false,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'carwheel.701.sound': false,
    'carwheel.701.motion': motion,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => _Auth())],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'ElMessiri'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduced, padding: padding),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: CarWheelScreen(repository: repository, live: false),
        ),
      ),
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
  testWidgets('capture the 390px screen for visual review', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('ElMessiri')
        ..addFont(rootBundle.load('assets/fonts/ElMessiri-Regular.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final repo = _Repository();
    final screen = await _mount(tester, repo, size: const Size(390, 844));
    repo.stakes = {'lambrex': 1000, 'aurelia': 1000};
    Map<String, dynamic> scene({bool win = false}) => {
          ...repo.table(
            phase: win ? 'result' : 'betting',
            result: win ? 'lambrex' : null,
            payout: win ? 88000 : 0,
          ),
          'players': [
            {'name': 'Nour', 'staked': 98000},
            {'name': 'Karim', 'staked': 42000},
            {'name': 'Lina', 'staked': 28500},
            {'name': 'Sami', 'staked': 15000},
          ],
          'playerCount': 18,
          'history': [
            'aurelia',
            'porsenna',
            'voltara',
            'bentara',
            'porsenna',
            'bavaro',
            'voltara',
            'stellaro',
            'porsenna',
            'aurelia',
          ],
          'totals': {
            for (final (i, b) in carWheelSegments.indexed)
              b.key: 25000 + i * 12500,
          },
        };
    screen.applyState(scene(), mine: true);
    await tester.runAsync(() async {
      final context = tester.element(find.byType(CarWheelScreen));
      for (final name in [
        'background',
        'velvet_atrium_v2',
        'rim',
        'hub',
        'pointer',
        'trophy',
        'chip_100',
        'chip_1k',
        'chip_10k',
        'chip_100k',
        for (final b in carWheelSegments) 'emblem_${b.key}',
      ]) {
        await precacheImage(carWheelProvider(name), context);
      }
    });
    await _settle(tester);
    Future<void> capture(String phase) async {
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/car_wheel-v2').create(recursive: true);
        final prefix =
            Platform.environment['CAR_WHEEL_CAPTURE_PREFIX'] ?? 'after';
        await File('build/car_wheel-v2/$prefix-$phase.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('betting');
    screen.applyState(scene(win: true), mine: true);
    await _settle(tester);
    await capture('result');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
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
      expect(
        CarWheelState.fromJson({'history': 3, 'players': 4}).players,
        isEmpty,
      );
    });
    test(
        'angle hit testing and spin end put every result under the top pointer',
        () {
      for (final (i, b) in carWheelSegments.indexed) {
        final angle = i * pi / 4;
        expect(carWheelKeyAtAngle(angle), b.key);
        expect(
          carWheelKeyAt(
            Offset(200 + sin(angle) * 120, 200 - cos(angle) * 120),
            400,
          ),
          b.key,
        );
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
  testWidgets('card and wedge taps share server bets and accessible labels',
      (tester) async {
    final repo = _Repository();
    await _mount(tester, repo);
    final label = find.text('Aurelia').first;
    await tester.tap(label);
    await _settle(tester);
    expect(repo.calls, ['bet aurelia 1000']);
    final wheel = tester.getRect(find.byType(CarWheelWheel));
    await tester.tapAt(wheel.center - Offset(0, wheel.width * .31));
    await _settle(tester);
    expect(repo.calls, ['bet aurelia 1000', 'bet aurelia 1000']);
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
      mine: true,
    );
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
      isFalse,
    );
    await _unmount(tester);
  });
  for (final size in [
    const Size(320, 740),
    const Size(360, 740),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('one screen fits $size with safe areas and no debug text',
        (tester) async {
      final repo = _Repository();
      final screen = await _mount(tester, repo,
          size: size, padding: const EdgeInsets.only(top: 24, bottom: 20),);
      void check() {
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(find.byType(CarWheelBetCard), findsNWidgets(8));
        final wheel = tester.getRect(find.byType(CarWheelWheel));
        expect(wheel.left, greaterThanOrEqualTo(0));
        expect(wheel.right, lessThanOrEqualTo(size.width));
        for (final card in find.byType(CarWheelBetCard).evaluate()) {
          final rect = tester.getRect(find.byWidget(card.widget));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThan(size.height - 70));
        }
        final dock = tester.getRect(find.byType(CarWheelDock));
        expect(dock.bottom, lessThanOrEqualTo(size.height - 20));
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(
              t.data ?? '',
              isNot(matches(RegExp(
                  r'request.?id|latency|\bms\b|[0-9]+\.[0-9]+s|BETTING_CLOSED|BAD_TARGET',
                  caseSensitive: false,),),),);
        }
      }

      check();
      screen.applyState(
          repo.table(phase: 'result', result: 'lambrex', payout: 88000),
          mine: true,);
      await _settle(tester);
      check();
      await _unmount(tester);
    });
  }
  testWidgets(
      'system reduced motion pauses ambient animation and lands instantly',
      (tester) async {
    final repo = _Repository();
    final screen = await _mount(tester, repo, motion: true, reduced: true);
    screen.applyState(repo.table(phase: 'closing'));
    screen.applyState(
        {...repo.table(phase: 'spinning', result: 'stellaro'), 'msLeft': 7000},);
    await tester.pump();
    final wheel = tester.widget<CarWheelWheel>(find.byType(CarWheelWheel));
    expect(wheel.reduced, isTrue);
    expect(carWheelKeyAtAngle(-wheel.angle.value), 'stellaro');
    final ambient = wheel.ambient.value;
    await tester.pump(const Duration(seconds: 1));
    expect(wheel.ambient.value, ambient);
    screen.applyState(
        repo.table(phase: 'result', result: 'stellaro', payout: 66000),
        mine: true,);
    await tester.pump();
    expect(find.textContaining('66,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
  testWidgets('spin frames leave the dock intact and land on the server result',
      (tester) async {
    final repo = _Repository();
    final screen = await _mount(tester, repo, motion: true);
    screen.applyState(repo.table(phase: 'closing'));
    screen.applyState(
        {...repo.table(phase: 'spinning', result: 'bavaro'), 'msLeft': 7000},);
    await tester.pump();
    final dock = tester.widget<CarWheelDock>(find.byType(CarWheelDock));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
        identical(dock, tester.widget<CarWheelDock>(find.byType(CarWheelDock))),
        isTrue,);
    screen.applyState(repo.table(phase: 'result', result: 'bavaro'),
        mine: true,);
    await tester.pump();
    expect(
        carWheelKeyAtAngle(-tester
            .widget<CarWheelWheel>(find.byType(CarWheelWheel))
            .angle
            .value,),
        'bavaro',);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}

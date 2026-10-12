import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/models/user.dart';
import 'package:samafox/providers/auth_provider.dart';
import 'package:samafox/repositories/yummy_repository.dart';
import 'package:samafox/screens/games/yummy_engine.dart';
import 'package:samafox/screens/games/yummy_grid.dart';
import 'package:samafox/screens/games/yummy_screen.dart';
import 'package:samafox/screens/games/yummy_strings.dart';
import 'yummy_engine_test.dart' show yummyFixture;

/// Pixel goldens for the machine and the whole screen, with motion off so
/// every frame is deterministic. Regenerate after an intentional visual
/// change: flutter test --update-goldens test/yummy_golden_test.dart

const _board = [
  'cherry', 'lemon', 'wild', 'grapes', 'orange', //
  'strawberry', 'strawberry', 'strawberry', 'diamond', 'candy', //
  'watermelon', 'bonus', 'orange', 'jackpot', 'lemon',
];

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
  @override
  Future<Map<String, dynamic>> fetchState() async {
    final round = yummyFixture(prize: 600, balance: 49700);
    (round['spin'] as Map)['grid'] = _board;
    return {
      'balance': 49700,
      'history': [round],
      'layout': {
        'betSteps': [10, 20, 50, 100, 200, 500, 1000],
        'minBet': 10,
        'maxBet': 9000,
        'enabled': true,
        'paytable': yummyPaytable,
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> feed() async => [];
}

Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
}

void main() {
  // Decode the symbols in the real zone before any machine asks for them.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });
  Future<void> atlas(WidgetTester tester) =>
      tester.runAsync(YummyAtlas.load).then((_) {});
  testWidgets('machine with a winning line', (tester) async {
    tester.view.physicalSize = const Size(420, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<YummyMachineState>();
    await atlas(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF08B9F2),
          body: Center(
            child: SizedBox(
              width: 400,
              child: YummyMachine(
                key: key,
                initial: _board,
                strings: const YummyStrings(false),
                reduced: true,
              ),
            ),
          ),
        ),
      ),
    );
    await _precache(tester);
    await key.currentState!.showWins(
      [
        const YummyLineWin(0, 'strawberry', 3, [5, 6, 7], 600),
      ],
      label: '+600',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(YummyMachine),
      matchesGoldenFile('goldens/yummy_machine.png'),
    );
  });

  testWidgets('free-spins skin', (tester) async {
    tester.view.physicalSize = const Size(420, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await atlas(tester);
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: YummyMachine(
                initial: _board,
                strings: YummyStrings(false),
                reduced: true,
                freeSpins: true,
              ),
            ),
          ),
        ),
      ),
    );
    await _precache(tester);
    await expectLater(
      find.byType(YummyMachine),
      matchesGoldenFile('goldens/yummy_machine_free.png'),
    );
  });

  testWidgets('whole screen at 390×844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'yummy.701.sound': false,
      'yummy.701.motion': false,
      'yummy.701.arabic': false,
    });
    await atlas(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => _Auth())],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: YummyScreen(repository: _Repository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _precache(tester);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(YummyScreen),
      matchesGoldenFile('goldens/yummy_screen.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });
}

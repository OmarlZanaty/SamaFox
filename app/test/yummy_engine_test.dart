import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/screens/games/yummy_engine.dart';
import 'package:samafox/screens/games/yummy_preferences.dart';

Map<String, dynamic> yummyFixture({
  int nonce = 1,
  int prize = 200,
  int balance = 49300,
}) =>
    {
      'id': 'round-$nonce',
      'at': '2026-10-07T12:00:00Z',
      'nonce': nonce,
      'balance': balance,
      'serverSeedHash': 'hash',
      'clientSeed': 'seed',
      'spin': {
        'grid': [
          'bonus',
          'bonus',
          'bonus',
          'bonus',
          'bonus',
          'strawberry',
          'strawberry',
          'strawberry',
          'orange',
          'lemon',
          'bonus',
          'bonus',
          'bonus',
          'bonus',
          'bonus',
        ],
        'wins': [
          {
            'line': 0,
            'symbol': 'strawberry',
            'count': 3,
            'cells': [5, 6, 7],
            'amount': 200,
          }
        ],
        'betPerLine': 100,
        'activeLines': 9,
        'totalBet': 900,
        'totalPrize': prize,
        'requestedPrize': prize,
        'bonusTriggered': false,
        'bonusMultiplier': 0,
        'bonusPrize': 0,
        'jackpotTriggered': false,
        'capped': false,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('1 total bet calculation', () => expect(yummyTotalBet(100, 9), 900));
  test(
    '2 insufficient balance blocks spin',
    () => expect(yummyCanSpin(899, 100, 9), isFalse),
  );
  test('3 horizontal line from the left', () {
    final grid = List<String>.filled(15, 'bonus');
    grid[5] = grid[6] = grid[7] = 'cherry';
    final wins = yummyEvaluateLines(grid, 100, 1);
    expect(wins.single.amount, 300);
    expect(wins.single.cells, [5, 6, 7]);
    grid[5] = 'bonus';
    grid[8] = grid[9] = 'cherry';
    expect(yummyEvaluateLines(grid, 100, 1), isEmpty);
  });
  test('4 all diagonal and V lines match the server patterns', () {
    for (var line = 0; line < 9; line++) {
      final grid = List<String>.filled(15, 'bonus');
      for (var reel = 0; reel < 5; reel++) {
        grid[yummyPaylines[line][reel] * 5 + reel] = 'diamond';
      }
      expect(
        yummyEvaluateLines(grid, 10, 9)
            .firstWhere((win) => win.line == line)
            .amount,
        5000,
      );
    }
  });
  test('5 leading wild substitutes and pays only the best match', () {
    final grid = List<String>.filled(15, 'bonus');
    grid[5] = 'wild';
    grid[6] = 'diamond';
    grid[7] = 'wild';
    expect(yummyEvaluateLines(grid, 100, 1).single.amount, 2000);
    grid[6] = 'wild';
    expect(yummyEvaluateLines(grid, 100, 1).single.amount, 2500);
  });
  test('6 bonus is never wild; wild never substitutes a jackpot', () {
    final grid = List<String>.filled(15, 'bonus');
    grid[5] = 'diamond';
    grid[7] = 'diamond';
    expect(yummyEvaluateLines(grid, 100, 1), isEmpty);
    grid[5] = 'jackpot';
    grid[6] = 'wild';
    grid[7] = 'jackpot';
    expect(yummyEvaluateLines(grid, 100, 1), isEmpty);
  });
  test('7 bonus detection requires at least three', () {
    final grid = List<String>.filled(15, 'cherry');
    grid[0] = grid[8] = 'bonus';
    expect(yummyHasBonus(grid), isFalse);
    grid[14] = 'bonus';
    expect(yummyHasBonus(grid), isTrue);
  });
  test('8 parses the authoritative balance and capped prize', () {
    final round = YummyRound.fromJson(yummyFixture());
    expect(round.balance, 50000 - round.totalBet + round.totalPrize);
    final fixture = yummyFixture();
    (fixture['spin'] as Map)['capped'] = true;
    (fixture['spin'] as Map)['requestedPrize'] = 1000;
    final capped = YummyRound.fromJson(fixture);
    expect(capped.totalPrize, 200);
    expect(capped.requestedPrize, 1000);
  });
  test('9 STOP only reveals the immutable server result', () {
    final result = YummyRound.fromJson(yummyFixture());
    final replay = YummyReplay(result);
    replay.stop();
    replay.stop();
    expect(replay.revealedReels, 5);
    expect(identical(replay.result, result), isTrue);
    expect(() => result.grid[0] = 'wild', throwsUnsupportedError);
  });
  test('10 history persists per account and retains the last fifty', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final preferences = YummyPreferences(storage, '701');
    await preferences.saveHistory(
      List.generate(
        60,
        (index) => YummyRound.fromJson(yummyFixture(nonce: index)),
      ),
    );
    expect(YummyPreferences(storage, '701').history, hasLength(50));
    expect(YummyPreferences(storage, '702').history, isEmpty);
  });
  test('11 clear history never creates or resets a coin balance', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final preferences = YummyPreferences(storage, '701');
    await preferences.saveHistory([YummyRound.fromJson(yummyFixture())]);
    await preferences.clearHistory();
    expect(preferences.history, isEmpty);
    expect(preferences.visible([YummyRound.fromJson(yummyFixture())]), isEmpty);
    expect(storage.getKeys().any((key) => key.contains('balance')), isFalse);
  });
  test('settings and unresolved request persist without client outcome math',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final preferences = YummyPreferences(storage, '701');
    expect(preferences.arabic, isTrue);
    await preferences.setSetting('arabic', false);
    await preferences.savePending(
      {'requestId': 'same-key', 'betPerLine': 100, 'activeLines': 9},
    );
    expect(YummyPreferences(storage, '701').arabic, isFalse);
    expect(preferences.pending!['requestId'], 'same-key');
    await preferences.savePending(null);
    expect(preferences.pending, isNull);
  });
  test('decorative RNG is injectable; inactive lines never win', () {
    expect(yummyDecorativeGrid(Random(7)), yummyDecorativeGrid(Random(7)));
    final grid = List<String>.filled(15, 'bonus');
    grid[0] = grid[1] = grid[2] = 'diamond';
    expect(yummyEvaluateLines(grid, 100, 1), isEmpty);
    expect(() => yummyEvaluateLines(grid, 100, 10), throwsArgumentError);
  });
}

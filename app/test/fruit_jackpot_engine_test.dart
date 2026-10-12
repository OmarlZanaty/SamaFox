import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samafox/screens/games/fruit_jackpot_engine.dart';
import 'package:samafox/screens/games/fruit_jackpot_preferences.dart';

Map<String, dynamic> fruitFixture({
  int number = 1,
  int balance = 49900,
  int prize = 0,
  bool bonus = false,
  bool jackpot = false,
}) => {
  'id': 'round-$number',
  'at': '2026-10-07T12:00:00Z',
  'roundNumber': number,
  'nonce': number,
  'balance': balance,
  'serverSeedHash': 'hash',
  'clientSeed': 'test',
  'spin': {
    'grid': jackpot
        ? List.filled(9, 'cherry')
        : bonus
        ? [
            'multiplier',
            'multiplier',
            'multiplier',
            'lemon',
            'kiwi',
            'plum',
            'banana',
            'raspberry',
            'strawberry',
          ]
        : List.of(fruitJackpotSymbolIds),
    'wins': <Map<String, dynamic>>[],
    'betPerLine': 100,
    'activeLines': 8,
    'totalBet': 100,
    'totalPrize': prize,
    'requestedPrize': prize,
    'centreMultiplier': 1,
    'rowMultipliers': [1, 2, 1],
    'bonusTriggered': bonus,
    'bonusMultiplier': bonus ? 5 : 0,
    'bonusPrize': bonus ? 500 : 0,
    'jackpotTriggered': jackpot,
    'capped': false,
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exactly eight valid straight lines', () {
    expect(fruitJackpotPaylines.length, 8);
    for (final cells in fruitJackpotPaylines) {
      expect(cells.toSet().length, 3);
      expect(cells[1] - cells[0], cells[2] - cells[1]);
    }
  });
  test('server result parses bonus, jackpot and STOP retains result', () {
    for (final f in [
      fruitFixture(),
      fruitFixture(bonus: true, prize: 500),
      fruitFixture(jackpot: true, prize: 100000),
    ]) {
      final round = FruitJackpotRound.fromJson(f),
          replay = FruitJackpotReplay(FruitJackpotRound.fromJson(f));
      replay.stop();
      expect(replay.revealedReels, 9);
      expect(replay.result.json, round.json);
      expect(round.grid.length, 9);
    }
    final invalid = fruitFixture();
    (invalid['spin'] as Map)['grid'] = ['bad'];
    expect(() => FruitJackpotRound.fromJson(invalid), throwsFormatException);
  });
  test('account scoped durable pending and history restoration', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final prefs = FruitJackpotPreferences(storage, '701');
    await prefs.savePending({
      'requestId': 'stable',
      'betPerLine': 100,
      'activeLines': 8,
    });
    await prefs.saveHistory([FruitJackpotRound.fromJson(fruitFixture())]);
    final restored = FruitJackpotPreferences(storage, '701');
    expect(restored.pending!['requestId'], 'stable');
    expect(restored.history.single.id, 'round-1');
    expect(FruitJackpotPreferences(storage, '702').history, isEmpty);
    await prefs.clearHistory();
    expect(prefs.history, isEmpty);
    expect(prefs.pending, isNotNull);
  });
}

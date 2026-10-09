const fruitJackpotPaylines = <List<int>>[
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];
const fruitJackpotPaytable = {
  'lemon': 5,
  'raspberry': 5,
  'kiwi': 5,
  'cherry': 40,
  'plum': 5,
  'watermelon': 20,
  'banana': 10,
  'strawberry': 10,
};
const fruitJackpotSymbolIds = [
  'lemon',
  'raspberry',
  'kiwi',
  'cherry',
  'plum',
  'watermelon',
  'banana',
  'strawberry',
  'multiplier',
];
const fruitJackpotBets = [100, 1000, 10000, 100000];

class FruitJackpotLineWin {
  final int line, count, amount;
  final String symbol;
  final List<int> cells;
  const FruitJackpotLineWin(
    this.line,
    this.symbol,
    this.count,
    this.cells,
    this.amount,
  );
  factory FruitJackpotLineWin.fromJson(Map<String, dynamic> json) =>
      FruitJackpotLineWin(
        (json['line'] as num).toInt(),
        json['symbol'] as String,
        (json['count'] as num).toInt(),
        List<int>.from(json['cells'] as List),
        (json['amount'] as num).toInt(),
      );
}

class FruitJackpotRound {
  int get centreMultiplier => (json['spin'] as Map)['centreMultiplier'] as int;
  List<int> get rowMultipliers =>
      List<int>.from((json['spin'] as Map)['rowMultipliers'] as List);
  int get roundNumber => json['roundNumber'] as int? ?? 0;
  final String id, serverSeedHash, clientSeed;
  final DateTime at;
  final List<String> grid;
  final List<FruitJackpotLineWin> wins;
  final int betPerLine,
      activeLines,
      totalBet,
      totalPrize,
      requestedPrize,
      balance,
      nonce,
      bonusMultiplier,
      bonusPrize;
  final bool bonusTriggered, jackpotTriggered, capped;
  final Map<String, dynamic> json;
  FruitJackpotRound.fromJson(Map<String, dynamic> source)
    : json = Map.unmodifiable(source),
      id = source['id']?.toString() ?? '',
      at = DateTime.tryParse(source['at']?.toString() ?? '') ?? DateTime.now(),
      serverSeedHash = source['serverSeedHash'] as String? ?? '',
      clientSeed = source['clientSeed'] as String? ?? '',
      nonce = (source['nonce'] as num?)?.toInt() ?? 0,
      balance = (source['balance'] as num).toInt(),
      grid = List.unmodifiable(
        List<String>.from((source['spin'] as Map)['grid'] as List),
      ),
      wins = List.unmodifiable(
        ((source['spin'] as Map)['wins'] as List).map(
          (win) => FruitJackpotLineWin.fromJson(
            Map<String, dynamic>.from(win as Map),
          ),
        ),
      ),
      betPerLine = ((source['spin'] as Map)['betPerLine'] as num).toInt(),
      activeLines = ((source['spin'] as Map)['activeLines'] as num).toInt(),
      totalBet = ((source['spin'] as Map)['totalBet'] as num).toInt(),
      totalPrize = ((source['spin'] as Map)['totalPrize'] as num).toInt(),
      requestedPrize =
          (((source['spin'] as Map)['requestedPrize'] ??
                      (source['spin'] as Map)['totalPrize'])
                  as num)
              .toInt(),
      bonusMultiplier =
          ((source['spin'] as Map)['bonusMultiplier'] as num?)?.toInt() ?? 0,
      bonusPrize =
          ((source['spin'] as Map)['bonusPrize'] as num?)?.toInt() ?? 0,
      bonusTriggered = (source['spin'] as Map)['bonusTriggered'] == true,
      jackpotTriggered = (source['spin'] as Map)['jackpotTriggered'] == true,
      capped = (source['spin'] as Map)['capped'] == true {
    if (grid.length != 9 ||
        grid.any((symbol) => !fruitJackpotSymbolIds.contains(symbol))) {
      throw const FormatException('Invalid YUMMY result');
    }
  }
}

class FruitJackpotReplay {
  final FruitJackpotRound result;
  int revealedReels = 0;
  FruitJackpotReplay(this.result);
  void stop() => revealedReels = 9;
}

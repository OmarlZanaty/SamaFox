import 'dart:math';

const yummyPaylines = <List<int>>[
  [1, 1, 1, 1, 1],
  [0, 0, 0, 0, 0],
  [2, 2, 2, 2, 2],
  [0, 1, 2, 1, 0],
  [2, 1, 0, 1, 2],
  [0, 0, 1, 0, 0],
  [2, 2, 1, 2, 2],
  [1, 0, 1, 2, 1],
  [1, 2, 1, 0, 1],
];
const yummyPaytable = <String, List<int>>{
  'strawberry': [2, 8, 20],
  'cherry': [3, 10, 30],
  'orange': [4, 12, 40],
  'lemon': [5, 15, 50],
  'watermelon': [8, 25, 80],
  'grapes': [10, 35, 100],
  'candy': [12, 50, 150],
  'diamond': [20, 100, 500],
  'wild': [25, 150, 1000],
};
const yummySymbolIds = [
  'strawberry',
  'cherry',
  'orange',
  'lemon',
  'watermelon',
  'grapes',
  'candy',
  'diamond',
  'wild',
  'bonus',
  'jackpot',
];

int yummyTotalBet(int betPerLine, int lines) {
  if (betPerLine <= 0 || lines < 1 || lines > 9) {
    throw ArgumentError('Invalid bet or lines');
  }
  return betPerLine * lines;
}

bool yummyCanSpin(int balance, int betPerLine, int lines) =>
    balance >= yummyTotalBet(betPerLine, lines);

bool yummyHasBonus(List<String> grid) =>
    grid.where((symbol) => symbol == 'bonus').length >= 3;

class YummyLineWin {
  final int line, count, amount;
  final String symbol;
  final List<int> cells;
  const YummyLineWin(
    this.line,
    this.symbol,
    this.count,
    this.cells,
    this.amount,
  );
  factory YummyLineWin.fromJson(Map<String, dynamic> json) => YummyLineWin(
        (json['line'] as num).toInt(),
        json['symbol'] as String,
        (json['count'] as num).toInt(),
        List<int>.from(json['cells'] as List),
        (json['amount'] as num).toInt(),
      );
}

List<YummyLineWin> yummyEvaluateLines(
  List<String> grid,
  int betPerLine,
  int activeLines,
) {
  yummyTotalBet(betPerLine, activeLines);
  if (grid.length != 15 ||
      grid.any((symbol) => !yummySymbolIds.contains(symbol))) {
    throw ArgumentError('Invalid board');
  }
  final wins = <YummyLineWin>[];
  for (var line = 0; line < activeLines; line++) {
    final cells =
        List.generate(5, (reel) => yummyPaylines[line][reel] * 5 + reel);
    YummyLineWin? best;
    for (final entry in yummyPaytable.entries) {
      var count = 0;
      for (final cell in cells) {
        if (grid[cell] == entry.key ||
            (entry.key != 'wild' && grid[cell] == 'wild')) {
          count++;
        } else {
          break;
        }
      }
      if (count < 3) continue;
      final amount = entry.value[count - 3] * betPerLine;
      if (best == null || amount > best.amount) {
        best = YummyLineWin(
          line,
          entry.key,
          count,
          cells.take(count).toList(),
          amount,
        );
      }
    }
    final crowns = cells.takeWhile((cell) => grid[cell] == 'jackpot').length;
    if (crowns >= 3) {
      best = YummyLineWin(
        line,
        'jackpot',
        crowns,
        cells.take(crowns).toList(),
        1000 * betPerLine,
      );
    }
    if (best != null) wins.add(best);
  }
  return wins;
}

List<String> yummyDecorativeGrid(Random random) =>
    List.generate(15, (_) => yummySymbolIds[random.nextInt(8)]);

class YummyRound {
  final String id, serverSeedHash, clientSeed;
  final DateTime at;
  final List<String> grid;
  final List<YummyLineWin> wins;
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
  YummyRound.fromJson(Map<String, dynamic> source)
      : json = Map.unmodifiable(source),
        id = source['id']?.toString() ?? '',
        at =
            DateTime.tryParse(source['at']?.toString() ?? '') ?? DateTime.now(),
        serverSeedHash = source['serverSeedHash'] as String? ?? '',
        clientSeed = source['clientSeed'] as String? ?? '',
        nonce = (source['nonce'] as num?)?.toInt() ?? 0,
        balance = (source['balance'] as num).toInt(),
        grid = List.unmodifiable(
          List<String>.from((source['spin'] as Map)['grid'] as List),
        ),
        wins = List.unmodifiable(
          ((source['spin'] as Map)['wins'] as List).map(
            (win) =>
                YummyLineWin.fromJson(Map<String, dynamic>.from(win as Map)),
          ),
        ),
        betPerLine = ((source['spin'] as Map)['betPerLine'] as num).toInt(),
        activeLines = ((source['spin'] as Map)['activeLines'] as num).toInt(),
        totalBet = ((source['spin'] as Map)['totalBet'] as num).toInt(),
        totalPrize = ((source['spin'] as Map)['totalPrize'] as num).toInt(),
        requestedPrize = (((source['spin'] as Map)['requestedPrize'] ??
                (source['spin'] as Map)['totalPrize']) as num)
            .toInt(),
        bonusMultiplier =
            ((source['spin'] as Map)['bonusMultiplier'] as num?)?.toInt() ?? 0,
        bonusPrize =
            ((source['spin'] as Map)['bonusPrize'] as num?)?.toInt() ?? 0,
        bonusTriggered = (source['spin'] as Map)['bonusTriggered'] == true,
        jackpotTriggered = (source['spin'] as Map)['jackpotTriggered'] == true,
        capped = (source['spin'] as Map)['capped'] == true {
    if (grid.length != 15 ||
        grid.any((symbol) => !yummySymbolIds.contains(symbol))) {
      throw const FormatException('Invalid YUMMY result');
    }
  }
}

class YummyReplay {
  final YummyRound result;
  int revealedReels = 0;
  YummyReplay(this.result);
  void stop() => revealedReels = 5;
}

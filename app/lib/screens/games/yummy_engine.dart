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
  'strawberry': [6, 15, 40],
  'cherry': [6, 20, 60],
  'orange': [8, 25, 80],
  'lemon': [10, 30, 100],
  'watermelon': [15, 50, 150],
  'grapes': [20, 75, 200],
  'candy': [25, 100, 300],
  'diamond': [40, 200, 750],
  'wild': [50, 250, 1000],
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

/// Defaults matching math v2; the server layout overrides them when present.
const yummyTumbleMultipliers = [1, 2, 3, 5];
const yummyExpandingReels = [1, 2, 3];
const yummyFreeSpinAwards = {
  3: [8, 2],
  4: [10, 3],
  5: [12, 5],
};

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

/// True when the reels still spinning could complete a feature: two BONUS on
/// the landed reels, or a crown on every landed reel so far (crowns pay from
/// the left). Drives the anticipation slow-down only, never an outcome.
bool yummyAnticipates(List<String> grid, int landedReels) {
  if (landedReels < 2 || landedReels >= 5) return false;
  var bonus = 0;
  for (var index = 0; index < 15; index++) {
    if (index % 5 < landedReels && grid[index] == 'bonus') bonus++;
  }
  if (bonus >= 2 && bonus < 5) return true;
  for (var reel = 0; reel < landedReels; reel++) {
    if (![0, 1, 2].any((row) => grid[row * 5 + reel] == 'jackpot')) {
      return false;
    }
  }
  return true;
}

/// Where each symbol of the next board comes from when [removed] pop: a row
/// of the current board (it fell) or a negative row above it (it dropped in).
/// Mirrors the server's collapse so the client can animate between two boards.
List<int> yummyFallSources(List<int> removed) {
  final gone = removed.toSet();
  final sources = List<int>.filled(15, 0);
  for (var reel = 0; reel < 5; reel++) {
    final kept = [
      for (var row = 0; row < 3; row++)
        if (!gone.contains(row * 5 + reel)) row,
    ];
    final fresh = 3 - kept.length;
    for (var row = 0; row < 3; row++) {
      sources[row * 5 + reel] = row < fresh ? row - fresh : kept[row - fresh];
    }
  }
  return sources;
}

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

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

List<String> _board(Object? value) {
  final grid = List<String>.from(value as List);
  if (grid.length != 15 ||
      grid.any((symbol) => !yummySymbolIds.contains(symbol))) {
    throw const FormatException('Invalid YUMMY result');
  }
  return List.unmodifiable(grid);
}

List<YummyLineWin> _wins(Object? value) => List.unmodifiable(
      (value as List? ?? const []).map(
        (win) => YummyLineWin.fromJson(Map<String, dynamic>.from(win as Map)),
      ),
    );

/// One scoring step of a spin: the board it was scored on, what it paid and
/// the cells that pop before the next step (empty on the last one).
class YummyTumble {
  final List<String> grid;
  final List<YummyLineWin> wins;
  final int multiplier, prize;
  final List<int> removed;
  const YummyTumble(
    this.grid,
    this.wins,
    this.multiplier,
    this.prize,
    this.removed,
  );
  factory YummyTumble.fromJson(Map<String, dynamic> json) => YummyTumble(
        _board(json['grid']),
        _wins(json['wins']),
        _int(json['multiplier'], 1),
        _int(json['prize']),
        List.unmodifiable(
          (json['removed'] as List? ?? const []).map((n) => (n as num).toInt()),
        ),
      );
}

List<YummyTumble> _tumbles(Object? value) => List.unmodifiable(
      (value as List? ?? const []).map(
        (t) => YummyTumble.fromJson(Map<String, dynamic>.from(t as Map)),
      ),
    );

class YummyFreeSpin {
  /// The board as it landed, before its WILDs expanded.
  final List<String> landed;
  final List<int> expandedReels;
  final List<YummyTumble> tumbles;
  final int prize;
  const YummyFreeSpin(
    this.landed,
    this.expandedReels,
    this.tumbles,
    this.prize,
  );
  factory YummyFreeSpin.fromJson(Map<String, dynamic> json) {
    final tumbles = _tumbles(json['tumbles']);
    if (tumbles.isEmpty) throw const FormatException('Empty free spin');
    final expanded = List<int>.unmodifiable(
      (json['expandedReels'] as List? ?? const [])
          .map((n) => (n as num).toInt()),
    );
    return YummyFreeSpin(
      // Without the pre-expansion board, land on the expanded one directly.
      json['landed'] is List ? _board(json['landed']) : tumbles.first.grid,
      json['landed'] is List ? expanded : const [],
      tumbles,
      _int(json['prize']),
    );
  }
}

class YummyFreeSpins {
  final int count, multiplier, trigger, prize;
  final List<YummyFreeSpin> spins;
  const YummyFreeSpins(
    this.count,
    this.multiplier,
    this.trigger,
    this.spins,
    this.prize,
  );
  static YummyFreeSpins? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final spins = List<YummyFreeSpin>.unmodifiable(
      (json['spins'] as List? ?? const []).map(
        (s) => YummyFreeSpin.fromJson(Map<String, dynamic>.from(s as Map)),
      ),
    );
    if (spins.isEmpty) return null;
    return YummyFreeSpins(
      _int(json['count'], spins.length),
      _int(json['multiplier'], 1),
      _int(json['trigger'], 3),
      spins,
      _int(json['prize'], spins.fold<int>(0, (sum, s) => sum + s.prize)),
    );
  }
}

/// A settled round as the server sent it. Tolerant of v1 rounds still in
/// history: they have no tumbles or free spins, so one step is synthesised
/// from the board and its wins, and the old instant bonus stays readable.
class YummyRound {
  final String id, serverSeedHash, clientSeed;
  final DateTime at;
  final List<String> grid;
  final List<YummyLineWin> wins;
  final List<YummyTumble> tumbles;
  final YummyFreeSpins? freeSpins;
  final int betPerLine,
      activeLines,
      totalBet,
      totalPrize,
      requestedPrize,
      basePrize,
      balance,
      nonce,
      mathVersion,
      bonusMultiplier,
      bonusPrize;
  final bool bonusTriggered, jackpotTriggered, capped;
  final Map<String, dynamic> json;

  factory YummyRound.fromJson(Map<String, dynamic> source) {
    final spin = Map<String, dynamic>.from(source['spin'] as Map);
    final grid = _board(spin['grid']);
    final wins = _wins(spin['wins']);
    var tumbles = _tumbles(spin['tumbles']);
    if (tumbles.isEmpty || !_sameBoard(tumbles.first.grid, grid)) {
      tumbles = List.unmodifiable([
        YummyTumble(
          grid,
          wins,
          1,
          wins.fold<int>(0, (sum, win) => sum + win.amount),
          const [],
        ),
      ]);
    }
    final totalPrize = (spin['totalPrize'] as num).toInt();
    return YummyRound._(
      json: Map.unmodifiable(source),
      id: source['id']?.toString() ?? '',
      at: DateTime.tryParse(source['at']?.toString() ?? '') ?? DateTime.now(),
      serverSeedHash: source['serverSeedHash'] as String? ?? '',
      clientSeed: source['clientSeed'] as String? ?? '',
      nonce: _int(source['nonce']),
      balance: (source['balance'] as num).toInt(),
      grid: grid,
      wins: wins,
      tumbles: tumbles,
      freeSpins: YummyFreeSpins.tryParse(spin['freeSpins']),
      betPerLine: (spin['betPerLine'] as num).toInt(),
      activeLines: (spin['activeLines'] as num).toInt(),
      totalBet: (spin['totalBet'] as num).toInt(),
      totalPrize: totalPrize,
      requestedPrize: _int(spin['requestedPrize'], totalPrize),
      basePrize: _int(
        spin['basePrize'],
        tumbles.fold<int>(0, (sum, t) => sum + t.prize),
      ),
      mathVersion: _int(spin['mathVersion'], 1),
      bonusMultiplier: _int(spin['bonusMultiplier']),
      bonusPrize: _int(spin['bonusPrize']),
      bonusTriggered: spin['bonusTriggered'] == true,
      jackpotTriggered: spin['jackpotTriggered'] == true,
      capped: spin['capped'] == true,
    );
  }

  YummyRound._({
    required this.json,
    required this.id,
    required this.at,
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
    required this.balance,
    required this.grid,
    required this.wins,
    required this.tumbles,
    required this.freeSpins,
    required this.betPerLine,
    required this.activeLines,
    required this.totalBet,
    required this.totalPrize,
    required this.requestedPrize,
    required this.basePrize,
    required this.mathVersion,
    required this.bonusMultiplier,
    required this.bonusPrize,
    required this.bonusTriggered,
    required this.jackpotTriggered,
    required this.capped,
  });

  static bool _sameBoard(List<String> a, List<String> b) {
    for (var i = 0; i < 15; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The board left on screen after the last tumble.
  List<String> get finalGrid => tumbles.last.grid;

  /// Wins of the last paying step, for the chips under the machine.
  List<YummyLineWin> get allWins => [for (final t in tumbles) ...t.wins];

  /// Paying steps in the base game (2+ means at least one tumble paid).
  int get tumbleChain => tumbles.where((t) => t.prize > 0).length;

  /// What the base game pays on screen; caps only ever shrink the total.
  int get baseShown => min(basePrize, totalPrize);

  /// Free-spin winnings on screen (zero for v1 rounds).
  int get freeSpinsShown => freeSpins == null ? 0 : totalPrize - baseShown;
}

class YummyReplay {
  final YummyRound result;
  int revealedReels = 0;
  YummyReplay(this.result);
  void stop() => revealedReels = 5;
}

import 'dart:math';

/// Pure client side of عجلة الفواكه (FRUIT WHEEL): models and geometry.
///
/// The server rolls every round; this file only describes what it returned and
/// where the wheel must stop to show it.

const fruitCards = ['watermelon', 'sevens', 'plum'];
const fruitMultipliers = {'watermelon': 2, 'sevens': 3, 'plum': 2};

/// Ten equal segments, clockwise from the pointer. Mirrors fruitWheel.math.ts.
const fruitSegments = [
  'watermelon', 'plum', 'watermelon', 'plum', 'sevens', //
  'watermelon', 'plum', 'watermelon', 'plum', 'bonus',
];
const fruitChips = [100, 1000, 10000, 100000];
const fruitTickerLength = 12;

/// Spin feel: 5–8 full turns over 3–4.5 s, settling with this curve.
const fruitMinTurns = 5, fruitMaxTurns = 8;
const fruitMinSpinMs = 3000, fruitMaxSpinMs = 4500;

double get fruitSegmentAngle => 2 * pi / fruitSegments.length;

/// Wheel rotation (radians, clockwise) that puts [offset] (0–1) of [segment]
/// under the top pointer, at least [turns] whole turns past [from].
double fruitStopAngle(double from, int segment, double offset, int turns) {
  final aim = -(segment + offset) * fruitSegmentAngle;
  final delta = (aim - from) % (2 * pi);
  return from + turns * 2 * pi + delta;
}

/// The segment under the pointer when the wheel is turned by [angle].
int fruitSegmentAt(double angle) {
  final a = (-angle) % (2 * pi);
  return (a / fruitSegmentAngle).floor() % fruitSegments.length;
}

/// Coins on each card for the next round.
class FruitBets {
  final Map<String, int> _coins;
  FruitBets([Map<String, int>? coins])
      : _coins = {for (final c in fruitCards) c: coins?[c] ?? 0};
  int operator [](String card) => _coins[card] ?? 0;
  int get total => _coins.values.fold(0, (a, b) => a + b);
  bool get isEmpty => total == 0;

  /// Adds [chip] to [card] unless the table would pass [maxBet].
  bool add(String card, int chip, int maxBet) {
    if (!fruitCards.contains(card) || total + chip > maxBet) return false;
    _coins[card] = this[card] + chip;
    return true;
  }

  void clear() => _coins.updateAll((_, __) => 0);
  FruitBets copy() => FruitBets(Map.of(_coins));
  Map<String, int> get json => Map.of(_coins);
  static FruitBets? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final bets = FruitBets({
      for (final c in fruitCards)
        c: raw[c] is num ? (raw[c] as num).toInt() : 0,
    });
    return bets.isEmpty ? null : bets;
  }
}

/// One settled round as the server returned it.
class FruitRound {
  final String id;
  final DateTime at;
  final int round, balance, totalBet, totalPrize, cardPrize, bonusPrize;
  final FruitBets bets;
  final String outcome;
  final String? winner;
  final int segment;
  final double offset;
  final List<int>? orbs;
  final String serverSeedHash, clientSeed;
  final int nonce;
  final Map<String, dynamic> json;

  FruitRound._(this.json)
      : id = json['id']?.toString() ?? '',
        at = DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
        round = _int(json['round']),
        balance = _int(json['balance']),
        totalBet = _int(_spin(json)['totalBet']),
        totalPrize = _int(_spin(json)['totalPrize']),
        cardPrize = _int(_spin(json)['cardPrize']),
        bonusPrize = _int(_spin(json)['bonusPrize']),
        bets = FruitBets.fromJson(_spin(json)['bets']) ?? FruitBets(),
        outcome = _spin(json)['outcome']?.toString() ?? 'watermelon',
        winner = _spin(json)['winner']?.toString(),
        segment = _int(_spin(json)['segment']) % fruitSegments.length,
        offset = ((_spin(json)['offset'] as num?)?.toDouble() ?? .5)
            .clamp(0.0, 1.0),
        orbs = (_spin(json)['orbs'] as List?)
            ?.map((v) => (v as num).toInt())
            .toList(),
        serverSeedHash = json['serverSeedHash']?.toString() ?? '',
        clientSeed = json['clientSeed']?.toString() ?? '',
        nonce = _int(json['nonce']);

  factory FruitRound.fromJson(Map<String, dynamic> json) =>
      FruitRound._(Map<String, dynamic>.from(json));

  bool get isBonus => outcome == 'bonus';
  int get net => totalPrize - totalBet;

  /// What [card] won this round (0 when it lost or had no chips).
  int wonOn(String card) => winner == card ? totalPrize - bonusPrize : 0;

  static Map<String, dynamic> _spin(Map<String, dynamic> json) =>
      json['spin'] is Map ? Map<String, dynamic>.from(json['spin'] as Map) : {};
  static int _int(Object? v) => v is num ? v.toInt() : 0;
}

/// Newest outcome first, at most [fruitTickerLength].
List<String> fruitPushTicker(List<String> ticker, String outcome) =>
    [outcome, ...ticker].take(fruitTickerLength).toList();

/// "62000" → "62K", "1500000" → "1.5M".
String fruitCompact(int value) {
  String trim(double v) =>
      v >= 100 || v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (value >= 1000000) return '${trim(value / 1000000)}M';
  if (value >= 10000) return '${trim(value / 1000)}K';
  return '$value';
}

/// Spin length for a fresh round: random turns and duration within the feel.
({int turns, int ms}) fruitSpinPlan(Random random) => (
      turns: fruitMinTurns + random.nextInt(fruitMaxTurns - fruitMinTurns + 1),
      ms: fruitMinSpinMs + random.nextInt(fruitMaxSpinMs - fruitMinSpinMs + 1),
    );

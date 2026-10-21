import 'dart:math';

/// Pure client side of عجلة الفواكه (FRUIT WHEEL): models and geometry.
///
/// The server rolls every round; this file only describes what it returned and
/// where the wheel must stop to show it.

const fruitCards = ['watermelon', 'sevens', 'plum'];
const Map<String, double> fruitMultipliers = {
  'watermelon': 2,
  'sevens': 8,
  'plum': 2,
};

/// Prefer the table config, with defaults for absent or invalid card values.
Map<String, double> fruitTableMultipliers(Object? raw) => {
      for (final card in fruitCards)
        card: raw is Map &&
                raw[card] is num &&
                (raw[card] as num).isFinite &&
                (raw[card] as num) > 0
            ? (raw[card] as num).toDouble()
            : fruitMultipliers[card]!,
    };

String fruitMultiplierLabel(double value) =>
    '×${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString()}';

/// Additive server outcomes, with support for installed servers' single result.
List<String> fruitWinningCards(Map<String, dynamic> j) {
  if (j['result'] == 'crown') return [];
  final cards = (j['results'] is List ? j['results'] as List : const [])
      .whereType<String>()
      .where(fruitCards.contains)
      .toSet()
      .toList();
  if (cards.isNotEmpty) return cards;
  return fruitCards.contains(j['result']) ? [j['result'] as String] : [];
}

/// History includes the no-win crown without treating it as a winning card.
List<String> fruitHistoryOutcomes(Map<String, dynamic> j) =>
    j['result'] == 'crown' ? ['crown'] : fruitWinningCards(j);

/// Ten equal segments matching the server, including the crown at index 9.
const fruitSegments = [
  'watermelon', 'plum', 'watermelon', 'plum', 'sevens', //
  'watermelon', 'plum', 'watermelon', 'plum', 'crown',
];
const fruitChips = [100, 1000, 10000, 100000];
const fruitTickerLength = 10;

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

  /// Adds [chip] to [card] subject to a per-card limit and at most two cards.
  bool add(String card, int chip, int maxBet) {
    if (!fruitCards.contains(card) ||
        chip <= 0 ||
        this[card] + chip > maxBet ||
        (this[card] == 0 && _coins.values.where((v) => v > 0).length >= 2)) {
      return false;
    }
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

/// Newest outcome first, at most [fruitTickerLength].
List<String> fruitPushTicker(List<String> ticker, String outcome) =>
    [outcome, ...ticker]
        .where(fruitSegments.contains)
        .take(fruitTickerLength)
        .toList();

/// "62000" → "62K", "1500000" → "1.5M".
String fruitCompact(int value) {
  String trim(double v) => v >= 100 || v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);
  if (value >= 1000000) return '${trim(value / 1000000)}M';
  if (value >= 10000) return '${trim(value / 1000)}K';
  return '$value';
}

class FruitWheelState {
  final int segment;
  final double offset;
  final int round, msLeft, totalBet, playerCount;
  final String phase, seedHash, tableId;
  final String? seed;
  final String? result;
  final List<String> results;
  final String? bonus;
  final int? roundsToBonus;
  final int bonusEveryRounds;
  final bool bonusEnabled;
  final List<List<String>> historyResults;
  final Map<String, int> totals;
  final List<Map<String, dynamic>> players, winners;
  final List<String> history;
  final Map<String, int> myStakes;
  final List<Map<String, dynamic>> myChips;
  final int myStaked, myPayout;
  final DateTime receivedAt;

  FruitWheelState.fromJson(Map<String, dynamic> j)
      : tableId = j['tableId']?.toString() ?? '',
        segment = _int(j['segment']).clamp(0, fruitSegments.length - 1),
        offset = ((j['offset'] as num?)?.toDouble() ?? .5).clamp(.15, .85),
        round = _int(j['round']),
        msLeft = _int(j['msLeft']),
        totalBet = _int(j['totalBet']),
        playerCount = _int(j['playerCount']),
        phase = j['phase']?.toString() ?? 'betting',
        seedHash = j['seedHash']?.toString() ?? '',
        seed = j['seed']?.toString(),
        result =
            fruitSegments.contains(j['result']) ? j['result'] as String : null,
        results = fruitWinningCards(j),
        bonus = ['double', 'triple'].contains(j['bonus'])
            ? j['bonus'] as String : null,
        roundsToBonus = j['roundsToBonus'] is num
            ? _int(j['roundsToBonus']).clamp(0, 1000) : null,
        bonusEveryRounds = j['bonusEveryRounds'] is num
            ? _int(j['bonusEveryRounds']) : 20,
        bonusEnabled = j['bonusEnabled'] != false,
        historyResults = j['historyRows'] is List
            ? _maps(j['historyRows'])
                .map(fruitHistoryOutcomes)
                .where((cards) => cards.isNotEmpty)
                .toList()
            : (j['history'] is List ? j['history'] as List : const [])
                .whereType<String>()
                .where(fruitSegments.contains)
                .map((card) => [card])
                .toList(),
        totals = _ints(j['totals']),
        players = _maps(j['players']),
        winners = _maps(j['winners']),
        history = (j['history'] is List ? j['history'] as List : const [])
            .whereType<String>()
            .where(fruitSegments.contains)
            .toList(),
        myStakes = _ints(_me(j)?['stakes']),
        myChips = _maps(_me(j)?['chipList']),
        myStaked = _int(_me(j)?['staked']),
        myPayout = _int(_me(j)?['payout']),
        receivedAt = DateTime.now();

  bool get betting => phase == 'betting';
  Duration get left {
    final d =
        Duration(milliseconds: msLeft) - DateTime.now().difference(receivedAt);
    return d.isNegative ? Duration.zero : d;
  }

  static Map? _me(Map<String, dynamic> j) =>
      j['me'] is Map ? j['me'] as Map : null;
  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static Map<String, int> _ints(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            e.key.toString(): (e.value is num ? (e.value as num).toInt() : 0),
        }
      : {};
  static List<Map<String, dynamic>> _maps(Object? v) =>
      (v is List ? v : const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
}

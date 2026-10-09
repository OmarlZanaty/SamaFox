import 'dart:math';
import 'dart:ui';

/// Pure client side of الروليت: the wheel, bet keys and table geometry.
/// Mirrors backend/src/services/roulette.math.ts; the server decides every
/// result and every payout, the client only draws them.

const rouletteWheel = [
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, //
  24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
];
const rouletteReds = {
  1,
  3,
  5,
  7,
  9,
  12,
  14,
  16,
  18,
  19,
  21,
  23,
  25,
  27,
  30,
  32,
  34,
  36,
};
const rouletteChips = [100, 500, 1000, 5000, 10000];
const rouletteHistoryLength = 12;

enum RouletteColor { green, red, black }

RouletteColor rouletteColor(int n) => n == 0
    ? RouletteColor.green
    : rouletteReds.contains(n)
        ? RouletteColor.red
        : RouletteColor.black;

/// Total return per coin, stake included, by bet type (tenths, like the server).
const _tenths = {
  'straight': 260, 'split': 130, 'street': 86, 'corner': 65, 'sixLine': 43,
  'firstFour': 65, //
  'even-money': 14, 'dozen': 21, 'column': 21,
};
const rouletteOutside = ['low', 'even', 'red', 'black', 'odd', 'high'];
const rouletteDozens = ['dozen1', 'dozen2', 'dozen3'];
const rouletteColumns = ['column1', 'column2', 'column3'];

List<int> _range(int from, int to) => [for (var i = from; i <= to; i++) i];

class RouletteBet {
  final String key, type;
  final List<int> numbers;
  const RouletteBet(this.key, this.type, this.numbers);
  double get multiplier => _tenths[_family]! / 10;
  int get tenths => _tenths[_family]!;
  String get _family => switch (type) {
        'red' || 'black' || 'odd' || 'even' || 'low' || 'high' => 'even-money',
        'dozen1' || 'dozen2' || 'dozen3' => 'dozen',
        'column1' || 'column2' || 'column3' => 'column',
        _ => type,
      };
}

/// Parses a bet key the way the server does; null for anything off the table.
RouletteBet? rouletteBet(String key) {
  final outside = <String, List<int>>{
    'red': _range(1, 36).where(rouletteReds.contains).toList(),
    'black': _range(1, 36).where((n) => !rouletteReds.contains(n)).toList(),
    'odd': _range(1, 36).where((n) => n.isOdd).toList(),
    'even': _range(1, 36).where((n) => n.isEven).toList(),
    'low': _range(1, 18),
    'high': _range(19, 36),
    'dozen1': _range(1, 12),
    'dozen2': _range(13, 24),
    'dozen3': _range(25, 36),
    'column1': _range(1, 36).where((n) => n % 3 == 1).toList(),
    'column2': _range(1, 36).where((n) => n % 3 == 2).toList(),
    'column3': _range(1, 36).where((n) => n % 3 == 0).toList(),
  };
  if (outside.containsKey(key)) return RouletteBet(key, key, outside[key]!);
  if (key == 'ff') return RouletteBet(key, 'firstFour', const [0, 1, 2, 3]);
  final parts = key.split(':');
  if (parts.length != 2) return null;
  final nums = parts[1].split('-').map(int.tryParse).toList();
  if (nums.any((n) => n == null || n < 0 || n > 36)) return null;
  final n = nums.cast<int>();
  final sorted = [...n]..sort();
  if (sorted.join('-') != parts[1]) return null;
  switch (parts[0]) {
    case 'n':
      return n.length == 1 ? RouletteBet(key, 'straight', n) : null;
    case 'split':
      if (n.length != 2) return null;
      final (x, y) = (sorted[0], sorted[1]);
      final ok =
          x == 0 ? y >= 1 && y <= 3 : (y == x + 1 && x % 3 != 0) || y == x + 3;
      return ok ? RouletteBet(key, 'split', sorted) : null;
    case 'street':
      return n.length == 1 && n[0] >= 1 && n[0] % 3 == 1
          ? RouletteBet(key, 'street', [n[0], n[0] + 1, n[0] + 2])
          : null;
    case 'six':
      return n.length == 1 && n[0] >= 1 && n[0] <= 31 && n[0] % 3 == 1
          ? RouletteBet(key, 'sixLine', _range(n[0], n[0] + 5))
          : null;
    case 'corner':
      if (n.length != 4) return null;
      final x = sorted[0];
      final ok = x >= 1 &&
          x % 3 != 0 &&
          x <= 32 &&
          sorted.join('-') == [x, x + 1, x + 3, x + 4].join('-');
      return ok ? RouletteBet(key, 'corner', sorted) : null;
  }
  return null;
}

/// What [stakes] return if the ball lands on [result] (stake included).
int roulettePayout(Map<String, int> stakes, int result) {
  var tenths = 0;
  stakes.forEach((key, amount) {
    final bet = rouletteBet(key);
    if (bet != null && amount > 0 && bet.numbers.contains(result)) {
      tenths += amount * bet.tenths;
    }
  });
  return tenths ~/ 10;
}

/// Bets on [stakes] that [result] wins, for highlighting the table.
Set<String> rouletteWinningKeys(Map<String, int> stakes, int result) => {
      for (final key in stakes.keys)
        if (rouletteBet(key)?.numbers.contains(result) ?? false) key,
    };

// ── Table: 12 rows of three (1-2-3 … 34-35-36), zero above ──────────────────
const rouletteRows = 12;
int rouletteNumberAt(int row, int col) => row * 3 + col + 1;

/// The bet a tap at ([fx], [fy]) inside cell ([row], [col]) means. Taps near
/// a shared edge back the split, near a corner the corner; the outer (left)
/// edge backs the street, and between two streets the six line.
String rouletteKeyAt(int row, int col, double fx, double fy,
    {double edge = .22,}) {
  final n = rouletteNumberAt(row, col);
  final left = fx < edge,
      right = fx > 1 - edge,
      top = fy < edge,
      bottom = fy > 1 - edge;
  if (left && col == 0) {
    if (top && row == 0) return 'ff';
    if (bottom && row < rouletteRows - 1) return 'six:${row * 3 + 1}';
    if (top && row > 0) return 'six:${(row - 1) * 3 + 1}';
    return 'street:${row * 3 + 1}';
  }
  final dx = right && col < 2
      ? 1
      : left && col > 0
          ? -1
          : 0;
  final dy = bottom && row < rouletteRows - 1
      ? 1
      : top && row > 0
          ? -1
          : 0;
  if (dx != 0 && dy != 0) {
    final base = rouletteNumberAt(min(row, row + dy), min(col, col + dx));
    return 'corner:$base-${base + 1}-${base + 3}-${base + 4}';
  }
  if (dx != 0) {
    final a = min(n, n + dx);
    return 'split:$a-${a + 1}';
  }
  if (dy != 0) {
    final a = min(n, n + 3 * dy);
    return 'split:$a-${a + 3}';
  }
  if (top && row == 0) return 'split:0-$n';
  return 'n:$n';
}

/// Where a chip on [key] sits, in units of number cells: x across the three
/// columns (0–3), y down the rows (0–12), zero above at y < 0. Outside bets
/// return null; their own buttons draw their chips.
Offset? rouletteAnchor(String key) {
  final bet = rouletteBet(key);
  if (bet == null) return null;
  Offset center(int n) => n == 0
      ? const Offset(1.5, -.5)
      : Offset((n - 1) % 3 + .5, (n - 1) ~/ 3 + .5);
  switch (bet.type) {
    case 'straight':
    case 'split':
    case 'corner':
      final points = bet.numbers.map(center).toList();
      if (bet.type == 'split' && bet.numbers.first == 0) {
        // A zero split sits on the line under zero, above its number.
        final c = center(bet.numbers[1]);
        return Offset(c.dx, 0);
      }
      return points.reduce((a, b) => a + b) / points.length.toDouble();
    case 'street':
      return Offset(0, (bet.numbers.first - 1) ~/ 3 + .5);
    case 'sixLine':
      return Offset(0, (bet.numbers.first - 1) ~/ 3 + 1.0);
    case 'firstFour':
      return Offset.zero;
  }
  return null;
}

// ── Wheel and ball motion ───────────────────────────────────────────────────
double get roulettePocketAngle => 2 * pi / rouletteWheel.length;

/// Angle (clockwise from the top, wheel coordinates) of [number]'s pocket centre.
double roulettePocketCenter(int number) =>
    (rouletteWheel.indexOf(number) + .5) * roulettePocketAngle;

/// Where the wheel and ball are [u] (0–1) of the way through a spin that
/// lands on [result]. The wheel turns clockwise and slows; the ball runs the
/// other way on the outer track, drops in over the last third, and ends in
/// the pocket — the result was decided before the spin started.
({double wheel, double ball, double radius}) rouletteSpinFrame({
  required double u,
  required double wheelStart,
  required int result,
  int wheelTurns = 1,
  int ballTurns = 5,
}) {
  final t = u.clamp(0.0, 1.0);
  double ease(double x) => 1 - pow(1 - x, 3).toDouble();
  final wheel = wheelStart + wheelTurns * 2 * pi * ease(t);
  final wheelEnd = wheelStart + wheelTurns * 2 * pi;
  final ballEnd = wheelEnd + roulettePocketCenter(result);
  final ball = ballEnd + ballTurns * 2 * pi * (1 - ease(t));
  // 1 = outer track, 0 = resting in the pocket ring; a small bounce on the way in.
  double radius;
  if (t < .62) {
    radius = 1;
  } else if (t < .9) {
    final k = (t - .62) / .28;
    radius = 1 - k + .12 * sin(k * pi * 3) * (1 - k);
  } else {
    radius = 0;
  }
  return (wheel: wheel, ball: ball, radius: radius.clamp(0.0, 1.0));
}

// ── Shared round state from the server ──────────────────────────────────────
class RouletteState {
  final int round, msLeft, totalBet, playerCount;
  final String phase, seedHash;
  final String? seed;
  final int? result;
  final Map<String, int> totals;
  final List<Map<String, dynamic>> players, winners;
  final List<int> history;
  final Map<String, int> myStakes;
  final int myStaked, myPayout;
  final DateTime receivedAt;

  RouletteState.fromJson(Map<String, dynamic> j)
      : round = _int(j['round']),
        msLeft = _int(j['msLeft']),
        totalBet = _int(j['totalBet']),
        playerCount = _int(j['playerCount']),
        phase = j['phase']?.toString() ?? 'betting',
        seedHash = j['seedHash']?.toString() ?? '',
        seed = j['seed']?.toString(),
        result = j['result'] is num ? (j['result'] as num).toInt() : null,
        totals = _ints(j['totals']),
        players = _maps(j['players']),
        winners = _maps(j['winners']),
        history = (j['history'] as List? ?? const [])
            .whereType<num>()
            .map((v) => v.toInt())
            .toList(),
        myStakes = _ints(_me(j)?['stakes']),
        myStaked = _int(_me(j)?['staked']),
        myPayout = _int(_me(j)?['payout']),
        receivedAt = DateTime.now();

  bool get betting => phase == 'betting';
  Duration get left {
    final d =
        Duration(milliseconds: msLeft) - DateTime.now().difference(receivedAt);
    return d.isNegative ? Duration.zero : d;
  }

  static Map? _me(Map<String, dynamic> j) => j['me'] is Map ? j['me'] as Map : null;
  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static Map<String, int> _ints(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            e.key.toString(): (e.value is num ? (e.value as num).toInt() : 0),
        }
      : {};
  static List<Map<String, dynamic>> _maps(Object? v) => (v as List? ?? const [])
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

/// "383000" → "383K"; small values stay exact.
String rouletteCompact(int v) {
  String trim(double d) => d == d.roundToDouble() || d >= 100
      ? d.toStringAsFixed(0)
      : d.toStringAsFixed(1);
  if (v >= 1000000) return '${trim(v / 1000000)}M';
  if (v >= 1000) return '${trim(v / 1000)}K';
  return '$v';
}

import 'dart:math';
import 'dart:ui';

/// Mirrors carWheel.math.ts. The server decides results and payouts; the
/// client uses this table only for drawing, hit testing and the paytable.
class CarWheelSegment {
  final String key, name;
  final int multiplier, weight;
  const CarWheelSegment(this.key, this.name, this.multiplier, this.weight);
  double get chance => weight / 8942;
}

const carWheelSegments = [
  CarWheelSegment('aurelia', 'Aurelia', 8, 825),
  CarWheelSegment('bavaro', 'Bavaro', 10, 660),
  CarWheelSegment('stellaro', 'Stellaro', 66, 100),
  CarWheelSegment('ferrarion', 'Ferrarion', 50, 132),
  CarWheelSegment('lambrex', 'Lambrex', 88, 75),
  CarWheelSegment('voltara', 'Voltara', 3, 2200),
  CarWheelSegment('porsenna', 'Porsenna', 2, 3300),
  CarWheelSegment('bentara', 'Bentara', 4, 1650),
];
const carWheelChips = [100, 1000, 10000, 100000];
const carWheelSegmentAngle = pi / 4;
CarWheelSegment? carWheelBet(String key) {
  for (final s in carWheelSegments) {
    if (s.key == key) return s;
  }
  return null;
}

int carWheelPayout(Map<String, int> stakes, String result) =>
    max(0, stakes[result] ?? 0) * (carWheelBet(result)?.multiplier ?? 0);
int carWheelMaxPayout(Map<String, int> stakes) =>
    carWheelSegments.map((s) => carWheelPayout(stakes, s.key)).reduce(max);

/// Clockwise from 12 o'clock; segment zero is centred under the pointer.
String carWheelKeyAtAngle(double angle) => carWheelSegments[
        ((angle + carWheelSegmentAngle / 2) % (2 * pi) / carWheelSegmentAngle)
            .floor()]
    .key;
String? carWheelKeyAt(Offset point, double size) {
  final p = point - Offset(size / 2, size / 2);
  if (p.distance < size * .13 || p.distance > size * .46) return null;
  return carWheelKeyAtAngle(atan2(p.dx, -p.dy));
}

double carWheelCenter(String key) =>
    carWheelSegments.indexWhere((s) => s.key == key) * carWheelSegmentAngle;

/// End the clockwise spin with the winner inside the fixed top pointer.
/// Jitter is limited to the middle 60% of a wedge, away from its dividers.
double carWheelSpinEnd(double start, String result,
    {int turns = 4, double jitter = 0,}) {
  final target =
      -carWheelCenter(result) + jitter.clamp(-.3, .3) * carWheelSegmentAngle;
  return start + turns.clamp(4, 5) * 2 * pi + (target - start) % (2 * pi);
}

double carWheelSpinFrame(double u, double start, double end) =>
    start + (end - start) * (1 - pow(1 - u.clamp(0.0, 1.0), 3));

// ── Shared round state from the server ──────────────────────────────────────
class CarWheelState {
  final int round, msLeft, totalBet, playerCount;
  final String phase, seedHash;
  final String? seed;
  final String? result;
  final Map<String, int> totals;
  final List<Map<String, dynamic>> players, winners;
  final List<String> history;
  final Map<String, int> myStakes;
  final List<Map<String, dynamic>> myChips;
  final int myStaked, myPayout;
  final DateTime receivedAt;

  CarWheelState.fromJson(Map<String, dynamic> j)
      : round = _int(j['round']),
        msLeft = _int(j['msLeft']),
        totalBet = _int(j['totalBet']),
        playerCount = _int(j['playerCount']),
        phase = j['phase']?.toString() ?? 'betting',
        seedHash = j['seedHash']?.toString() ?? '',
        seed = j['seed']?.toString(),
        result = carWheelBet(j['result']?.toString() ?? '')?.key,
        totals = _ints(j['totals']),
        players = _maps(j['players']),
        winners = _maps(j['winners']),
        history = (j['history'] is List ? j['history'] as List : const [])
            .whereType<String>()
            .where((v) => carWheelBet(v) != null)
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

/// "383000" → "383K"; small values stay exact.
String carWheelCompact(int v) {
  String trim(double d) => d == d.roundToDouble() || d >= 100
      ? d.toStringAsFixed(0)
      : d.toStringAsFixed(1);
  if (v >= 1000000) return '${trim(v / 1000000)}M';
  if (v >= 1000) return '${trim(v / 1000)}K';
  return '$v';
}

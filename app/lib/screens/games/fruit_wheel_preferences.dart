import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'fruit_wheel_engine.dart';

/// Per-account settings for FRUIT WHEEL. Coins and rounds live on the server;
/// this only remembers choices. Corrupt values fall back to defaults.
class FruitWheelPreferences {
  final SharedPreferences storage;
  final String account;
  FruitWheelPreferences(this.storage, this.account);
  String get _prefix => 'fruitwheel.$account.';

  bool get arabic => storage.getBool('${_prefix}arabic') ?? true;
  bool get sound => storage.getBool('${_prefix}sound') ?? true;
  bool get motion => storage.getBool('${_prefix}motion') ?? true;
  int get chip => storage.getInt('${_prefix}chip') ?? fruitChips.first;
  Future<void> setSetting(String key, bool value) =>
      storage.setBool('$_prefix$key', value);
  Future<void> setChip(int chip) => storage.setInt('${_prefix}chip', chip);

  T? _json<T>(String key, T? Function(Object?) parse) {
    try {
      final raw = storage.getString('$_prefix$key');
      return raw == null ? null : parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _put(String key, Object? value) => value == null
      ? storage.remove('$_prefix$key')
      : storage.setString('$_prefix$key', jsonEncode(value));

  /// The chips of the last round, for REPEAT.
  FruitBets? get lastBets => _json('last', FruitBets.fromJson);
  Future<void> saveLastBets(FruitBets bets) => _put('last', bets.json);

  /// A spin sent but not yet answered: retried with the same key on return,
  /// so a dropped connection can never charge twice or lose a win.
  ({String requestId, FruitBets bets})? get pending => _json('pending', (raw) {
        if (raw is! Map || raw['requestId'] is! String) return null;
        final bets = FruitBets.fromJson(raw['bets']);
        return bets == null
            ? null
            : (requestId: raw['requestId'] as String, bets: bets);
      });
  Future<void> savePending(String? requestId, FruitBets? bets) => _put(
        'pending',
        requestId == null ? null : {'requestId': requestId, 'bets': bets!.json},
      );

  /// History rows older than this were cleared by the player (display only).
  DateTime? get hiddenBefore =>
      DateTime.tryParse(storage.getString('${_prefix}hidden') ?? '');
  Future<void> clearHistory() => storage.setString(
        '${_prefix}hidden',
        DateTime.now().toUtc().toIso8601String(),
      );
  List<FruitRound> visible(List<FruitRound> rounds) {
    final cutoff = hiddenBefore;
    return rounds
        .where((r) => cutoff == null || r.at.isAfter(cutoff))
        .take(50)
        .toList();
  }
}

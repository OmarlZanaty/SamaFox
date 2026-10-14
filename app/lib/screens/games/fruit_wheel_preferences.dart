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
}

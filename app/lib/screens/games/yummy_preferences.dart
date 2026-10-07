import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'yummy_engine.dart';

class YummyPreferences {
  final SharedPreferences storage;
  final String account;
  YummyPreferences(this.storage, this.account);
  String get _prefix => 'yummy.$account.';
  bool get arabic => storage.getBool('${_prefix}arabic') ?? true;
  bool get sound => storage.getBool('${_prefix}sound') ?? true;
  bool get motion => storage.getBool('${_prefix}motion') ?? true;
  DateTime? get hiddenBefore =>
      DateTime.tryParse(storage.getString('${_prefix}hidden') ?? '');
  Future<void> setSetting(String key, bool value) async =>
      storage.setBool('$_prefix$key', value);
  Map<String, dynamic>? get pending {
    try {
      final value = storage.getString('${_prefix}pending');
      return value == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePending(Map<String, dynamic>? value) async {
    if (value == null) {
      await storage.remove('${_prefix}pending');
    } else {
      await storage.setString('${_prefix}pending', jsonEncode(value));
    }
  }

  List<YummyRound> get history {
    try {
      final records =
          jsonDecode(storage.getString('${_prefix}history') ?? '[]') as List;
      return records
          .map(
            (row) => YummyRound.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<YummyRound> visible(List<YummyRound> rounds) {
    final cutoff = hiddenBefore;
    return rounds
        .where((round) => cutoff == null || round.at.isAfter(cutoff))
        .take(50)
        .toList();
  }

  Future<void> saveHistory(List<YummyRound> rounds) async => storage.setString(
        '${_prefix}history',
        jsonEncode(visible(rounds).map((round) => round.json).toList()),
      );
  Future<void> clearHistory() async {
    await storage.setString(
      '${_prefix}hidden',
      DateTime.now().toUtc().toIso8601String(),
    );
    await storage.remove('${_prefix}history');
  }
}

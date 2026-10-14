import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../repositories/fruit_wheel_repository.dart';
import '../screens/games/fruit_wheel_engine.dart';
import '../screens/games/fruit_wheel_screen.dart';
import '../utils/storage_service.dart';

/// Dev-only entry point that boots straight into FRUIT WHEEL with an
/// in-memory stand-in for the server. Not referenced by the app; nothing here
/// ships, and its odds only approximate fruitWheelRound.math.ts.
///
///   flutter run -t lib/dev/fruit_wheel_preview.dart -d web-server --web-port 5763
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((_) => _PreviewAuth())],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'ElMessiri'),
        home: FruitWheelScreen(
          live: false,
          repository: PreviewFruitWheelRepository(),
        ),
      ),
    ),
  );
}

class _PreviewAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _PreviewAuth()
      : super(
          AuthState(
            user: User(id: 519273, name: 'Preview', coinsBalance: 1000000),
          ),
        );
  @override
  void updateCoinsBalance(int newBalance) => state =
      state.copyWith(user: state.user!.copyWith(coinsBalance: newBalance));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Local fake shared table; no network, wallet or production pool.
class PreviewFruitWheelRepository extends FruitWheelRepository {
  final _started = DateTime.now();
  int balance = 1000000, round = 2445;
  int _cycle = -1;
  bool _settled = false;
  String _outcome = 'watermelon';
  int _payout = 0;
  final Map<String, int> _stakes = {};
  Map<String, int> _previous = {};
  final List<({String key, int amount})> _chips = [];
  final List<String> _results = [];
  final List<Map<String, dynamic>> _history = [];
  int get _elapsed => DateTime.now().difference(_started).inMilliseconds;
  String get _phase {
    final ms = _elapsed % 42000;
    return ms < 30000
        ? 'betting'
        : ms < 31000
            ? 'closing'
            : ms < 37000
                ? 'spinning'
                : 'result';
  }

  void _advance() {
    final cycle = _elapsed ~/ 42000;
    if (_cycle != cycle) {
      if (_cycle >= 0 && !_settled) _settle();
      _cycle = cycle;
      round = 2445 + cycle;
      _stakes.clear();
      _chips.clear();
      _payout = 0;
      _settled = false;
      final roll = Random(round).nextInt(10000);
      _outcome = roll < 3500
          ? 'watermelon'
          : roll < 7000
              ? 'plum'
              : roll < 7875
                  ? 'sevens'
                  : 'crown';
    }
    if (_phase == 'result' && !_settled) _settle();
  }

  void _settle() {
    _settled = true;
    _payout = (_stakes[_outcome] ?? 0) * (fruitMultipliers[_outcome] ?? 0);
    balance += _payout;
    if (_stakes.isNotEmpty) _previous = Map.of(_stakes);
    _results.add(_outcome);
    _history.insert(0, {
      'round': round,
      'at': DateTime.now().toIso8601String(),
      'result': _outcome,
      'bet': _stakes.values.fold(0, (a, b) => a + b),
      'prize': _payout,
    });
  }

  Map<String, dynamic> _reply() =>
      {'balance': balance, 'round': round, 'stakes': Map.of(_stakes)};
  @override
  Future<Map<String, dynamic>> fetchState() async {
    _advance();
    final ms = _elapsed % 42000;
    final end = ms < 30000
        ? 30000
        : ms < 31000
            ? 31000
            : ms < 37000
                ? 37000
                : 42000;
    final total = _stakes.values.fold(0, (a, b) => a + b);
    return {
      'balance': balance,
      'layout': {'minBet': 100, 'maxPerKey': 1000000},
      'state': {
        'round': round,
        'phase': _phase,
        'msLeft': end - ms,
        'result': _phase == 'spinning' || _phase == 'result' ? _outcome : null,
        'segment': fruitSegments.indexOf(_outcome),
        'offset': .5,
        'totals': Map.of(_stakes),
        'totalBet': total,
        'playerCount': total > 0 ? 1 : 0,
        'history': _results.reversed.take(10).toList().reversed.toList(),
        'seedHash': 'preview',
        'me': {'stakes': Map.of(_stakes), 'staked': total, 'payout': _payout},
        'winners': _payout > 0
            ? [
                {'name': 'Preview', 'staked': total, 'payout': _payout},
              ]
            : [],
      },
    };
  }

  void _check() {
    _advance();
    if (_phase != 'betting') throw const FruitWheelException('BETTING_CLOSED');
  }

  @override
  Future<Map<String, dynamic>> bet(String key, int amount) async {
    _check();
    final next = FruitBets(_stakes);
    if (!_stakes.containsKey(key) && _stakes.length >= 2) {
      throw const FruitWheelException('MAX_CARDS');
    }
    if (!next.add(key, amount, 1000000)) {
      throw const FruitWheelException('MAX_BET');
    }
    if (amount > balance) throw const FruitWheelException('INSUFFICIENT_COINS');
    _stakes[key] = next[key];
    _chips.add((key: key, amount: amount));
    balance -= amount;
    return _reply();
  }

  @override
  Future<Map<String, dynamic>> undo() async {
    _check();
    if (_chips.isNotEmpty) {
      final chip = _chips.removeLast();
      balance += chip.amount;
      final left = _stakes[chip.key]! - chip.amount;
      if (left > 0) {
        _stakes[chip.key] = left;
      } else {
        _stakes.remove(chip.key);
      }
    }
    return _reply();
  }

  @override
  Future<Map<String, dynamic>> clear() async {
    _check();
    balance += _stakes.values.fold(0, (a, b) => a + b);
    _stakes.clear();
    _chips.clear();
    return _reply();
  }

  @override
  Future<Map<String, dynamic>> repeat() async {
    _check();
    if (_previous.isEmpty) throw const FruitWheelException('NO_PREVIOUS');
    final next = FruitBets(_stakes);
    final amount = _previous.values.fold(0, (a, b) => a + b);
    if ({..._stakes.keys, ..._previous.keys}.length > 2) {
      throw const FruitWheelException('MAX_CARDS');
    }
    for (final e in _previous.entries) {
      if (!next.add(e.key, e.value, 1000000)) {
        throw const FruitWheelException('MAX_BET');
      }
    }
    if (amount > balance) throw const FruitWheelException('INSUFFICIENT_COINS');
    for (final e in _previous.entries) {
      await bet(e.key, e.value);
    }
    return _reply();
  }

  @override
  Future<List<Map<String, dynamic>>> history() async => _history;
  @override
  Future<Map<String, dynamic>> ranking() async => {
        'entries': [],
        'me': {'net': 0},
      };
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../repositories/car_wheel_repository.dart';
import '../screens/games/car_wheel_engine.dart';
import '../screens/games/car_wheel_screen.dart';
import '../utils/storage_service.dart';

/// Dev-only entry point: عجلة السيارات against an in-memory table that runs its own
/// rounds (short timers). Not referenced by the app; nothing here ships.
///
///   flutter run -t lib/dev/car_wheel_preview.dart -d web-server --web-port 5775
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  final table = PreviewCarWheelTable();
  runApp(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((_) => _PreviewAuth())],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'ElMessiri'),
        home: CarWheelScreen(key: table.screen, repository: table, live: false),
      ),
    ),
  );
  table.run();
}

class _PreviewAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _PreviewAuth()
      : super(AuthState(
            user: User(id: 519273, name: 'Preview', coinsBalance: 5000000),),);
  @override
  void updateCoinsBalance(int newBalance) => state =
      state.copyWith(user: state.user!.copyWith(coinsBalance: newBalance));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewCarWheelTable extends CarWheelRepository {
  final screen = GlobalKey<CarWheelScreenState>();
  final _random = Random();
  int balance = 5000000, round = 249;
  String phase = 'betting';
  DateTime endsAt = DateTime.now();
  String? result;
  Map<String, int> stakes = {}, last = {};
  final crowd = <String, int>{for (final s in carWheelSegments) s.key: 10400};
  final results = <String>['aurelia', 'porsenna', 'voltara'];
  final chips = <Map<String, dynamic>>[];
  int payout = 0;

  Map<String, dynamic> _table() => {
        'round': round,
        'phase': phase,
        'msLeft': max(0, endsAt.difference(DateTime.now()).inMilliseconds),
        'seedHash': 'ab' * 32,
        'result': phase == 'betting' || phase == 'closing' ? null : result,
        'totals': {
          for (final k in {...crowd.keys, ...stakes.keys})
            k: (crowd[k] ?? 0) + (stakes[k] ?? 0),
        },
        'totalBet': 2286400 + stakes.values.fold(0, (a, b) => a + b),
        'playerCount': 4,
        'players': [
          for (final (i, n) in ['Lucky', 'Green Chip', 'Nour'].indexed)
            {
              'userId': i,
              'name': n,
              'avatarUrl': null,
              'staked': 90000 - i * 20000,
            },
        ],
        'history': results,
        'me': {
          'stakes': stakes,
          'staked': stakes.values.fold(0, (a, b) => a + b),
          'payout': payout,
          'chipList': chips,
        },
      };

  void _push() => screen.currentState?.applyState(_table(), mine: true);

  void _phase(String next, int seconds) {
    phase = next;
    endsAt = DateTime.now().add(Duration(seconds: seconds));
  }

  Future<void> run() async {
    while (true) {
      round++;
      payout = 0;
      _phase('betting', 15);
      _push();
      await Future<void>.delayed(const Duration(seconds: 15));
      _phase('closing', 2);
      _push();
      await Future<void>.delayed(const Duration(seconds: 2));
      result = carWheelSegments[_random.nextInt(8)].key;
      _phase('spinning', 7);
      _push();
      await Future<void>.delayed(const Duration(seconds: 7));
      payout = carWheelPayout(stakes, result!);
      balance += payout;
      results.add(result!);
      if (stakes.isNotEmpty) last = stakes;
      _phase('result', 5);
      _push();
      await Future<void>.delayed(const Duration(seconds: 5));
      stakes = {};
      chips.clear();
      chips.clear();
    }
  }

  Map<String, dynamic> _ok() => {
        'success': true,
        'stakes': stakes,
        'balance': balance,
        'chipList': chips,
      };
  @override
  Future<Map<String, dynamic>> fetchState() async =>
      {'state': _table(), 'balance': balance, 'chipList': chips};
  @override
  Future<Map<String, dynamic>> bet(String key, int amount) async {
    if (phase != 'betting') throw const CarWheelException('BETTING_CLOSED');
    if (amount > balance) throw const CarWheelException('INSUFFICIENT_COINS');
    chips.add({'id': chips.length + 1, 'key': key, 'amount': amount});
    balance -= amount;
    stakes = {...stakes, key: (stakes[key] ?? 0) + amount};
    return _ok();
  }

  @override
  Future<Map<String, dynamic>> clear() async {
    if (phase != 'betting') throw const CarWheelException('BETTING_CLOSED');
    balance += stakes.values.fold(0, (a, b) => a + b);
    stakes = {};
    chips.clear();
    return _ok();
  }

  @override
  Future<Map<String, dynamic>> undo() async {
    if (phase != 'betting') throw const CarWheelException('BETTING_CLOSED');
    if (chips.isEmpty) throw const CarWheelException('NO_BET');
    final c = chips.removeLast();
    final key = c['key'] as String, amount = c['amount'] as int;
    stakes[key] = (stakes[key] ?? 0) - amount;
    balance += amount;
    return _ok();
  }

  @override
  Future<Map<String, dynamic>> repeat() async {
    for (final e in last.entries) {
      await bet(e.key, e.value);
    }
    return _ok();
  }

  @override
  Future<List<Map<String, dynamic>>> history() async => [];
  @override
  Future<Map<String, dynamic>> ranking() async => {
        'entries': [
          for (final (i, n)
              in ['Player A', 'Player B', 'Lucky Demo', 'Green Chip'].indexed)
            {
              'rank': i + 1,
              'name': n,
              'avatarUrl': null,
              'net': 400000 - i * 90000,
            },
        ],
        'me': {'net': 0, 'best': 0},
      };
}

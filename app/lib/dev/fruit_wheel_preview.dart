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
/// ships, and its odds only approximate fruitWheel.math.ts.
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
        home: FruitWheelScreen(repository: PreviewFruitWheelRepository()),
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

class PreviewFruitWheelRepository extends FruitWheelRepository {
  final _random = Random();
  int balance = 1000000, round = 2445, nonce = 0;
  final List<Map<String, dynamic>> rounds = [];
  final Map<String, int> totals = {'watermelon': 62000, 'sevens': 54000, 'plum': 21000};

  @override
  Future<Map<String, dynamic>> fetchState() async => {
        'balance': balance,
        'history': rounds,
        'rounds': round,
        'today': {'totals': totals},
        'layout': {
          'minBet': 100,
          'maxBet': 300000,
          'mathRtp': .694,
          'dailyMaxWinPerUser': 5000000,
        },
      };

  @override
  Future<Map<String, dynamic>> leaderboard() async => {
        'endsIn': 3 * 86400000 + 5 * 3600000,
        'me': {'rank': 22, 'won': 4200},
        'entries': [
          for (final (i, name) in ['لوزة', 'روووح', 'غمزة', 'نجمة', 'Sam', 'Nour'].indexed)
            {'rank': i + 1, 'userId': i, 'name': name, 'avatar': null, 'won': 90000 - i * 12000},
        ],
      };

  @override
  Future<Map<String, dynamic>> fairness() async => {
        'fairness': {'serverSeedHash': 'ab' * 32, 'clientSeed': 'preview', 'nonce': nonce},
      };

  @override
  Future<Map<String, dynamic>> rotateSeed() async =>
      {'revealed': {'serverSeed': 'cd' * 32}};

  @override
  Future<FruitRound> spin(FruitBets bets, {String? requestId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (bets.total > balance) throw const FruitWheelException('INSUFFICIENT');
    final roll = _random.nextInt(10000);
    final outcome = roll < 3300
        ? 'watermelon'
        : roll < 6600
            ? 'plum'
            : roll < 8800
                ? 'sevens'
                : 'bonus';
    final slots = [
      for (var i = 0; i < fruitSegments.length; i++)
        if (fruitSegments[i] == outcome) i,
    ];
    List<int>? orbs;
    var prize = 0, bonusPrize = 0;
    if (outcome == 'bonus') {
      orbs = ([2, 3, 5]..shuffle(_random));
      bonusPrize = (bets.total * .1 * orbs.first).floor();
      prize = bonusPrize;
    } else {
      prize = bets[outcome] * fruitMultipliers[outcome]!;
    }
    balance += prize - bets.total;
    round++;
    nonce++;
    final json = {
      'id': 'r$round',
      'at': DateTime.now().toUtc().toIso8601String(),
      'round': round,
      'balance': balance,
      'serverSeedHash': 'ab' * 32,
      'clientSeed': 'preview',
      'nonce': nonce,
      'spin': {
        'bets': bets.json,
        'totalBet': bets.total,
        'outcome': outcome,
        'segment': slots[_random.nextInt(slots.length)],
        'offset': .15 + _random.nextDouble() * .7,
        'winner': outcome == 'bonus' ? null : outcome,
        'cardPrize': prize - bonusPrize,
        'orbs': orbs,
        'bonusPrize': bonusPrize,
        'totalPrize': prize,
      },
    };
    rounds.insert(0, json);
    return FruitRound.fromJson(json);
  }
}

// Plays the REAL بوابات أوليمبوس screen from recorded spins.
//
//   flutter run -d chrome -t lib/dev/olympus_play.dart
//
// Unlike olympus_preview.dart, which arranges the presentation widgets by hand
// to eyeball artwork, this runs the shipped OlympusScreen: the real replay loop,
// the real tumble timing, the real multiplier collection, the real free-spins
// feature and the real celebration. The only thing swapped out is the network.
//
// The spins come from assets/dev/olympus_spin_samples.json - a copy of the
// contract-test fixture, which is genuine output from the server's own spin
// math (regenerate with `npm run dump:olympus` in backend/, then copy it across).
// So what plays here is exactly what a player would see for those rounds -
// nothing about the outcome is invented on this side.
//
// Tap SPIN to cycle through the recorded rounds in order.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/olympus_repository.dart';
import '../screens/games/olympus_screen.dart';

/// The recorded rounds, in the order SPIN walks through them.
const _order = ['plain_loss', 'three_mults', 'epic_win', 'bonus_retrigger'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final raw = await rootBundle.loadString('assets/dev/olympus_spin_samples.json');
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  runApp(ProviderScope(child: OlympusPlayApp(fixture: fixture)));
}

class OlympusPlayApp extends StatelessWidget {
  const OlympusPlayApp({super.key, required this.fixture});

  final Map<String, dynamic> fixture;

  @override
  Widget build(BuildContext context) => MaterialApp(
        // Arabic, matching AppConfig.defaultLanguage - without this the harness
        // falls back to en and tests a language no player sees.
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar', ''), Locale('en', '')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'ElMessiri'),
        ),
        home: OlympusScreen(repository: _RecordedRepository(fixture)),
      );
}

/// Serves recorded spins in place of the backend.
///
/// Subclasses the real repository rather than reimplementing an interface, so
/// if the contract changes this stops compiling instead of silently drifting
/// out of sync with what the screen expects.
class _RecordedRepository extends OlympusRepository {
  _RecordedRepository(this.fixture);

  final Map<String, dynamic> fixture;

  int _index = 0;
  int _balance = 250000;

  OlympusSpin _spinAt(int i) => OlympusSpin.fromJson(
        Map<String, dynamic>.from(
          (fixture[_order[i % _order.length]] as Map)['spin'] as Map,
        ),
      );

  @override
  Future<OlympusState> fetchState() async {
    // The layout the server actually publishes, so the paytable and the help
    // sheet show real numbers.
    return OlympusState(
      layout: OlympusLayout.fromJson(const {
        'cols': 6,
        'rows': 5,
        'minMatch': 8,
        'minBet': 20,
        'maxBet': 20000,
        'maxWinMultiple': 5000,
        'paytable': {
          'GEM_BLUE': [0.22, 0.56, 1.55],
          'GEM_GREEN': [0.27, 0.67, 1.85],
          'GEM_YELLOW': [0.33, 0.82, 2.25],
          'GEM_PURPLE': [0.41, 1.02, 2.85],
          'GEM_RED': [0.53, 1.32, 3.65],
          'RING': [0.76, 1.95, 5.5],
          'CHALICE': [1.12, 2.95, 8.25],
          'HOURGLASS': [1.95, 5.0, 14.5],
          'CROWN': [3.7, 9.25, 25.5],
        },
        'multValues': [2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 50, 100, 250, 500],
        'scatterTrigger': 4,
        'freeSpins': 15,
        'scatterRetrigger': 3,
        'retriggerSpins': 5,
        'tierThresholds': {
          'EPIC_WIN': 100,
          'MEGA_WIN': 40,
          'BIG_WIN': 15,
          'NICE_WIN': 5,
        },
        'standardSymbols': [
          'GEM_BLUE',
          'GEM_GREEN',
          'GEM_YELLOW',
          'GEM_PURPLE',
          'GEM_RED',
          'RING',
          'CHALICE',
          'HOURGLASS',
          'CROWN',
        ],
      }),
      balance: _balance,
      history: const [],
      fairness: const OlympusFairness(
        serverSeedHash: 'recorded-fixture-no-live-seed',
        clientSeed: 'qa',
        nonce: 0,
      ),
    );
  }

  @override
  Future<OlympusSpinResponse> spin({required int amount}) async {
    // A round trip's worth of delay, so the button's busy state is exercised.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final spin = _spinAt(_index++);

    // The recorded rounds were dealt at 20 coins; settle at that stake so the
    // amounts on screen match the frames being replayed.
    _balance += spin.grandTotal - spin.bet;

    return OlympusSpinResponse(
      spin: spin,
      balance: _balance,
      fairness: OlympusFairness(
        serverSeedHash: 'recorded-fixture-no-live-seed',
        clientSeed: 'qa',
        nonce: _index,
      ),
    );
  }

  @override
  Future<OlympusFairness> setClientSeed(String seed) async => OlympusFairness(
        serverSeedHash: 'recorded-fixture-no-live-seed',
        clientSeed: seed,
        nonce: _index,
      );
}

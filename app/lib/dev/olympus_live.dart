// Runs the REAL بوابات أوليمبوس screen against a REAL running backend.
//
//   flutter run -d chrome -t lib/dev/olympus_live.dart \
//     --dart-define=API_BASE_URL=http://localhost:3100/api/v1/ \
//     --dart-define=OLYMPUS_DEV_TOKEN=<bearer token>
//
// Mint the token with, in backend/:
//   npx ts-node --transpile-only scripts/olympus-local-user.ts
//
// This is the only harness that exercises the whole stack: HTTP, auth, the
// atomic balance charge, nonce reservation, the real RNG and a real database
// row. olympus_play.dart replays recorded rounds; this one plays new ones.
//
// Development only. It writes the supplied token straight into secure storage
// so no login screen is needed; it never contains a token of its own.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../screens/games/olympus_screen.dart';
import '../services/dio_client.dart';
import '../utils/storage_service.dart';

const _token = String.fromEnvironment('OLYMPUS_DEV_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_token.isEmpty) {
    runApp(const _Missing());
    return;
  }

  await StorageService.init();
  await StorageService.saveTokens(accessToken: _token, refreshToken: _token);
  DioClient.init();

  runApp(const _LiveApp());
}

class _LiveApp extends StatelessWidget {
  const _LiveApp();

  @override
  Widget build(BuildContext context) => ProviderScope(
        child: MaterialApp(
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
          home: const OlympusScreen(),
        ),
      );
}

/// Says what is missing rather than failing with an unexplained 401.
class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF12052B),
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Pass --dart-define=OLYMPUS_DEV_TOKEN=<token>\n\n'
                'Mint one in backend/ with:\n'
                'npx ts-node --transpile-only scripts/olympus-local-user.ts\n\n'
                'API base: ${AppConfig.apiBaseUrl}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.7),
              ),
            ),
          ),
        ),
      );
}

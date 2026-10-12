import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../screens/games/fruit_jackpot_screen.dart';
import '../services/dio_client.dart';
import '../utils/storage_service.dart';

/// Dev-only entry point that boots straight into Fruit Jackpot against the browser
/// harness, without login. It is not referenced by the app and nothing here ships.
///
///   cd backend && npx ts-node --transpile-only ../tools/fruit-jackpot-mock/server.ts
///   flutter run -t lib/dev/fruit_jackpot_preview.dart -d web-server \
///     --dart-define=API_BASE_URL=http://localhost:3101/api/v1/
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  // The harness accepts any token; this one just has to parse as a JWT.
  const token = 'eyJhbGciOiJIUzI1NiJ9.eyJpZCI6MX0.preview';
  await StorageService.saveTokens(accessToken: token, refreshToken: token);
  DioClient.init();
  runApp(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((_) => _PreviewAuth())],
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _PreviewAuth()
    : super(AuthState(user: User(id: 1, name: 'Preview', coinsBalance: 0)));
  @override
  void updateCoinsBalance(int newBalance) => state = state.copyWith(
    user: state.user!.copyWith(coinsBalance: newBalance),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'ElMessiri'),
    home: const FruitJackpotScreen(),
  );
}

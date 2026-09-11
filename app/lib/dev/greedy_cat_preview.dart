import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/games/greedy_cat_screen.dart';
import '../services/socket_service.dart';

/// Dev-only entry point that boots straight into القط الجشع.
///
/// It exists so the wheel can be rendered, screenshotted and iterated on
/// without going through login and the home screen. It is not referenced by
/// the app: `lib/main.dart` is untouched, and nothing here ships.
///
///   node tools/greedy-cat-mock/server.js
///   flutter run -t lib/dev/greedy_cat_preview.dart -d web-server \
///     --dart-define=API_BASE_URL=http://localhost:3100/api/v1/ \
///     --dart-define=SOCKET_URL=http://localhost:3100
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The harness accepts any token; this one just has to parse as a JWT.
  SocketService().connect('eyJhbGciOiJIUzI1NiJ9.eyJpZCI6MX0.preview');
  runApp(const ProviderScope(child: _PreviewApp()));
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'ElMessiri'),
        home: const GreedyCatScreen(),
      );
}

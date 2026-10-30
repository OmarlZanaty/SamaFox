import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../screens/games/fruit_wheel_screen.dart';
import '../screens/games/olympus_screen.dart';
import '../utils/storage_service.dart';
import '../widgets/room/room_games_host.dart';
import 'fruit_wheel_preview.dart' show PreviewFruitWheelRepository;
import 'olympus_play.dart' show RecordedOlympusRepository;

/// Dev-only: a fake room with mics and a chat bar, and buttons that open the
/// room games card (RoomGamesHost) on the 77 wheel or Olympus with no backend.
///
///   flutter build web -t lib/dev/room_games_card_preview.dart -o build/web-games-card
///   open …/?game=fruit  or  …/?game=olympus
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  final raw = await rootBundle.loadString('assets/dev/olympus_spin_samples.json');
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  runApp(ProviderScope(
    overrides: [authStateProvider.overrideWith((_) => _PreviewAuth())],
    child: MaterialApp(
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
      home: _FakeRoom(fixture: fixture),
    ),
  ));
}

class _PreviewAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _PreviewAuth() : super(AuthState(user: User(id: 519273, name: 'Preview', coinsBalance: 1000000)));
  @override
  void updateCoinsBalance(int newBalance) =>
      state = state.copyWith(user: state.user!.copyWith(coinsBalance: newBalance));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom extends StatefulWidget {
  const _FakeRoom({required this.fixture});
  final Map<String, dynamic> fixture;
  @override
  State<_FakeRoom> createState() => _FakeRoomState();
}

class _FakeRoomState extends State<_FakeRoom> {
  @override
  void initState() {
    super.initState();
    final game = Uri.base.queryParameters['game'];
    if (game != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(game));
  }

  void _open(String game) => RoomGamesHost.show(
        context,
        initial: game == 'olympus'
            ? OlympusScreen(repository: RecordedOlympusRepository(widget.fixture))
            : FruitWheelScreen(live: false, repository: PreviewFruitWheelRepository()),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF2A1240),
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 60),
            Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                for (var i = 1; i <= 10; i++)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircleAvatar(radius: 24, backgroundColor: Colors.white24, child: Icon(Icons.mic, color: Colors.white54)),
                    Text('$i', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
              ],
            ),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ElevatedButton(onPressed: () => _open('fruit'), child: const Text('77')),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: () => _open('olympus'), child: const Text('Olympus')),
            ]),
            const SizedBox(height: 8),
            Container(height: 56, color: Colors.black54, alignment: Alignment.center,
                child: const Text('شريط الكتابة', style: TextStyle(color: Colors.white54))),
          ]),
        ),
      );
}

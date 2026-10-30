import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gifts/models/gift.dart';
import '../gifts/services/gift_socket_service.dart';
import '../gifts/widgets/lucky_win_banner.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../screens/games_hub_screen.dart';
import '../screens/splash_screen.dart';
import '../services/dio_client.dart';
import '../services/socket_service.dart';
import '../utils/storage_service.dart';
import '../widgets/home/cp_ranking_screen.dart';
import '../widgets/home/home_cp_top_card.dart';
import '../widgets/room/room_events.dart';
import '../widgets/room/room_game_win_strip.dart';

/// Dev-only: each new screen piece from the client requests with fake data,
/// for side-by-side screenshots against the client's reference images.
///
///   flutter build web -t lib/dev/client_compare_preview.dart -o build/web-compare
///   open …/?view=pk | pkwin | lucky | strip | home | ranking | splash | games
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  DioClient.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
    final data = _fake(o.path);
    if (data != null) {
      h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
    } else {
      h.reject(DioException(requestOptions: o, message: 'preview: no fixture'));
    }
  }));
  final view = Uri.base.queryParameters['view'] ?? 'pk';
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
      home: _views[view]?.call() ?? const SizedBox(),
    ),
  ));
}

String _avatar(String id) => '${Uri.base.origin}/assets/assets/images/emoji/$id.webp';

Map<String, dynamic> _user(int id, String name, String face) => {'id': id, 'name': name, 'avatarUrl': _avatar(face)};

Object? _fake(String path) {
  if (path.contains('cp/top')) {
    const names = ['Mr. Nada', 'الفهد', 'Kitta', 'Eva', 'أبو الليث', 'Mona', 'Zain', 'Lara', 'Omar', 'Sara'];
    const faces = ['heart', 'laugh', 'kiss_left', 'kiss_right', 'hug', 'couple_kiss', 'stars', 'party', 'dance', 'wow'];
    return {
      'data': [
        for (var i = 0; i < 9; i++)
          {
            'rank': i + 1,
            'level': 9 - i,
            'levelName': 'CP Lv.${9 - i}',
            'cpXp': 3142720000 ~/ (i + 1),
            'userA': _user(100 + i, names[i], faces[i]),
            'userB': _user(200 + i, names[(i + 3) % names.length], faces[(i + 4) % faces.length]),
          },
      ],
    };
  }
  if (path.contains('cp/partners')) {
    return {
      'data': [
        {'userId': 7, 'name': 'Mr. Nada', 'avatarUrl': _avatar('kiss_left'), 'cpLevel': 4, 'cpLevelName': 'CP Lv.4'},
      ],
    };
  }
  if (path.contains('top-wagerers')) {
    return {
      'items': [
        {'name': 'Mr.Saler', 'avatar': _avatar('crown'), 'wagered': 8250000},
        {'name': 'Dr/مكافح', 'avatar': _avatar('stars'), 'wagered': 4100000},
        {'name': 'المخلص', 'avatar': _avatar('party'), 'wagered': 2300000},
      ],
    };
  }
  if (path.contains('games/wins/recent')) {
    return {
      'data': [
        {'id': 1, 'userId': 5, 'name': 'Ahmed', 'avatarUrl': _avatar('laugh'), 'roomId': 1, 'gameName': 'عجلة 77', 'winCoins': 240000, 'multiplier': 8},
      ],
    };
  }
  return null;
}

final Map<String, Widget Function()> _views = {
  'pk': () => const _PkView(),
  'pkwin': () => const _PkView(winner: true),
  'lucky': () => const _LuckyView(),
  'strip': () => const _Room(child: Column(children: [SizedBox(height: 90), RoomGameWinStrip(roomId: 1)])),
  'home': () => const Scaffold(backgroundColor: Color(0xFF1B0F3B), body: SafeArea(child: Column(children: [SizedBox(height: 70), HomeCpTopCard()]))),
  'ranking': () => const _Ranking(),
  'splash': () => const SplashScreen(),
  'games': () => const GamesHubScreen(),
};

class _PreviewAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _PreviewAuth() : super(AuthState(user: User(id: 519273, name: 'الفهد', coinsBalance: 1000000)));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A dark room-like backdrop.
class _Room extends StatelessWidget {
  const _Room({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF241238), Color(0xFF0D0A1A)]),
          ),
          child: SafeArea(child: SizedBox.expand(child: child)),
        ),
      );
}

class _PkView extends StatefulWidget {
  const _PkView({this.winner = false});
  final bool winner;
  @override
  State<_PkView> createState() => _PkViewState();
}

class _PkViewState extends State<_PkView> {
  final _people = <int, Map>{
    11: {'id': 11, 'name': 'Player A', 'avatarUrl': _avatar('kiss_right')},
    22: {'id': 22, 'name': 'Player B', 'avatarUrl': _avatar('stars')},
  };
  late final _pk = <String, dynamic>{
    'pkId': 'p1', 'type': 'GLOBAL', 'status': 'ACTIVE', 'room1Id': 1, 'room2Id': 2, 'roomId': 1,
    'sideAUserId': 11, 'sideBUserId': 22, 'scoreA': 12400, 'scoreB': 9800,
    'endsAt': DateTime.now().add(const Duration(minutes: 7, seconds: 45)).toUtc().toIso8601String(),
  };

  @override
  void initState() {
    super.initState();
    if (widget.winner) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showPkWinner(context,
          {..._pk, 'winner': 'A', 'scoreA': 12400, 'scoreB': 9800}, _people));
    }
  }

  @override
  Widget build(BuildContext context) => _Room(
        child: Column(children: [
          const SizedBox(height: 70),
          RoomPkBar(
            roomId: 1, initialPk: _pk, initialPeople: _people,
            onSupport: (_, __, ___) {},
            onGift: () {}, onToggleMute: () {}, muted: false,
          ),
        ]),
      );
}

class _FakeGiftSocket extends GiftSocketService {
  _FakeGiftSocket() : super(SocketService());
  final wins = StreamController<LuckyRollEvent>.broadcast();
  @override
  Stream<LuckyRollEvent> get luckyWinStream => wins.stream;
  @override
  Stream<GiftSendEvent> get sentStream => const Stream.empty();
}

class _LuckyView extends StatefulWidget {
  const _LuckyView();
  @override
  State<_LuckyView> createState() => _LuckyViewState();
}

class _LuckyViewState extends State<_LuckyView> {
  final _socket = _FakeGiftSocket();
  Timer? _t;
  var _n = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _n++;
      for (final s in [(1, 'الوكيلة', 'kiss_left', 120), (2, 'JOHNNY', 'laugh', 40)]) {
        _socket.wins.add(LuckyRollEvent(
          rollId: _n * 10 + s.$1, senderId: s.$1, senderName: s.$2, senderAvatarUrl: _avatar(s.$3),
          recipientId: 9, roomId: 1, giftName: 'Kiss', giftIconUrl: _avatar('couple_kiss'),
          giftCoins: 10, hostCoins: 1, multiplier: s.$4, payoutCoins: s.$4 * 10, ts: DateTime.now(),
        ));
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Room(child: LuckyWinBanner(socket: _socket, roomId: 1, myUserId: 519273));
}

class _Ranking extends StatelessWidget {
  const _Ranking();
  @override
  Widget build(BuildContext context) {
    final rows = (_fake('cp/top') as Map)['data'] as List;
    return CpRankingScreen(initial: [for (final r in rows) HomeCpEntry(Map<String, dynamic>.from(r as Map))]);
  }
}

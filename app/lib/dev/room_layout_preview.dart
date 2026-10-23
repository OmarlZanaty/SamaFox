import '../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/room_controller_provider.dart';
import '../screens/room/room_widgets.dart';
import '../services/socket_service.dart';
import '../utils/storage_service.dart';
import '../widgets/room/room_chat_panel.dart';
import '../widgets/room/room_seats_chat_layout.dart';
import '../widgets/room/seats_grid.dart';

/// Dev-only: the room's mics + chat layout with fake data, sized like the real
/// RoomScreen (header, wave, bottom bar). Not referenced by the app.
///
///   flutter build web -t lib/dev/room_layout_preview.dart -o build/web-room
///   open …/?seats=20
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  final seats =
      int.tryParse(Uri.base.queryParameters['seats'] ?? '') ?? 20;
  runApp(
    ProviderScope(
      overrides: [
        roomControllerProvider(1).overrideWith((ref) => _PreviewRoom(seats)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: _PreviewRoomScreen(seatCount: seats),
        ),
      ),
    ),
  );
}

class _PreviewRoom extends StateNotifier<RoomControllerState>
    implements RoomControllerNotifier {
  _PreviewRoom(int seats)
      : super(RoomControllerState(
          roomId: 1,
          seatCount: seats,
          messages: [
            for (var i = 0; i < 8; i++)
              SocketMessage(
                messageId: i,
                roomId: 1,
                userId: 100 + i,
                username: tr('مستخدم ${i + 1}', "User ${i + 1}"),
                message: [
                  tr('مرحبا بالجميع', "Hello everyone"),
                  tr('السلام عليكم', "Peace be upon you"),
                  tr('نورتوا الروم', "Welcome to the room"),
                  tr('الصوت واضح؟', "Is the audio clear?"),
                ][i % 4],
                timestamp: DateTime.now().millisecondsSinceEpoch - i * 1000,
              ),
          ],
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _seatKeys = <int, GlobalKey>{};

class _PreviewRoomScreen extends StatelessWidget {
  const _PreviewRoomScreen({required this.seatCount});
  final int seatCount;

  @override
  Widget build(BuildContext context) {
    const bottomBarH = 64.0;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A2410), Color(0xFF8A5A2B), Color(0xFF2A1A0C)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Room header stand-in (title, id, buttons).
                  Container(
                    height: 72,
                    alignment: Alignment.center,
                    color: Colors.black26,
                    child: Text(tr('روم تجريبي — $seatCount مايك', "Test room — $seatCount mics"),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: bottomBarH + 10 + 55),
                      child: RoomSeatsChatLayout(
                        seatCount: seatCount,
                        seats: ClipPath(
                          clipper: BottomWaveClipper(
                              depth: RoomSeatsChatLayout.waveDepth),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 12,
                              right: 12,
                              bottom: RoomSeatsChatLayout.waveDepth,
                            ),
                            child: SeatsGrid(
                              scrollable: false,
                              seats: {
                                for (var i = 1; i <= seatCount; i++)
                                  i: SeatData(
                                    seatNumber: i,
                                    userId: i == 8 ? 500 : null,
                                    username: i == 8 ? tr('علوش', "Alloush") : null,
                                    avatarUrl: null,
                                    level: 1,
                                    isMuted: false,
                                    isLocked: false,
                                  ),
                              },
                              seatCount: seatCount,
                              seatEarnings: const {500: 12000},
                              seatKeys: _seatKeys,
                              myUserId: 0,
                              isAdmin: false,
                              lockedSeats: const {},
                              ownerId: 0,
                              adminIds: const [],
                              onSeatTap: (_, __) {},
                            ),
                          ),
                        ),
                        chat: RoomChatPanel(
                          roomId: 1,
                          header: Container(
                            height: 30,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(tr('🎲 البطل كسب ×50  750000', "🎲 The champion won ×50  750000"),
                                style: TextStyle(
                                    color: Colors.amber, fontSize: 12)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Bottom bar stand-in.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomBarH,
                child: Container(color: Colors.black38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

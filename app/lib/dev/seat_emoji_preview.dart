import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../services/socket_service.dart';
import '../widgets/room/room_emoji.dart';
import '../widgets/room/room_role_chip.dart';
import '../widgets/room/room_top_supporters.dart';
import '../widgets/room/room_win_announcement.dart';
import '../widgets/room/seat_card.dart';

/// Dev-only: four mics, the emoji sheet and buttons that fire seat emojis
/// (as the server would relay them), plus the new room chips / supporters /
/// win card. No backend.
///
///   flutter build web -t lib/dev/seat_emoji_preview.dart -o build/web-seat-emoji
void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar', ''), Locale('en', '')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark(),
      home: const _Preview(),
    ));

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  int _n = 0;
  final _seats = [
    for (var i = 1; i <= 4; i++)
      SeatData.fromJson({'seatNumber': i, 'userId': 100 + i, 'username': 'User $i', 'isMuted': false}),
  ];

  void _fire(String id, int sender) {
    final def = roomEmojiById(id)!;
    _n++;
    final result = id == 'dice' ? 1 + _n % 6 : id == 'slot' ? _n % 3 : null;
    roomEmojiEvents.add(RoomEmojiEvent(def, sender - 100, sender, result, null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B0F3B),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final s in _seats)
              SeatCard(
                seatNumber: s.seatNumber,
                seat: s,
                isMine: s.userId == 101,
                isAdmin: false,
                isOwnerSeat: s.userId == 101,
                isAdminSeat: s.userId == 102,
                onTap: () {},
                seatSize: 74,
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final id in ['laugh', 'heart', 'dance', 'dice', 'slot'])
              for (final u in [101, 102])
                ElevatedButton(key: Key('fire_${id}_$u'), onPressed: () => _fire(id, u), child: Text('$id → $u')),
            ElevatedButton(
              key: const Key('picker'),
              onPressed: () => RoomEmojiPicker.show(context, onPick: (e) {
                Navigator.of(context).maybePop();
                _fire(e.id, 101);
              }),
              child: const Text('😀 sheet'),
            ),
          ]),
          const SizedBox(height: 16),
          const Row(children: [RoomRoleChip(isOwner: true), SizedBox(width: 8), RoomRoleChip(isOwner: false)]),
          const SizedBox(height: 16),
          RoomTopSupporters(
            items: const [
              RoomParticipant(userId: 1, name: 'Top 1', amount: 52000),
              RoomParticipant(userId: 2, name: 'Top 2', amount: 18000),
            ],
            onTap: (_) {},
          ),
          const SizedBox(height: 16),
          RoomWinAnnouncement(
            game: GameWinAnnouncement.fromMap(const {
              'userId': 5, 'name': 'Ahmed', 'gameName': 'عجلة 77', 'winCoins': 80000, 'multiplier': 8,
            }),
          ),
        ]),
      ),
    );
  }
}

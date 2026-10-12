// تأثير CP Level on the mic grid: drawn only for CP partners on neighbouring
// seats of the same row, and never for anyone else.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/services/socket_service.dart';
import 'package:samafox/widgets/room/cp_seat_effect.dart';
import 'package:samafox/widgets/room/seats_grid.dart';

SeatData _seat(int n, int? uid) => SeatData(
      seatNumber: n,
      userId: uid,
      username: uid == null ? null : 'U$uid',
      avatarUrl: null,
      level: 1,
      isMuted: true,
      isLocked: false,
    );

const _heart = CpSeatLink(userA: 1, userB: 2, level: 3, effectKey: 'heart3d', animationSpeed: 1, priority: 10);

Widget _grid(Map<int, int?> occupants, List<CpSeatLink> links) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      body: Center(
        child: SizedBox(
          width: 400,
          height: 320,
          child: SeatsGrid(
            seats: {for (final e in occupants.entries) e.key: _seat(e.key, e.value)},
            seatCount: 8,
            myUserId: 99,
            isAdmin: false,
            onSeatTap: (_, __) {},
            ownerId: 0,
            adminIds: const [],
            lockedSeats: const {},
            seatKeys: {},
            cpLinks: links,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('partners on neighbouring seats get the effect', (tester) async {
    await tester.pumpWidget(_grid({1: 1, 2: 2}, [_heart]));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(CpSeatEffectLayer), findsOneWidget);
    await expectLater(find.byType(SeatsGrid), matchesGoldenFile('goldens/cp_heart_effect.png'));
  });

  testWidgets('partners far apart get nothing', (tester) async {
    await tester.pumpWidget(_grid({1: 1, 3: 2}, [_heart]));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CpSeatEffectLayer), findsNothing);
  });

  testWidgets('neighbouring numbers on different rows get nothing', (tester) async {
    // 8 seats lay out as 4 + 4, so seats 4 and 5 are not side by side.
    await tester.pumpWidget(_grid({4: 1, 5: 2}, [_heart]));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CpSeatEffectLayer), findsNothing);
  });

  testWidgets('one partner leaves the mic → the effect goes', (tester) async {
    await tester.pumpWidget(_grid({1: 1, 2: 2}, [_heart]));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CpSeatEffectLayer), findsOneWidget);
    // The next server snapshot no longer carries the link.
    await tester.pumpWidget(_grid({1: 1, 2: null}, const []));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CpSeatEffectLayer), findsNothing);
  });
}

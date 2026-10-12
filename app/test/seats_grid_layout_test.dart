import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/services/socket_service.dart';
import 'package:samafox/widgets/room/seat_card.dart';
import 'package:samafox/widgets/room/seats_grid.dart';

const _gridBoxKey = Key('seats-grid-box');

SeatData _seat(int n) => SeatData(
      seatNumber: n,
      userId: null,
      username: null,
      avatarUrl: null,
      level: 1,
      isMuted: false,
      isLocked: false,
    );

Widget _grid(int seatCount, {double? height, double bottomInset = 0}) {
  final gridHeight = height ??
      SeatsGrid.heightFor(
        width: 360,
        seatCount: seatCount,
        maxHeight: 400,
      );

  return MediaQuery(
    data: MediaQueryData(size: const Size(360, 800), padding: EdgeInsets.only(bottom: bottomInset)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            key: _gridBoxKey,
            width: 360,
            height: gridHeight,
            child: SeatsGrid(
              seats: {for (var i = 1; i <= seatCount; i++) i: _seat(i)},
              seatCount: seatCount,
              myUserId: 99,
              isAdmin: false,
              onSeatTap: (_, __) {},
              ownerId: 0,
              adminIds: const [],
              lockedSeats: const {},
              seatKeys: {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final seatCount in const [5, 10, 30]) {
    testWidgets('$seatCount seats keep avatars at or below 54 dp',
        (tester) async {
      await tester.pumpWidget(_grid(seatCount));
      await tester.pump();

      final exception = tester.takeException();
      expect(exception, isNull);
      for (final card in tester.widgetList<SeatCard>(find.byType(SeatCard))) {
        expect(card.seatSize, lessThanOrEqualTo(54));
      }
    });
  }

  testWidgets('ten seats are packed at the top and heightFor matches',
      (tester) async {
    final height = SeatsGrid.heightFor(
      width: 360,
      seatCount: 10,
      maxHeight: 400,
    );

    await tester.pumpWidget(_grid(10, height: height));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_gridBoxKey)).height, height);
    expect(
      tester.getTopLeft(find.byType(SeatCard).first).dy,
      moreOrLessEquals(tester.getTopLeft(find.byKey(_gridBoxKey)).dy),
    );
  });

  testWidgets('a navigation-bar inset neither shrinks the mics nor makes them scroll', (tester) async {
    await tester.pumpWidget(_grid(10, bottomInset: 48));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNothing);
    for (final card in tester.widgetList<SeatCard>(find.byType(SeatCard))) {
      expect(card.seatSize, 54);
    }
  });
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/services/socket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/providers/room_controller_provider.dart';
import 'package:samafox/widgets/room/room_chat_panel.dart';
import 'package:samafox/widgets/room/room_seats_chat_layout.dart';
import 'package:samafox/widgets/room/seat_card.dart';
import 'package:samafox/widgets/room/seats_grid.dart';

const _gridBoxKey = Key('seats-grid-box');

class _TestRoom extends StateNotifier<RoomControllerState>
    implements RoomControllerNotifier {
  _TestRoom() : super(const RoomControllerState(roomId: 1));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
    data: MediaQueryData(
        size: const Size(360, 800),
        padding: EdgeInsets.only(bottom: bottomInset)),
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

  testWidgets(
      'a navigation-bar inset neither shrinks the mics nor makes them scroll',
      (tester) async {
    await tester.pumpWidget(_grid(10, bottomInset: 48));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNothing);
    for (final card in tester.widgetList<SeatCard>(find.byType(SeatCard))) {
      expect(card.seatSize, 54);
    }
  });

  testWidgets('room chat starts below the mic box on compact and tall phones',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [Size(360, 640), Size(412, 915)]) {
      for (var seatCount = 1; seatCount <= 30; seatCount++) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              roomControllerProvider(1).overrideWith((ref) => _TestRoom())
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                    size: size,
                    padding: const EdgeInsets.only(top: 24, bottom: 24)),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // Exercise a header taller than the old 72 dp estimate.
                      const SizedBox(height: 96),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 129),
                          child: RoomSeatsChatLayout(
                            seatCount: seatCount,
                            seats: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                              child: SeatsGrid(
                                seats: {
                                  for (var i = 1; i <= seatCount; i++)
                                    i: _seat(i)
                                },
                                seatCount: seatCount,
                                scrollable: false,
                                myUserId: 99,
                                isAdmin: false,
                                onSeatTap: (_, __) {},
                                ownerId: 0,
                                adminIds: const [],
                                lockedSeats: const {},
                                seatKeys: {},
                              ),
                            ),
                            chat: const RoomChatPanel(
                                roomId: 1, header: SizedBox(height: 30)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final reason = '$seatCount seats at ${size.width}x${size.height}';
        expect(tester.takeException(), isNull, reason: reason);
        final seatsRect =
            tester.getRect(find.byKey(RoomSeatsChatLayout.seatsBoxKey));
        final chatRect =
            tester.getRect(find.byKey(RoomSeatsChatLayout.chatBoxKey));
        expect(chatRect.bottom, lessThanOrEqualTo(size.height - 129),
            reason: reason);
        // 15/10: the messages disappeared under 20 mics. The chat keeps room
        // for the tabs, the winners strip and a few lines.
        expect(chatRect.height, greaterThanOrEqualTo(170 - .01),
            reason: reason);
        expect(find.byType(SeatCard), findsNWidgets(seatCount));
        var lastSeatBottom = 0.0;
        for (final card in find.byType(SeatCard).evaluate()) {
          final rect = tester.getRect(find.byWidget(card.widget));
          expect(rect.bottom, lessThanOrEqualTo(chatRect.top + .01),
              reason: '$reason: a mic is under the chat');
          expect(rect.top, greaterThanOrEqualTo(seatsRect.top), reason: reason);
          lastSeatBottom = max(lastSeatBottom, rect.bottom);
        }
        // «الكل / هدية / دردشة» right under the last row: ≤ 1 cm (≈ 63 dp).
        for (final label in ['الكل', 'هدية', 'دردشة']) {
          final top = tester.getTopLeft(find.text(label)).dy;
          expect(top, greaterThanOrEqualTo(lastSeatBottom), reason: reason);
          expect(top - lastSeatBottom, lessThanOrEqualTo(63),
              reason: '$reason: tabs too far below the mics');
        }
        await tester.tap(find.text('هدية'));
        await tester.pump();
        expect(
            tester.widget<Text>(find.text('هدية')).style?.color, Colors.white);
      }
    }
  });
}

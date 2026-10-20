import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'room_left_rail.dart';
import 'seats_grid.dart';

/// Seats and chat share the space below the room header.
///
/// 15/10, client: «الكل / هدية / دردشة» sit just under the coins of the last
/// mic row (≤ 1 cm) and move up and down with the mics; the messages must never
/// disappear. So the chat keeps a minimum height and the mics shrink to leave
/// it, and the chat starts right under the last row — over the empty wave the
/// seats box keeps at its bottom, not after it.
class RoomSeatsChatLayout extends StatelessWidget {
  const RoomSeatsChatLayout({
    super.key,
    required this.seatCount,
    required this.seats,
    required this.chat,
  });

  final int seatCount;
  final Widget seats;
  final Widget chat;

  static const seatsBoxKey = ValueKey('room-seats-box');
  static const chatBoxKey = ValueKey('room-chat-box');

  /// The empty band [seats] keeps under its last row (the wave clip).
  static const waveDepth = 40.0;

  /// From the last row's coins to the top of the chat panel.
  static const gapUnderSeats = 6.0;

  /// The chat never gets less: tabs, the winners strip and a few messages.
  static double minChatHeight(double available) =>
      (available * .32).clamp(170.0, 260.0).toDouble();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight;
          final gridMax =
              math.max(0.0, available - gapUnderSeats - minChatHeight(available));
          final gridHeight = SeatsGrid.heightFor(
            // 24 = horizontal padding, + the left rail gutter (SPEC52 #19).
            width: math.max(0.0, constraints.maxWidth - 24 - kRoomRailGutter),
            seatCount: seatCount,
            maxHeight: gridMax,
          );
          final chatTop = math.min(available, gridHeight + gapUnderSeats);
          return Stack(
            children: [
              Positioned(
                key: seatsBoxKey,
                top: 0,
                left: 0,
                right: 0,
                height: math.min(available, gridHeight + waveDepth),
                child: seats,
              ),
              Positioned(
                key: chatBoxKey,
                top: chatTop,
                bottom: 0,
                left: constraints.maxWidth * .05,
                right: constraints.maxWidth * .05,
                child: ClipRect(child: chat),
              ),
            ],
          );
        },
      );
}

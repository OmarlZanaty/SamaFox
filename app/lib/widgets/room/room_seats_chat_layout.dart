import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'seats_grid.dart';

// Reserved above the microphones for the game winnings and gifts strip.
const double kRoomWinsStripSlot = 48;

/// Seats and chat share the remaining space below the actual room header.
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const waveDepth = 40.0;
          const gap = 12.0;
          // Leave room for tabs and the winners ticker on compact phones.
          final gridMax =
              math.max(0.0, constraints.maxHeight - waveDepth - gap - 96);
          final gridHeight = SeatsGrid.heightFor(
            width: math.max(0.0, constraints.maxWidth - 24),
            seatCount: seatCount,
            maxHeight: gridMax,
          );
          final seatsHeight =
              math.min(constraints.maxHeight, gridHeight + waveDepth);
          // The chat takes everything under the mics (12/10: "the chat grows
          // into the space the mics free") — and never more: on 14/10 a
          // 30% minimum pushed it up over the last row of mics.
          final chatHeight =
              math.max(0.0, constraints.maxHeight - seatsHeight - gap);
          return Column(
            children: [
              SizedBox(key: seatsBoxKey, height: seatsHeight, child: seats),
              const SizedBox(height: gap),
              SizedBox(
                key: chatBoxKey,
                width: constraints.maxWidth * .90,
                height: chatHeight,
                child: ClipRect(child: chat),
              ),
            ],
          );
        },
      );
}

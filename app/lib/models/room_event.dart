// ✅ STEP 1) Add a small model (new file)
// lib/models/room_event.dart
import 'package:flutter/material.dart';

enum RoomEventType { gift, seat, mic, join, leave, system }

class RoomEvent {
  final RoomEventType type;
  final String text;
  final DateTime at;
  final String? username;
  final String? badge;
  final int? coins;

  const RoomEvent({
    required this.type,
    required this.text,
    required this.at ,
    this.username,
    this.badge,
    this.coins,
  });

  IconData get icon {
    switch (type) {
      case RoomEventType.gift:
        return Icons.card_giftcard;
      case RoomEventType.seat:
        return Icons.event_seat;
      case RoomEventType.mic:
        return Icons.mic;
      case RoomEventType.join:
        return Icons.login;
      case RoomEventType.leave:
        return Icons.logout;
      case RoomEventType.system:
      default:
        return Icons.info_outline;
    }
  }
}
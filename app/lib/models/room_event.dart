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
  final String? countryCode;
  final String? gender;

  /// Identity shown next to the name on an entrance line —
  /// "فهد VIP 6 · LV 8 دخل الغرفة" — plus the icon urls of his شارات.
  final int? vipLevel;
  final int? level;
  final List<String> badges;

  /// Who the line is about — the entrant, or the gift's SENDER. Lets the feed
  /// open his card on tap, exactly like a chat bubble does.
  final int? userId;

  const RoomEvent({
    required this.type,
    required this.text,
    required this.at ,
    this.username,
    this.badge,
    this.coins,
    this.countryCode,
    this.gender,
    this.vipLevel,
    this.level,
    this.badges = const [],
    this.userId,
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

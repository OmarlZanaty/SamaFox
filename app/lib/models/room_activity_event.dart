import 'package:flutter/material.dart';
import 'room_event.dart'; // ✅ IMPORTANT

class RoomActivityEvent {
  final String text;
  final IconData icon;
  final DateTime time;
  final RoomEventType type;

  RoomActivityEvent({
    required this.text,
    required this.icon,
    required this.time,
    required this.type,
  });
}
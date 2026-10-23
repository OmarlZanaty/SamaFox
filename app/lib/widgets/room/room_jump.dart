import '../../l10n/tr.dart';
import 'package:flutter/material.dart';

import '../../main.dart' show navigatorKey;
import '../../screens/room_screen.dart';
import '../../services/active_room.dart';
import '../../services/dio_client.dart';

/// SPEC52 #4 (and the rocket / share links) — "هل تريد الانتقال إلى هذه
/// الغرفة؟" then into that room, or "الغرفة غير متاحة حاليًا." when the server
/// says it is closed or gone. One helper so every banner behaves the same.
Future<void> confirmAndJumpToRoom(
  int roomId, {
  String? question,
  String? roomName,
}) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  if (ActiveRoom.instance.roomId == roomId) {
    _snack(tr('أنت موجود في هذه الغرفة بالفعل', "You are already in this room"));
    return;
  }
  final yes = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF2A1655),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(question ?? tr('هل تريد الانتقال إلى هذه الغرفة؟', 'Go to this room?'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: roomName == null
            ? null
            : Text(roomName, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(tr('لا', "No"), style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(tr('نعم', "Yes"), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
  if (yes != true) return;

  // Ask the server first: a closed/removed room must not open an empty screen.
  bool available = false;
  try {
    final res = await DioClient.dio.get('/rooms/$roomId');
    final body = res.data;
    final room = body is Map ? (body['room'] ?? body['data'] ?? body) : null;
    final active = room is Map ? room['isActive'] : null;
    available = res.statusCode == 200 && active != false;
  } catch (_) {
    available = false;
  }
  if (!available) {
    _snack(tr('الغرفة غير متاحة حاليًا.', "Room currently unavailable."));
    return;
  }
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute(builder: (_) => RoomScreen(roomId: roomId)));
}

void _snack(String msg) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
}

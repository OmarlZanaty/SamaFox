import 'dart:async';

import 'package:flutter/foundation.dart';

/// The one room this device is in.
///
/// The client's report: *"لما ادخل اي غرفه بفضل معلق علي المايك في الغرفه اللي
/// قبلها"*, and the requirement *"مع دخولي اي غرفه اخرج تلقائي من الغرفه اللي
/// كنت فيها"*.
///
/// Nothing enforced that. A room is entered with `Navigator.push`, so opening
/// room B from a profile, a search result, a gift banner or the PiP bubble left
/// room A's screen alive underneath it — still joined on the server, still
/// holding its seat, and (because [WebRTCAudioService] is a singleton) still
/// publishing the microphone into A's mesh.
///
/// This is the registry that makes "one room at a time" true on the client:
/// whoever owns the live room registers a closer here, and entering a different
/// room runs it first. The server enforces the same rule independently on
/// `join_room`, so an old client cannot hold a seat in a room it has left.
class ActiveRoom {
  ActiveRoom._();
  static final ActiveRoom instance = ActiveRoom._();

  int? _roomId;
  Future<void> Function()? _closer;

  /// The room currently owning the audio session, or null.
  int? get roomId => _roomId;

  /// Take ownership of [roomId], closing whatever other room held it.
  ///
  /// Awaits the old room's teardown so the caller can initialise its own audio
  /// afterwards without racing it: the two would otherwise fight over the same
  /// singleton service.
  Future<void> enter(int roomId, Future<void> Function() closer) async {
    if (_roomId != null && _roomId != roomId) {
      final close = _closer;
      final leaving = _roomId;
      _roomId = null;
      _closer = null;
      if (close != null) {
        try {
          await close();
        } catch (e) {
          // A failure here must never block entering the new room; the server
          // drops the old membership on join_room regardless.
          debugPrint('[ActiveRoom] closing room $leaving failed: $e');
        }
      }
    }
    _roomId = roomId;
    _closer = closer;
  }

  /// Hand ownership to another owner of the SAME room — the PiP bubble taking
  /// over from the screen, or the screen taking over from the bubble.
  void handOver(int roomId, Future<void> Function() closer) {
    if (_roomId != null && _roomId != roomId) return;
    _roomId = roomId;
    _closer = closer;
  }

  /// Give up ownership, if [roomId] still holds it. Called when a room is left
  /// for real, so a later entry has nothing to close.
  void release(int roomId) {
    if (_roomId != roomId) return;
    _roomId = null;
    _closer = null;
  }
}

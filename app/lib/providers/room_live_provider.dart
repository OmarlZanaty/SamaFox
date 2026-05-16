import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/room_live_state.dart';
import '../services/socket_service.dart';

final roomLiveProvider = StateNotifierProvider.family<RoomLiveNotifier, RoomLiveState, int>(
      (ref, roomId) => RoomLiveNotifier(roomId),
);

class RoomLiveNotifier extends StateNotifier<RoomLiveState> {
  RoomLiveNotifier(this.roomId) : super(RoomLiveState.empty(roomId));

  final int roomId;
  final SocketService _socket = SocketService();

  StreamSubscription? _seatsStateSub;
  StreamSubscription? _seatUpdateSub;
  StreamSubscription? _queueSub;
  StreamSubscription? _msgSub;

  bool _bound = false;

  void bind() {
    if (_bound) return;
    _bound = true;

    _seatsStateSub = _socket.roomSeatsStateStream.listen((s) {
      final map = <int, SeatData>{};
      for (final seat in s.seats) {
        map[seat.seatNumber] = seat;
      }
      state = state.copyWith(seats: map);
    });

    _seatUpdateSub = _socket.seatUpdateStream.listen((u) {
      final seats = Map<int, SeatData>.from(state.seats);
      final seatNumber = u.seatNumber ?? 0;
      if (seatNumber == 0) return;

      final old = seats[seatNumber];
      if (old == null) return;

      if (u.type == SeatUpdateType.occupied) {
        seats[seatNumber] = SeatData(
          seatNumber: seatNumber,
          userId: u.userId,
          username: u.username,
          avatarUrl: u.avatarUrl,
          avatarFrameUrl: u.avatarFrameUrl, // ✅ FIX: was missing, frame always null
          level: u.level ?? 0,
          isMuted: u.isMuted ?? true,
          isLocked: old.isLocked,
        );
      } else if (u.type == SeatUpdateType.vacated) {
        seats[seatNumber] = SeatData(
          seatNumber: seatNumber,
          userId: null,
          username: null,
          avatarUrl: null,
          avatarFrameUrl: null, // ✅ clear on vacate
          level: 0,
          isMuted: true,
          isLocked: old.isLocked,
        );
      } else if (u.type == SeatUpdateType.muteChanged) {
        seats[seatNumber] = SeatData(
          seatNumber: seatNumber,
          userId: old.userId,
          username: old.username,
          avatarUrl: old.avatarUrl,
          avatarFrameUrl: old.avatarFrameUrl, // ✅ preserve frame on mute change
          level: old.level,
          isMuted: u.isMuted ?? old.isMuted,
          isLocked: old.isLocked,
        );
      }

      state = state.copyWith(seats: seats);
    });

    _queueSub = _socket.micQueueStream.listen((q) {
      if (q.roomId != roomId) return;
      state = state.copyWith(micQueue: q.queueUserIds);
    });

    _msgSub = _socket.messageStream.listen((m) {
      if (m.roomId != roomId) return;
      final msgs = List<SocketMessage>.from(state.messages);
      msgs.add(m);
      state = state.copyWith(messages: msgs);
    });
  }

  @override
  void dispose() {
    _seatsStateSub?.cancel();
    _seatUpdateSub?.cancel();
    _queueSub?.cancel();
    _msgSub?.cancel();
    super.dispose();
  }
}
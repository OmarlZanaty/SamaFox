import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/providers/room_provider.dart';
//import '../services/socket_service_impl.dart';
import '../models/user.dart';
import '../services/socket_service.dart';
import 'auth_provider.dart';
import '../models/room_event.dart';
enum MyMicStatus { none, requested, approved, onMic }

final roomControllerProvider =
StateNotifierProvider.autoDispose.family<RoomControllerNotifier, RoomControllerState, int>(
      (ref, roomId) => RoomControllerNotifier(ref: ref, roomId: roomId),
);

class RoomControllerState {
  final int roomId;
  final int ownerId;
  final List<int> adminIds;
  final List<SocketMessage> messages;
  final Map<int, SeatData> seats;
  final List<int> micQueue;
  final List<int> voiceUserIds; // ✅ ADD
  final bool isOpen;
  final int seatCount;
  final String? roomImageUrl;        // ✅ NEW
  final String? roomBackgroundUrl;   // ✅ NEW
  final MyMicStatus myMicStatus; // ✅ NEW
  final Set<int> lockedSeats;
  final List<RoomEvent> events; // ✅ NEW
  final Map<int, User> onlineUsers;

  const RoomControllerState({
    required this.roomId,
    this.ownerId = 0,
    this.adminIds = const <int>[],
    this.messages = const <SocketMessage>[],
    this.seats = const <int, SeatData>{}, // ✅ FIX
    this.micQueue = const <int>[],
    this.voiceUserIds = const <int>[], // ✅ ADD
    this.isOpen = false,
    this.seatCount = 0, // 0 = unknown until socket/rest fills it
    this.roomImageUrl,              // ✅ NEW
    this.roomBackgroundUrl,         // ✅ NEW
    this.myMicStatus = MyMicStatus.none,
    this.lockedSeats = const <int>{}, // ✅ NEW
    this.events = const <RoomEvent>[], // ✅ NEW
    this.onlineUsers = const {},
  });



  RoomControllerState copyWith({
    int? ownerId,
    List<int>? adminIds,
    List<SocketMessage>? messages,
    Map<int, SeatData>? seats,
    List<int>? micQueue,
    List<int>? voiceUserIds, // ✅ ADD
    int? seatCount,        // ✅ ADD
    bool? isOpen,
    MyMicStatus? myMicStatus,
    Set<int>? lockedSeats,            // ✅ NEW (nullable param)
    List<RoomEvent>? events, // ✅ NEW
    String? roomImageUrl,           // ✅ NEW
    String? roomBackgroundUrl,      // ✅ NEW
    Map<int, User>? onlineUsers,
  }) {
    return RoomControllerState(
      roomId: roomId,
      ownerId: ownerId ?? this.ownerId,
      adminIds: adminIds ?? this.adminIds,
      messages: messages ?? this.messages,
      seats: seats ?? this.seats,
      micQueue: micQueue ?? this.micQueue,
      voiceUserIds: voiceUserIds ?? this.voiceUserIds, // ✅ ADD
      seatCount: (seatCount ?? this.seatCount).clamp(0, 24),
      isOpen: isOpen ?? this.isOpen,
      roomImageUrl: roomImageUrl ?? this.roomImageUrl,                 // ✅ NEW
      roomBackgroundUrl: roomBackgroundUrl ?? this.roomBackgroundUrl,  // ✅ NEW
      myMicStatus: myMicStatus ?? this.myMicStatus,
      lockedSeats: lockedSeats ?? this.lockedSeats,   // ✅ NEW (keep existing)
      events: events ?? this.events, // ✅ NEW
      onlineUsers: onlineUsers ?? this.onlineUsers,
    );
  }
}


class RoomControllerNotifier extends StateNotifier<RoomControllerState> {
  final Ref ref;
  final int roomId;
  final SocketService _socket = SocketService();

  StreamSubscription? _reconnectSub;

  StreamSubscription<SocketMessage>? _msgSub;
  StreamSubscription<SeatUpdate>? _seatSub;
  StreamSubscription<RoomSeatsState>? _seatsStateSub;
  StreamSubscription<Map<String, dynamic>>? _voiceUsersSub; // ✅ ADD
  StreamSubscription<Map<String, dynamic>>? _approveMicSub; // ✅ NEW
  StreamSubscription<dynamic>? _seatLockSub;

  RoomControllerNotifier({required this.ref, required this.roomId})
      : super(RoomControllerState(roomId: roomId));

  // ----------------------------
  // Lifecycle
  // ----------------------------

  // ----------------------------
// Lifecycle
// ----------------------------
  void setSeatCountLocal(int count) {
    final safe = count.clamp(1, 24);
    if (safe == state.seatCount) return;
    state = state.copyWith(seatCount: safe);
  }
  int? _pendingSeatNumber;

  Future<void> loadRoomDetails() async {
    try {
      final room = ref.read(roomsProvider).findById(roomId);
      if (room == null) return;

      state = state.copyWith(
        ownerId: room.owner?.id ?? room.ownerId ?? 0, // ✅ FIX
        seatCount: (room.maxSeats ?? 0),
        roomImageUrl: room.coverImageUrl,
        roomBackgroundUrl: room.backgroundImageUrl,
      );

      print('🔄 Room details reloaded for room=$roomId');
    } catch (e) {
      print('❌ Failed to reload room: $e');
    }
  }

  void addOnlineUser(User user) {
    final updated = Map<int, User>.from(state.onlineUsers);
    updated[user.id] = user;

    state = state.copyWith(onlineUsers: updated);
  }


  void setVoiceUsers(List<int> users) {
    state = state.copyWith(
      voiceUserIds: users,
    );
  }

  void removeOnlineUser(int userId) {
    final updated = Map<int, User>.from(state.onlineUsers);
    updated.remove(userId);

    state = state.copyWith(onlineUsers: updated);
  }

  void addActivity(
    String text,
    RoomEventType type, {
    String? username,
    String? badge,
    int? coins,
    String? countryCode,
    String? gender,
  }) {
    final newEvent = RoomEvent(
      type: type,
      text: text,
      at: DateTime.now(),
      username: username,  // ✅ ADD
      badge: badge,        // ✅ ADD
      coins: coins,        // ✅ ADD
      countryCode: countryCode,
      gender: gender,
    );

    final updated = [...state.events, newEvent];

    // ✅ prevent memory growth
    final trimmed = updated.length > 50
        ? updated.sublist(updated.length - 50)
        : updated;

    state = state.copyWith(events: trimmed);
  }

  void addRoomEvent(RoomEvent e) {
    final list = [...state.events, e];
    final trimmed = list.length > 60 ? list.sublist(list.length - 60) : list;
    state = state.copyWith(events: trimmed);
  }

  void setSeatLockedLocal({required int seatNumber, required bool locked}) {
    final next = Set<int>.from(state.lockedSeats);
    if (locked) {
      next.add(seatNumber);
    } else {
      next.remove(seatNumber);
    }
    state = state.copyWith(lockedSeats: next);
  }

  Future<void> toggleSeatLock({required int seatNumber, required bool locked}) async {
    // optimistic local
    setSeatLockedLocal(seatNumber: seatNumber, locked: locked);

    await _socket.waitUntilConnected(timeout: const Duration(seconds: 5));
    if (!_socket.isConnected) return;

    _socket.emit('seat_lock', {
      'roomId': state.roomId,
      'seatNumber': seatNumber,
      'locked': locked,

      // aliases
      'room_id': state.roomId,
      'seat_number': seatNumber,
    });

    // force refresh (if backend supports)
    _socket.emit('get_room_seats_state', {'roomId': roomId});
    _socket.emit('request_room_seats_state', {'roomId': roomId});
  }



  // ----------------------------
// Room visuals (Admin)
// ----------------------------
  void setRoomImageUrlLocal(String url) {
    final v = url.trim();
    if (v.isEmpty) return;
    if (v == state.roomImageUrl) return;
    state = state.copyWith(roomImageUrl: v);
  }

  void setRoomBackgroundUrlLocal(String url) {
    final v = url.trim();
    if (v.isEmpty) return;
    if (v == state.roomBackgroundUrl) return;
    state = state.copyWith(roomBackgroundUrl: v);
  }

  bool _opening = false;
  void adminRemoveFromSeat({required int seatNumber, required int targetUserId}) {
    print('🛑 adminRemoveFromSeat room=$roomId seat=$seatNumber target=$targetUserId');

    // ✅ OPTIMISTIC release in UI
    final current = Map<int, SeatData>.from(state.seats);
    final old = current[seatNumber];
    if (old != null) {
      current[seatNumber] = SeatData(
        seatNumber: seatNumber,
        userId: null,
        username: null,
        avatarUrl: null,
        avatarFrameUrl: null, // ADD THIS LINE
        level: 0,
        isMuted: true,
        isLocked: old.isLocked,
      );

      state = state.copyWith(seats: current);
    }

    // ✅ ADMIN kick (use service helper)
    _socket.adminRemoveFromSeat(
      roomId: roomId,
      seatNumber: seatNumber,
      targetUserId: targetUserId,
    );

    // ✅ Force refresh so all devices reflect it fast
    _socket.emit('get_room_seats_state', {'roomId': roomId});
    _socket.emit('request_room_seats_state', {'roomId': roomId});
    _socket.getVoiceUsers(roomId: roomId);
  }



  Future<void> openRoom() async {
    if (state.isOpen || _opening) return;
    _opening = true;

    try {
      final user = ref.read(authStateProvider).user;
      if (user == null) return;

      await _socket.waitUntilConnected(timeout: const Duration(seconds: 10));
      if (!_socket.isConnected) return;

      _socket.joinRoom(roomId: roomId, userId: user.id, username: user.name);
      _socket.getVoiceUsers(roomId: roomId); // ✅ request voice users snapshot

      _bindStreams();
      // after joinRoom + bindStreams
      final room = ref.read(roomsProvider).findById(roomId); // or call /rooms/:id
      final maxSeats = room?.maxSeats;
      if (maxSeats != null && maxSeats > 0) {
        state = state.copyWith(seatCount: maxSeats);
      }


      state = state.copyWith(isOpen: true);
    } finally {
      _opening = false;
    }
  }


  void closeRoom() {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    _socket.leaveRoom(roomId: roomId, userId: user.id);
    print('🚪 closeRoom() room=$roomId');

    _seatLockSub?.cancel();
    _seatLockSub = null;
    _socket.off('seat_lock');

    // cancel typed streams
    _msgSub?.cancel();
    _seatSub?.cancel();
    _seatsStateSub?.cancel();
    _msgSub = null;
    _seatSub = null;
    _seatsStateSub = null;
    _voiceUsersSub?.cancel();
    _voiceUsersSub = null;
    _approveMicSub?.cancel();
    _approveMicSub = null;

    _reconnectSub?.cancel(); // ✅ ADD
    _reconnectSub = null;    // ✅ ADD

    // remove raw listeners to avoid duplicates
    _socket.off('mic_queue_updated');
    _socket.off('seat_occupied');
    _socket.off('seat_released');
    _socket.off('seat_updated');

    state = state.copyWith(isOpen: false);

    print('🔗 binding streams room=$roomId');

  }

  void _bindStreams() {
    _msgSub?.cancel();
    _seatSub?.cancel();
    _seatsStateSub?.cancel();

    _msgSub = _socket.messageStream.listen((m) {
      final next = [...state.messages, m];
      state = state.copyWith(messages: next);
      print('💬 messageStream room=$roomId from=${m.userId} name=${m.username} msg=${m.message}');

    });

    _socket.on('user_joined', (data) {
      if (data is! Map) return;

      final username = data['username'] ?? 'مستخدم';

      addActivity(
        'انضم إلى الغرفة',
        RoomEventType.join,
        username: username?.toString(),
        countryCode: data['countryCode']?.toString() ?? data['country']?.toString(),
        gender: data['gender']?.toString(),
      );
    });

    _socket.on('user_left', (data) {
      if (data is! Map) return;

      final username = data['username'] ?? 'مستخدم';

      addActivity(
        'غادر الغرفة',
        RoomEventType.leave,
        username: username?.toString(),
        countryCode: data['countryCode']?.toString() ?? data['country']?.toString(),
        gender: data['gender']?.toString(),
      );
    });

    // ✅ This snapshot is the source of truth
    _seatsStateSub = _socket.roomStateStream.listen((s) {
      final nextSeats = <int, SeatData>{};

      for (final seat in s.seats) {
        final old = state.seats[seat.seatNumber];

        nextSeats[seat.seatNumber] = SeatData(
          seatNumber: seat.seatNumber,
          userId: seat.userId,
          username: seat.username,
          avatarUrl: seat.avatarUrl,
          relationPartner: seat.relationPartner ?? old?.relationPartner,

          // ✅ KEEP OLD FRAME IF SNAPSHOT IS NULL
          avatarFrameUrl: seat.avatarFrameUrl ?? old?.avatarFrameUrl,

          level: seat.level,
          isMuted: seat.isMuted,
          isLocked: seat.isLocked,
        );
      }

      final nextCount = s.seatCount > 0 ? s.seatCount : state.seatCount;
      final ensureSeatsUpTo = (nextCount <= 0 ? 9 : nextCount).clamp(1, 24);

      for (int i = 1; i <= ensureSeatsUpTo; i++) {
        nextSeats.putIfAbsent(i, () => SeatData(
          seatNumber: i,
          userId: null,
          username: null,
          avatarUrl: null,
          level: 0,
          isMuted: true,
          isLocked: false,
        ));
      }

      // ✅ STEP 3: derive lockedSeats from snapshot
      final lockedFromSeats = nextSeats.values
          .where((x) => x.isLocked)
          .map((x) => x.seatNumber)
          .toSet();

      state = state.copyWith(
        seats: nextSeats,
        ownerId: s.ownerId,
        adminIds: s.adminIds,
        seatCount: ensureSeatsUpTo,
        lockedSeats: lockedFromSeats.isNotEmpty ? lockedFromSeats : state.lockedSeats,
      );

      print('📦 [room_seats_state] room=$roomId owner=${s.ownerId} admins=${s.adminIds} seats=${nextSeats.length}');
    });


    // ✅ keep your existing typed stream, but DO NOT rely on it
    // because SeatUpdate parsing may be wrong.
    _seatSub = _socket.seatUpdateStream.listen((u) {
      if (u.seatNumber == null) return;

      if (u.type == SeatUpdateType.muteChanged && u.isMuted != null) {
        final current = Map<int, SeatData>.from(state.seats);
        final old = current[u.seatNumber!];
        if (old != null) {
          current[u.seatNumber!] = SeatData(
            seatNumber: old.seatNumber,
            userId: old.userId,
            username: old.username,
            avatarUrl: old.avatarUrl,
            level: old.level,
            isMuted: u.isMuted!,
            isLocked: old.isLocked,
          );


          state = state.copyWith(seats: current);
        }
        print('✅ applied muteChanged seat=${u.seatNumber} muted=${u.isMuted}');
      }
    });

    _seatLockSub?.cancel();
    _seatLockSub = _socket.seatLockStream.listen((data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);

      final rid = _safeInt(map['roomId']) ?? _safeInt(map['room_id']);
      if (rid != roomId) return;

      final sn = _safeInt(map['seatNumber']) ?? _safeInt(map['seat_number']);
      if (sn == null) return;

      final locked = (map['locked'] == true) || (map['locked']?.toString() == 'true');

      // ✅ 1) update lockedSeats set
      setSeatLockedLocal(seatNumber: sn, locked: locked);

      // ✅ 2) also update SeatData.isLocked so snapshot/UI stays consistent
      final current = Map<int, SeatData>.from(state.seats);
      final old = current[sn] ?? SeatData.empty(sn);
      current[sn] = SeatData(
        seatNumber: old.seatNumber,
        userId: old.userId,
        username: old.username,
        avatarUrl: old.avatarUrl,
        level: old.level,
        isMuted: old.isMuted,
        isLocked: locked,
      );
      state = state.copyWith(seats: current);

      print('🔒 seat_lock applied room=$roomId seat=$sn locked=$locked');
    });


    _approveMicSub?.cancel();
    _approveMicSub = _socket.approveMicStream.listen((data) {
      final rid = _safeInt(data['roomId']) ?? _safeInt(data['room_id']);
      if (rid != roomId) return;

      final me = ref.read(authStateProvider).user?.id;
      if (me == null) return;

      // backend may send targetUserId/userId
      final target = _safeInt(data['targetUserId']) ??
          _safeInt(data['userId']) ??
          _safeInt(data['user_id']);

      if (target != me) return;

      print('✅ approveMic received for ME in room=$roomId');

      // ✅ Immediately reflect approval so button changes & user can't re-raise
      state = state.copyWith(
        myMicStatus: MyMicStatus.approved,
        micQueue: state.micQueue.where((id) => id != me).toList(), // remove me locally
      );

      // ✅ Force refresh snapshots so seats stop showing “available”
      _socket.getVoiceUsers(roomId: roomId);
      _socket.emit('get_room_seats_state', {'roomId': roomId});
      _socket.emit('request_room_seats_state', {'roomId': roomId});
    });

    _reconnectSub?.cancel(); // ✅ cancel any previous subscription first
    _reconnectSub = _socket.reconnectStream.listen((_) async {
      final user = ref.read(authStateProvider).user;
      if (user == null) return;
      print('🔁 reconnect -> rejoin room=$roomId');
      _socket.joinRoom(roomId: roomId, userId: user.id, username: user.name);
      _socket.emit('get_room_seats_state', {'roomId': roomId});
      _socket.emit('request_room_seats_state', {'roomId': roomId});
      _socket.getVoiceUsers(roomId: roomId);
    });


    print('🔗 streams bound room=$roomId');

    // ----------------------------
    // RAW socket listeners (source of truth)
    // ----------------------------

    _socket.on('seat_error', (data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);

      final rid = _safeInt(map['roomId']) ?? _safeInt(map['room_id']);
      if (rid != roomId) return;

      final sn = _safeInt(map['seatNumber']) ?? _safeInt(map['seat_number']);
      if (sn == null) return;

      // rollback only if it was my pending optimistic seat
      if (_pendingSeatNumber == sn) {
        final current = Map<int, SeatData>.from(state.seats);
        final old = current[sn];

        if (old != null) {
          current[sn] = SeatData(
            seatNumber: sn,
            userId: null,
            username: null,
            avatarUrl: null,
            level: 0,
            isMuted: true,
            isLocked: old.isLocked,
          );
          state = state.copyWith(seats: current, myMicStatus: MyMicStatus.none);
        }

        _pendingSeatNumber = null;

        // force refresh snapshot to be safe
        _socket.emit('get_room_seats_state', {'roomId': roomId});
      }
    });

    _socket.on('seat_occupied', (data) {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        _applySeatOccupiedFromRaw(map);
        final username = map['username'] ?? map['name'] ?? 'Someone';
        addActivity(
          "$username أخد مقعد 🎤",
          RoomEventType.seat,
          username: username,
          badge: map['badge']?.toString(),
          coins: _safeInt(map['coins']),
          countryCode: map['countryCode']?.toString() ?? map['country']?.toString(),
          gender: map['gender']?.toString(),
        );
      }
    });

    _socket.on('seat_released', (data) {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);

        _applySeatReleasedFromRaw(map);

        addActivity(
          "اصبح المقعد متاح الأن",
          RoomEventType.seat,
          username: map['username']?.toString() ?? map['name']?.toString(),
          countryCode: map['countryCode']?.toString() ?? map['country']?.toString(),
          gender: map['gender']?.toString(),
        );
      }
    });

    _socket.on('seat_updated', (data) {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        _applySeatUpdatedFromRaw(map);
      }
    });

    _socket.on('seat_mute_changed', (data) {
      print('🧪 RAW seat_mute_changed => $data');
    });

    // In initSubscriptions / wherever you handle socket events:
    _socket.on('relation_ended', (_) {
      // Force reload room state so relation badge clears
      _socket.emit('init_room_seats', {'roomId': roomId});
    });

    _socket.on('mic_queue_updated', (data) {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final rawQueue = map['queue'];

        final q = (rawQueue is List)
            ? rawQueue
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList()
            : <int>[];

        state = state.copyWith(micQueue: q);

        final me = ref.read(authStateProvider).user?.id;
        MyMicStatus nextStatus = state.myMicStatus;

        if (me != null) {
          final onMic = state.voiceUserIds.contains(me) ||
              state.seats.values.any((s) => s.userId == me);

          if (onMic) {
            nextStatus = MyMicStatus.onMic;
          } else if (q.contains(me)) {
            nextStatus = MyMicStatus.requested;
          } else if (state.myMicStatus == MyMicStatus.requested) {
            // I was requested but removed (maybe rejected/canceled/approved)
            // Don't force to none; approve event will set approved.
            nextStatus = state.myMicStatus;
          }
        }

        state = state.copyWith(micQueue: q, myMicStatus: nextStatus);

      }
    });

    _voiceUsersSub?.cancel();
    _voiceUsersSub = _socket.voiceUsersStream.listen((data) {
      final rid = _safeInt(data['roomId']) ?? _safeInt(data['room_id']);
      if (rid != roomId) return;

      final raw = data['users'];

      final users = (raw is List)
          ? raw.map((e) {
        if (e is int) return e;
        if (e is num) return e.toInt(); // ✅ IMPORTANT FIX (handles 33.0)
        if (e is String) return int.tryParse(e);
        if (e is Map && e['userId'] != null) return int.tryParse('${e['userId']}');
        return null;
      }).whereType<int>().where((id) => id > 0).toList()
          : <int>[];

      print('👥 voice_users in room $roomId: $users');
      state = state.copyWith(voiceUserIds: users); // ✅ ADD

      final me = ref.read(authStateProvider).user?.id;
      if (me != null && users.contains(me)) {
        // ✅ confirmed by voice snapshot that I am in voice
        if (state.myMicStatus != MyMicStatus.onMic) {
          state = state.copyWith(myMicStatus: MyMicStatus.onMic);
        }
      }

      // ✅ OPTION A: keep it only for logs
      // ✅ OPTION B: if you want to store it in state, add a field in RoomControllerState
    });

  }

// ----------------------------
// Helpers: apply raw socket payloads
// ----------------------------

  void _applySeatOccupiedFromRaw(Map<String, dynamic> map) {

    print("🔍 RAW seat_occupied map: $map");
    // backend sometimes sends seatNumber OR seat_number OR number
    final seatNumber = _safeInt(map['seatNumber']) ??
        _safeInt(map['seat_number']) ??
        _safeInt(map['number']);

    if (seatNumber == null || seatNumber <= 0) return;

    final userId = _safeInt(map['userId']) ?? _safeInt(map['user_id']);
    final username = (map['username'] ?? map['name'])?.toString();
    final avatarUrl = (map["avatarUrl"] ?? map["avatar_url"])?.toString();
    final avatarFrameUrl = (map["avatarFrameUrl"] ?? map["avatar_frame_url"] ?? map["frameImageUrl"])?.toString(); // ADD THIS LINE
    final level = _safeInt(map["level"]) ?? 0;
    final isMuted = (map["isMuted"] is bool) ? map["isMuted"] as bool : null;
    print("🔍 parsed avatarFrameUrl: $avatarFrameUrl"); // ADD THIS

    final current = Map<int, SeatData>.from(state.seats);
    final old = current[seatNumber] ??
        SeatData(
          seatNumber: seatNumber,
          userId: null,
          username: null,
          avatarUrl: null,
          level: 0,
          isMuted: true,
          isLocked: false,
        );

    current[seatNumber] = SeatData(
      seatNumber: seatNumber,
      userId: userId ?? old.userId,
      username: username ?? old.username,
      avatarUrl: avatarUrl ?? old.avatarUrl,
      avatarFrameUrl: avatarFrameUrl ?? old.avatarFrameUrl, // ADD THIS LINE
      level: level == 0 ? old.level : level,
      isMuted: isMuted ?? old.isMuted,
      isLocked: old.isLocked,
    );


    state = state.copyWith(seats: current);

    final me = ref.read(authStateProvider).user?.id;
    final appliedUserId = userId ?? old.userId;
    if (me != null && appliedUserId == me) {
      // ✅ I got seated (on mic)
      if (state.myMicStatus != MyMicStatus.onMic) {
        state = state.copyWith(myMicStatus: MyMicStatus.onMic);
      }
    }

    if (me != null && appliedUserId == me) {
      _pendingSeatNumber = null;
      if (state.myMicStatus != MyMicStatus.onMic) {
        state = state.copyWith(myMicStatus: MyMicStatus.onMic);
      }
    }

  }

  void moveSeat({
    required int fromSeat,
    required int toSeat,
  }) {
    final updatedSeats = Map<int, SeatData>.from(state.seats);

    final mySeat = updatedSeats[fromSeat];

    if (mySeat != null) {
      updatedSeats[fromSeat] = SeatData.empty(fromSeat);
      updatedSeats[toSeat] = SeatData(
        seatNumber: toSeat,
        userId: mySeat.userId,
        username: mySeat.username,
        avatarUrl: mySeat.avatarUrl,
        avatarFrameUrl: mySeat.avatarFrameUrl,
        level: mySeat.level,
        isMuted: mySeat.isMuted,
        isLocked: mySeat.isLocked,
        isSpeaking: mySeat.isSpeaking,
      );
    }

    state = state.copyWith(seats: updatedSeats);

    // 🔥 emit to backend
    _socket.emit('moveSeat', {
      'roomId': roomId,
      'fromSeat': fromSeat,
      'toSeat': toSeat,
    });

    print("🔁 moveSeat from $fromSeat → $toSeat");
  }

  void setUserSpeaking(int userId, bool isSpeaking) {
    if (state.seats.isEmpty) return; // ✅ ADD THIS

    state = state.copyWith(
      seats: {
        for (final entry in state.seats.entries)
          entry.key: entry.value.userId == userId
              ? entry.value.copyWith(isSpeaking: isSpeaking)
              : entry.value,
      },
    );
  }

  void _applySeatReleasedFromRaw(Map<String, dynamic> map) {
    final seatNumber =
        _safeInt(map['seatNumber']) ?? _safeInt(map['seat_number']);
    print('🪑 APPLY seat_released room=$roomId seat=$seatNumber');

    if (seatNumber == null || seatNumber <= 0) return;

    final current = Map<int, SeatData>.from(state.seats);
    final old = current[seatNumber];
    if (old == null) return;

    current[seatNumber] = SeatData(
      seatNumber: seatNumber,
      userId: null,
      username: null,
      avatarUrl: null,
      avatarFrameUrl: null, // ADD THIS LINE
      level: 0,
      isMuted: true,
      isLocked: old.isLocked,
    );


    state = state.copyWith(seats: current);
  }

  void _applySeatUpdatedFromRaw(Map<String, dynamic> map) {
    final seatNumber = _safeInt(map['seatNumber']) ??
        _safeInt(map['seat_number']) ??
        _safeInt(map['seatId']) ??
        _safeInt(map['seat_id']);
    if (seatNumber == null || seatNumber <= 0) return;

    final userId = _safeInt(map['userId']) ?? _safeInt(map['user_id']);
    final micEnabled = map['micEnabled'] == true;
    final isSpeaking = map['isSpeaking'] == true;

    final current = Map<int, SeatData>.from(state.seats);
    final old = current[seatNumber] ?? SeatData.empty(seatNumber);

    current[seatNumber] = SeatData(
      seatNumber: seatNumber,
      userId: userId,
      username: userId == null ? null : old.username,
      avatarUrl: userId == null ? null : old.avatarUrl,
      avatarFrameUrl: userId == null ? null : old.avatarFrameUrl,
      level: userId == null ? 0 : old.level,
      isMuted: !micEnabled,
      isLocked: old.isLocked,
      isSpeaking: isSpeaking,
    );

    state = state.copyWith(seats: current);
  }

  int? _safeInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt(); // ✅ handles 33.0
    return int.tryParse(v.toString());
  }



  // ----------------------------
  // Chat
  // ----------------------------

  void sendRoomMessage({required String message}) {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    _socket.sendRoomMessage(
      roomId: roomId,
      userId: user.id,
      username: user.name,
      message: message,
    );
  }

  void sendTyping({required bool isTyping}) {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    _socket.sendTyping(
      roomId: roomId,
      userId: user.id,
      username: user.name,
      isTyping: isTyping,
    );
  }

  // ----------------------------
  // Mic queue
  // ----------------------------

// ----------------------------
// Mic queue
// ----------------------------

  void requestMic() {
    final me = ref.read(authStateProvider).user?.id;
    if (me == null) return;

    // ✅ Block re-request if already pending/approved/onMic
    final alreadyPending = state.micQueue.contains(me);
    final alreadyOnMic = state.voiceUserIds.contains(me) || state.seats.values.any((s) => s.userId == me);

    if (alreadyPending || alreadyOnMic || state.myMicStatus == MyMicStatus.approved) {
      print('⛔ requestMic blocked (already pending/approved/onMic)');
      return;
    }

    print('🎙️ requestMic room=$roomId byUser=$me');
    state = state.copyWith(myMicStatus: MyMicStatus.requested); // ✅ optimistic
    _socket.requestMic(roomId: roomId);
  }


  void cancelMic() {
    print('🎙️ cancelMic room=$roomId');
    state = state.copyWith(myMicStatus: MyMicStatus.none); // ✅ optimistic
    _socket.cancelMicRequest(roomId: roomId);
  }

  void leaveSeat({required int seatNumber}) {
    final me = ref.read(authStateProvider).user?.id;
    if (me == null) return;

    final seat = state.seats[seatNumber];
    if (seat == null) return;

    // only leave if I'm the occupant
    if (seat.userId != me) {
      print('⛔ leaveSeat blocked: not my seat (seat=$seatNumber, seatUser=${seat.userId}, me=$me)');
      return;
    }

    print('🚪 leaveSeat room=$roomId seat=$seatNumber me=$me');


    // ✅ optimistic UI release
    final current = Map<int, SeatData>.from(state.seats);
    final old = current[seatNumber];
    if (old != null) {
      current[seatNumber] = SeatData(
        seatNumber: seatNumber,
        userId: null,
        username: null,
        avatarUrl: null,
        level: 0,
        isMuted: true,
        isLocked: old.isLocked,
      );
      state = state.copyWith(seats: current);

      // if I was on mic, downgrade status
      if (state.myMicStatus == MyMicStatus.onMic) {
        state = state.copyWith(myMicStatus: MyMicStatus.none);
      }
    }

    addActivity(
      "لقد تركت مقعدك",
      RoomEventType.seat,
      username: ref.read(authStateProvider).user?.name,
      countryCode: ref.read(authStateProvider).user?.countryCode,
      gender: ref.read(authStateProvider).user?.gender,
    );

    // ✅ backend
    _socket.leaveSeat(roomId: roomId, seatNumber: seatNumber);

    // ✅ refresh
    _socket.emit('get_room_seats_state', {'roomId': roomId});
    _socket.emit('request_room_seats_state', {'roomId': roomId});
    _socket.getVoiceUsers(roomId: roomId);
  }

  void approveMic({required int userId}) {
    print('✅ approveMic room=$roomId userId=$userId');
    _socket.approveMic(roomId: roomId, userId: userId);
  }

  void rejectMic({required int userId}) {
    print('❌ rejectMic room=$roomId userId=$userId');
    _socket.rejectMic(roomId: roomId, userId: userId);
  }

  // ----------------------------
  // Seat controls
  // ----------------------------

  // ----------------------------
// Seat controls (FREE MIC MODE)
// ----------------------------
  Future<void> takeSeat({required int seatNumber}) async {
    final me = ref.read(authStateProvider).user;
    if (me == null) return;

    // ✅ Ensure room is open/joined and socket is connected
    if (!state.isOpen) {
      await openRoom();
    }
    await _socket.waitUntilConnected(timeout: const Duration(seconds: 8));
    if (!_socket.isConnected) {
      print('❌ takeSeat aborted: socket not connected');
      return;
    }

    // Block if I'm already seated
    final alreadySeated = state.seats.values.any((s) => s.userId == me.id);
    if (alreadySeated) {
      print('⛔ takeSeat blocked: already seated');
      return;
    }

    // Block if seat occupied
    final currentSeat = state.seats[seatNumber];
    if (currentSeat != null && currentSeat.userId != null) {
      print('⛔ takeSeat blocked: seat occupied');
      return;
    }

    print('🪑 takeSeat EMIT room=$roomId seat=$seatNumber me=${me.id}');

    // ✅ Now it's safe to do optimistic UI
    _pendingSeatNumber = seatNumber;

    final current = Map<int, SeatData>.from(state.seats);
    final old = current[seatNumber] ?? SeatData.empty(seatNumber);

    current[seatNumber] = SeatData(
      seatNumber: seatNumber,
      userId: me.id,
      username: me.name,
      avatarUrl: me.avatarUrl,
      level: me.level ?? 0,
      isMuted: true,
      isLocked: old.isLocked,
    );
    state = state.copyWith(seats: current, myMicStatus: MyMicStatus.requested);

    addActivity(
      "${me.name} أخد مقعد",
      RoomEventType.seat,
      username: me.name,   // ✅ ADD
      countryCode: me.countryCode,
      gender: me.gender,
    );

    // ✅ Emit ONLY after connected
    // ✅ Emit via SocketService helper
    final frameUrl = ref.read(authStateProvider).user?.avatarFrameUrl;

    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    print("🧪 MY FRAME BEFORE EMIT: ${user.avatarFrameUrl}");

    _socket.takeSeat(
      roomId: roomId,
      seatNumber: seatNumber,
      userId: me.id,
      username: me.name,
      avatarUrl: me.avatarUrl,
      avatarFrameUrl: user.avatarFrameUrl, // ✅ FIX HERE
    );

    // ✅ Refresh snapshot (optional but ok)
    _socket.emit('get_room_seats_state', {'roomId': roomId});
    _socket.emit('request_room_seats_state', {'roomId': roomId});
  }



  // Seat controls
  void toggleMute({
    required int seatNumber,
    required bool isMuted,
    int? targetUserId,
  }) {
    final me = ref.read(authStateProvider).user?.id;
    if (me == null) return;

    final seat = state.seats[seatNumber];
    if (seat == null) return;

    final int? resolvedTarget = targetUserId ?? seat.userId;
    if (resolvedTarget == null) return;

    final bool isSelf = resolvedTarget == me;

    // optimistic UI update
    final current = Map<int, SeatData>.from(state.seats);
    final old = current[seatNumber];
    if (old != null) {
      current[seatNumber] = SeatData(
        seatNumber: old.seatNumber,
        userId: old.userId,
        username: old.username,
        avatarUrl: old.avatarUrl,
        level: old.level,
        isMuted: isMuted,
        isLocked: old.isLocked,
      );
      state = state.copyWith(seats: current);
    }

    if (isSelf) {
      // ✅ SELF -> backend expects toggle_mute
      _socket.toggleMute(
        roomId: roomId,
        seatNumber: seatNumber,
        isMuted: isMuted,
        userId: me,
      );
    } else {
      // ✅ ADMIN moderation -> backend expects set_seat_mute
      _socket.setSeatMute(
        roomId: roomId,
        seatNumber: seatNumber,
        targetUserId: resolvedTarget,
        mute: isMuted,
      );
    }

    // refresh snapshot
    _socket.emit('get_room_seats_state', {'roomId': roomId});
    _socket.emit('request_room_seats_state', {'roomId': roomId});
    _socket.getVoiceUsers(roomId: roomId);
  }







  // ----------------------------
  // Gifts
  // ----------------------------

  void sendGift({
    required int receiverId,
    required int giftId,
    int quantity = 1,
    String? message,
  }) {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;
    _socket.sendGift(
      roomId: roomId,
      receiverId: receiverId,
      giftId: giftId,
      quantity: quantity,
      message: message,
    );
  }

  void clearMessages() {
    state = state.copyWith(messages: const <SocketMessage>[]);
  }


  @override
  void dispose() {
    _msgSub?.cancel();
    _seatSub?.cancel();
    _seatsStateSub?.cancel();
    _voiceUsersSub?.cancel();
    _approveMicSub?.cancel();
    _seatLockSub?.cancel();
    _reconnectSub?.cancel(); // ✅ ADD
    closeRoom();
    super.dispose();
  }



}

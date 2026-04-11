// lib/models/room_state.dart
import 'package:samafox/models/user.dart';

import '../services/socket_service.dart';
import 'RoomMemberView.dart';
import '../models/room_event.dart';
// lib/models/room_state.dart

class RoomState {
  final int id;
  final String name;
  final int membersCount;
  final String? coverImageUrl;
  final String? backgroundImageUrl;
  final int maxSeats;

  final List<RoomEvent> events; // ✅ ONLY ONE
  final Map<int, User> onlineUsers;
  final List<RoomMemberView>? users;
  final int? ownerId;
  // runtime
  final List<RoomSeat> seats;
  final List<int> micQueue;

  final List<SocketMessage> roomMessages;

  RoomState({
    required this.id,
    required this.name,
    required this.membersCount,
    required this.maxSeats,
    this.coverImageUrl,
    this.backgroundImageUrl,
    this.users,
    this.seats = const [],
    this.micQueue = const [],
    this.roomMessages = const [],
    this.events = const [], // ✅ FIXED
    this.onlineUsers = const {},
    this.ownerId, // ✅ ADD THIS
  });

  factory RoomState.fromJson(Map<String, dynamic> json) {
    return RoomState(
      id: json['id'] ?? json['roomId'] ?? 0,
      name: (json['name'] ?? '').toString(),

      membersCount: json['membersCount'] ?? json['members_count'] ?? 0,
      ownerId: json['ownerId'] ?? json['owner_id'], // ✅ ADD HERE
      coverImageUrl: json['coverImageUrl'] ?? json['cover_image_url'],
      backgroundImageUrl: json['backgroundImageUrl'] ?? json['background_image_url'],
      maxSeats: json['maxSeats'] ?? json['max_seats'] ?? 8,
      users: ((json['users'] as List?) ?? (json['members'] as List?))
          ?.map((e) => RoomMemberView.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      seats: const [],
      micQueue: const [],
      roomMessages: const [],
      events: const [], // ✅ FIXED

    );
  }

  RoomState copyWith({
    int? maxSeats,
    List<RoomSeat>? seats,
    List<int>? micQueue,
    List<SocketMessage>? roomMessages,
    List<RoomMemberView>? users,
    List<RoomEvent>? events, // ✅ FIXED
    Map<int, User>? onlineUsers,
  }) {
    return RoomState(
      id: id,
      name: name,
      membersCount: membersCount,
      coverImageUrl: coverImageUrl,
      backgroundImageUrl: backgroundImageUrl,
      maxSeats: maxSeats ?? this.maxSeats,
      users: users ?? this.users,
      seats: seats ?? this.seats,
      micQueue: micQueue ?? this.micQueue,
      roomMessages: roomMessages ?? this.roomMessages,
      events: events ?? this.events, // ✅ FIXED
      onlineUsers: onlineUsers ?? this.onlineUsers,
    );
  }


  // ================= Seats apply helpers =================

  RoomState applySeatsState(Map<String, dynamic> payload) {
    final list = (payload['seats'] as List? ?? const []);
    final newSeats = list
        .map((e) => RoomSeat.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return copyWith(seats: newSeats);
  }

  RoomState applySeatOccupied(Map<String, dynamic> data) {
    final seatNumber = data['seatNumber'] ?? 0;
    final updated = seats.map((s) {
      if (s.seatNumber == seatNumber) return s.copyWith(
        userId: data['userId'],
        username: data['username'],
        avatarUrl: data['avatarUrl'],
        level: data['level'],
        isMuted: data['isMuted'] ?? true,
        avatarFrameUrl: data['avatarFrameUrl'],
      );
      return s;
    }).toList();
    return copyWith(seats: updated);
  }

  RoomState applySeatReleased(Map<String, dynamic> data) {
    final seatNumber = data['seatNumber'] ?? 0;
    final updated = seats.map((s) {
      if (s.seatNumber == seatNumber) return RoomSeat.empty(seatNumber);
      return s;
    }).toList();
    return copyWith(seats: updated);
  }

  RoomState applyUserMuteToggled(Map<String, dynamic> data) {
    final seatNumber = data['seatNumber'] ?? 0;
    final updated = seats.map((s) {
      if (s.seatNumber == seatNumber) return s.copyWith(isMuted: data['isMuted'] ?? true);
      return s;
    }).toList();
    return copyWith(seats: updated);
  }

  // ================= Snapshot apply (room_state) =================
  RoomState applyRoomSnapshot(Map<String, dynamic> snap) {
    final maxSeatsNew = (snap['maxSeats'] is int) ? snap['maxSeats'] as int : maxSeats;

    // seats may come as List<Map> or already in correct format
    final seatsList = (snap['seats'] as List?) ?? const [];
    final mappedSeats = seatsList.map((e) => RoomSeat.fromJson(Map<String, dynamic>.from(e))).toList();

    // micQueue may come as list
    final q = (snap['micQueue'] as List?) ?? (snap['queue'] as List?) ?? const [];
    final queue = q.map((x) => int.tryParse('$x') ?? 0).where((x) => x > 0).toList();

    return copyWith(
      maxSeats: maxSeatsNew,
      seats: mappedSeats.isNotEmpty ? mappedSeats : seats,
      micQueue: queue.isNotEmpty ? queue : micQueue,
    );
  }

  // ================= Chat apply =================
  RoomState addSocketMessage(SocketMessage m) {
    final newList = [...roomMessages, m];
    // keep last 200
    final trimmed = newList.length > 200 ? newList.sublist(newList.length - 200) : newList;
    return copyWith(roomMessages: trimmed);
  }
}

class RoomSeat {
  final int seatNumber;
  final int? userId;
  final String? username;
  final String? avatarUrl;
  final int level;
  final bool isMuted;
  final bool isLocked;
  final String? avatarFrameUrl;


  RoomSeat({
    required this.seatNumber,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.level,
    required this.isMuted,
    required this.isLocked,
    this.avatarFrameUrl,

  });

  factory RoomSeat.empty(int i) => RoomSeat(
    seatNumber: i,
    userId: null,
    username: null,
    avatarUrl: null,
    level: 0,
    isMuted: true,
    isLocked: false,
  );

  factory RoomSeat.fromJson(Map<String, dynamic> json) {

    print("🔥 FROM JSON FRAME: ${json['avatarFrameUrl']}");

    return RoomSeat(
      seatNumber: json['seatNumber'] ?? 0,
      userId: json['userId'],
      username: json['username'],
      avatarUrl: json['avatarUrl'],
      avatarFrameUrl: json['avatarFrameUrl'], // ✅🔥 THIS LINE
      level: json['level'] ?? 0,
      isMuted: json['isMuted'] ?? true,
      isLocked: json['isLocked'] ?? false,
    );
  }

  RoomSeat copyWith({
    int? userId,
    String? username,
    String? avatarUrl,
    int? level,
    bool? isMuted,
    bool? isLocked,
    String? avatarFrameUrl,

  }) {
    return RoomSeat(
      seatNumber: seatNumber,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      isMuted: isMuted ?? this.isMuted,
      isLocked: isLocked ?? this.isLocked,
      avatarFrameUrl: avatarFrameUrl ?? this.avatarFrameUrl,

    );
  }
}

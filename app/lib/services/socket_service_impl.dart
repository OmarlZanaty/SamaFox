import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';
import '../utils/logger.dart';
import '../services/socket_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _token; // ✅ REQUIRED — was missing, causing "Undefined name '_token'"

  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<SocketMessage>.broadcast();
  final _userEventController = StreamController<SocketUserEvent>.broadcast();
  final _seatUpdateController = StreamController<SeatUpdate>.broadcast();
  final _roomStateController = StreamController<RoomSeatsState>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<SocketMessage> get messageStream => _messageController.stream;
  Stream<SocketUserEvent> get userEventStream => _userEventController.stream;
  Stream<SeatUpdate> get seatUpdateStream => _seatUpdateController.stream;
  Stream<RoomSeatsState> get roomStateStream => _roomStateController.stream;

  bool get isConnected => _socket?.connected ?? false;

  String _cleanJwt(String t) {
    var x = t.trim();

    if (x.startsWith('Bearer ')) x = x.substring(7).trim();

    if (x.startsWith('"') && x.endsWith('"') && x.length > 2) {
      x = x.substring(1, x.length - 1);
    }

    if (x.startsWith("'") && x.endsWith("'") && x.length > 2) {
      x = x.substring(1, x.length - 1);
    }

    return x;
  }

  void connect(String token) {
    final jwt = _cleanJwt(token);
    if (jwt.isEmpty) return;

    final parts = jwt.split('.');
    if (parts.length != 3) {
      AppLogger.error('Token malformed: ${parts.length} parts');
      return;
    }

    _token = jwt; // ✅ set FIRST before anything else

    if (_socket != null) {
      try {
        _socket!.clearListeners();
        _socket!.disconnect();
        _socket!.dispose();
      } catch (_) {}
      _socket = null;
    }

    final options = IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(AppConfig.socketReconnectionAttempts)
        .setReconnectionDelay(AppConfig.socketReconnectionDelay)
        .setAuth({'token': jwt}) // ✅ USE jwt, NOT original token
        .build();

    _socket = IO.io(AppConfig.socketUrl, options);

    _socket!.onConnectError((e) => print("❌ CONNECT ERROR: $e"));
    _socket!.onError((e) => print("❌ SOCKET ERROR: $e"));

    _setupListeners();
    _socket!.connect();

    AppLogger.info('Socket connection initiated (auth token set)');
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connectionController.add(false);
    AppLogger.info('Socket disconnected');
  }

  void takeSeat({
    required int roomId,
    required int seatNumber,
    required int userId,
    required String username,
    String? avatarUrl,
  }) {
    emit('take_seat', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'userId': userId,
      'username': username,
      'avatarUrl': avatarUrl,
    });
  }

  void _setupListeners() {
    _socket!.onConnect((_) {
      AppLogger.info('✅ Socket connected! token=${_token?.substring(0, 20)}...');
      _connectionController.add(true);
    });

    _socket!.onDisconnect((_) {
      AppLogger.info('❌ Socket disconnected');
      _connectionController.add(false);
    });

    _socket!.onConnectError((error) {
      AppLogger.error('Socket connection error: $error');
      _connectionController.add(false);
    });

    _socket!.onError((error) {
      AppLogger.error('Socket error: $error');
    });

    _socket!.onReconnect((_) {
      AppLogger.info('🔁 Socket reconnected');
      // Re-apply token on reconnect
      final t = _token;
      if (t != null && t.isNotEmpty) {
        _socket?.auth = {'token': t};
      }
      _connectionController.add(true);
    });

    _socket!.on('reconnect_attempt', (attempt) {
      AppLogger.info('Socket reconnection attempt: $attempt');
    });

    _socket!.on('reconnect_error', (error) {
      AppLogger.error('Socket reconnection error: $error');
    });

    _socket!.on('reconnect_failed', (_) {
      AppLogger.error('Socket reconnection failed after all attempts');
    });

    _socket!.on('new_message', (data) {
      try {
        final message = SocketMessage.fromJson(Map<String, dynamic>.from(data));
        _messageController.add(message);
      } catch (e) {
        AppLogger.error('Error parsing new message: $e');
      }
    });

    _socket!.on('user_joined', (data) {
      try {
        final event = SocketUserEvent.fromJson(
          Map<String, dynamic>.from(data),
          UserEventType.joined,
        );
        _userEventController.add(event);
      } catch (e) {
        AppLogger.error('Error parsing user joined: $e');
      }
    });

    _socket!.on('user_left', (data) {
      try {
        final event = SocketUserEvent.fromJson(
          Map<String, dynamic>.from(data),
          UserEventType.left,
        );
        _userEventController.add(event);
      } catch (e) {
        AppLogger.error('Error parsing user left: $e');
      }
    });

    _socket!.on('typing', (data) {
      try {
        final event = SocketUserEvent.fromJson(
          Map<String, dynamic>.from(data),
          UserEventType.typing,
        );
        _userEventController.add(event);
      } catch (e) {
        AppLogger.error('Error parsing typing event: $e');
      }
    });

    _socket!.on('room_seats_state', (data) {
      try {
        final state = RoomSeatsState.fromJson(Map<String, dynamic>.from(data));
        _roomStateController.add(state);
      } catch (e) {
        AppLogger.error('Error parsing room seats state: $e');
      }
    });

    _socket!.on('seat_occupied', (data) {
      try {
        final update = SeatUpdate.fromJson(
          Map<String, dynamic>.from(data),
          SeatUpdateType.occupied,
        );
        _seatUpdateController.add(update);
      } catch (e) {
        AppLogger.error('Error parsing seat occupied: $e');
      }
    });

    _socket!.on('seat_released', (data) {
      try {
        final update = SeatUpdate.fromJson(
          Map<String, dynamic>.from(data),
          SeatUpdateType.vacated,
        );
        _seatUpdateController.add(update);
      } catch (e) {
        AppLogger.error('Error parsing seat released: $e');
      }
    });

    _socket!.on('seat_mute_changed', (data) {
      try {
        final update = SeatUpdate.fromJson(
          Map<String, dynamic>.from(data),
          SeatUpdateType.muteChanged,
        );
        _seatUpdateController.add(update);
      } catch (e) {
        AppLogger.error('Error parsing seat_mute_changed: $e');
      }
    });

    _socket!.on('mic_access_approved', (data) {
      AppLogger.info('Mic access approved');
    });

    _socket!.on('mic_access_denied', (data) {
      AppLogger.info('Mic access denied');
    });
  }

  // Room operations
  void joinRoom(int roomId, int userId, String username) {
    _socket?.emit('join_room', {
      'roomId': roomId,
      'userId': userId,
      'username': username,
    });
    AppLogger.info('Joining room $roomId as $username');
  }

  void leaveRoom(int roomId, int userId) {
    _socket?.emit('leave_room', {
      'roomId': roomId,
      'userId': userId,
    });
    AppLogger.info('Leaving room $roomId');
  }

  void initRoomSeats(int roomId) {
    _socket?.emit('init_room_seats', {'roomId': roomId});
    AppLogger.info('Initializing room seats for room $roomId');
  }

  void requestMicAccess(
      int roomId,
      int seatNumber,
      int userId,
      String username,
      String? avatarUrl,
      ) {
    _socket?.emit('take_seat', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'userId': userId,
      'username': username,
      'avatarUrl': avatarUrl,
    });
  }

  void leaveSeatRoom(int roomId, int userId, int seatNumber) {
    _socket?.emit('leave_seat', {
      'roomId': roomId,
      'userId': userId,
      'seatNumber': seatNumber,
    });
  }

  void toggleSelfMute(int roomId, int seatNumber, bool isMuted) {
    _socket?.emit('toggle_mute', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'isMuted': isMuted,
    });
  }

  void sendMessage(int roomId, int userId, String username, String message) {
    _socket?.emit('send_message', {
      'roomId': roomId,
      'userId': userId,
      'username': username,
      'message': message,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void sendTyping(int roomId, int userId, String username, bool isTyping) {
    _socket?.emit('typing', {
      'roomId': roomId,
      'userId': userId,
      'username': username,
      'isTyping': isTyping,
    });
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
  }

  void dispose() {
    _connectionController.close();
    _messageController.close();
    _userEventController.close();
    _seatUpdateController.close();
    _roomStateController.close();
    disconnect();
  }
}

// ===== Models =====

class SocketMessage {
  final int messageId;
  final int roomId;
  final int userId;
  final String username;
  final String message;
  final int timestamp;
  final String? avatar;

  SocketMessage({
    required this.messageId,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.message,
    required this.timestamp,
    this.avatar,
  });

  factory SocketMessage.fromJson(Map<String, dynamic> json) {
    int _i(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return SocketMessage(
      messageId: _i(json['id'] ?? json['messageId']),
      roomId: _i(json['roomId']),
      userId: _i(json['userId']),
      username: (json['username'] ?? '').toString(),
      message: (json['message'] ?? json['content'] ?? '').toString(),
      timestamp: _i(json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      avatar: json['avatar']?.toString() ?? json['avatarUrl']?.toString(),
    );
  }
}

enum UserEventType { joined, left, typing }

class SocketUserEvent {
  final int userId;
  final String username;
  final int roomId;
  final UserEventType type;
  final bool? isTyping;

  SocketUserEvent({
    required this.userId,
    required this.username,
    required this.roomId,
    required this.type,
    this.isTyping,
  });

  factory SocketUserEvent.fromJson(Map<String, dynamic> json, UserEventType type) {
    int _i(dynamic v) => int.tryParse('$v') ?? 0;

    return SocketUserEvent(
      userId: _i(json['userId']),
      username: (json['username'] ?? '').toString(),
      roomId: _i(json['roomId']),
      type: type,
      isTyping: json['isTyping'] as bool?,
    );
  }
}

enum SeatUpdateType { occupied, vacated, muteChanged }

class SeatUpdate {
  final int seatNumber;
  final int? userId;
  final String? username;
  final String? avatarUrl;
  final int? level;
  final bool? isMuted;
  final SeatUpdateType type;

  SeatUpdate({
    required this.seatNumber,
    this.userId,
    this.username,
    this.avatarUrl,
    this.level,
    this.isMuted,
    required this.type,
  });

  factory SeatUpdate.fromJson(Map<String, dynamic> json, SeatUpdateType type) {
    int? _ni(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    bool? _nb(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      return v.toString() == 'true';
    }

    return SeatUpdate(
      seatNumber: _ni(json['seatNumber'] ?? json['seat_number']) ?? 0,
      userId: _ni(json['userId'] ?? json['user_id']),
      username: (json['username'] ?? json['name'])?.toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'])?.toString(),
      level: _ni(json['level']),
      isMuted: _nb(json['isMuted'] ?? json['muted']),
      type: type,
    );
  }
}

class RoomSeatsState {
  final int roomId;
  final int ownerId;
  final List<SeatData> seats;

  RoomSeatsState({
    required this.roomId,
    required this.ownerId,
    required this.seats,
  });

  factory RoomSeatsState.fromJson(Map<String, dynamic> json) {
    int _i(dynamic v) => int.tryParse('$v') ?? 0;

    return RoomSeatsState(
      roomId: _i(json['roomId'] ?? json['room_id']),
      ownerId: _i(json['ownerId'] ?? json['owner_id']),
      seats: ((json['seats'] ?? const []) as List)
          .map((s) => SeatData.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
    );
  }
}

class SeatData {
  final int seatNumber;
  final int? userId;
  final String? username;
  final String? avatarUrl;
  final int level;
  final String? avatarFrameUrl;
  final bool isMuted;
  final bool isLocked;

  SeatData({
    required this.seatNumber,
    this.userId,
    this.username,
    this.avatarUrl,
    required this.level,
    this.avatarFrameUrl,
    required this.isMuted,
    required this.isLocked,
  });

  factory SeatData.fromJson(Map<String, dynamic> json) {
    int _i(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

    final rawMuted = json['isMuted'] ?? json['muted'];
    final rawLocked = json['isLocked'] ?? json['locked'];

    return SeatData(
      seatNumber: _i(json['seatNumber'] ?? json['seat_number'] ?? json['number']),
      userId: json['userId'] == null ? null : _i(json['userId'] ?? json['user_id']),
      username: (json['username'] ?? json['name'])?.toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'])?.toString(),
      avatarFrameUrl: (json['avatarFrameUrl'] ?? json['avatar_frame_url'])?.toString(),
      level: _i(json['level']),
      isMuted: rawMuted == true || rawMuted?.toString() == 'true',
      isLocked: rawLocked == true || rawLocked?.toString() == 'true',
    );
  }
}
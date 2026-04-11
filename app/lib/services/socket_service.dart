import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/gift_sent_event.dart';
export 'socket_service_impl.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import '../models/incoming_message.dart';
import '../models/message_events.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _token;

  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<SocketMessage>.broadcast();
  final _userEventController = StreamController<SocketUserEvent>.broadcast();
  final _seatUpdateController = StreamController<SeatUpdate>.broadcast();
  final _roomStateController = StreamController<RoomSeatsState>.broadcast();

  final _micQueueController = StreamController<MicQueueState>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();
  Stream<void> get reconnectStream => _reconnectController.stream;
  final _voiceUsersController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get voiceUsersStream => _voiceUsersController.stream;
  final _approveMicController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get approveMicStream => _approveMicController.stream;

  final _seatLockController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get seatLockStream => _seatLockController.stream;

  final _incomingMessageController = StreamController<IncomingMessage>.broadcast();
  Stream<IncomingMessage> get incomingMessageStream => _incomingMessageController.stream;

  final StreamController<GiftSentEvent> _giftController =
  StreamController<GiftSentEvent>.broadcast();

  Stream<GiftSentEvent> get giftStream => _giftController.stream;
  final StreamController<Map<String, dynamic>> _globalGiftBroadcastController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get globalGiftBroadcastStream =>
      _globalGiftBroadcastController.stream;

  final _typingController = StreamController<TypingEvent>.broadcast();
  Stream<TypingEvent> get typingStream => _typingController.stream;

  final _receiptController = StreamController<ReceiptEvent>.broadcast();
  Stream<ReceiptEvent> get receiptStream => _receiptController.stream;

  final _seatEffectController = StreamController<Map>.broadcast();
  Stream<Map> get seatEffectStream => _seatEffectController.stream;

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<SocketMessage> get messageStream => _messageController.stream;
  Stream<SocketUserEvent> get userEventStream => _userEventController.stream;
  Stream<SeatUpdate> get seatUpdateStream => _seatUpdateController.stream;
  Stream<RoomSeatsState> get roomStateStream => _roomStateController.stream;

  Stream<MicQueueState> get micQueueStream => _micQueueController.stream;

  final _reactionController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get reactionStream => _reactionController.stream;

  // ✅ REQUIRED by RoomLiveNotifier
  Stream<RoomSeatsState> get roomSeatsStateStream => roomStateStream;

  bool get isConnected => _socket?.connected ?? false;

  // ===============================
// Socket error stream (NEW)
// ===============================
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  void _emitError(String msg) {
    try { _errorController.add(msg); } catch (_) {}
  }

// inside SocketService class



  void offGiftSent() {
    _socket?.off('gift_sent');
  }

  void sendDmTyping({
    required int conversationId,
    required bool isTyping,
  }) {
    emit('dm_typing', {'conversationId': conversationId, 'isTyping': isTyping});
  }

  String _cleanJwt(String t) {
    var x = t.trim();

    // remove Bearer if someone passed it
    if (x.startsWith('Bearer ')) x = x.substring(7).trim();

    // remove accidental JSON quotes
    if (x.startsWith('"') && x.endsWith('"') && x.length > 2) {
      x = x.substring(1, x.length - 1);
    }

    return x;
  }


  // Seats
  void takeSeat({
    required int roomId,
    required int seatNumber,
    required int userId,
    required String username,
    String? avatarUrl,
    String? avatarFrameUrl, // ✅ ADD THIS
  }) {
    _log('emit take_seat roomId=$roomId seat=$seatNumber userId=$userId');

    // Send multiple keys to support backend differences
    emit('take_seat', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'userId': userId,
      'username': username,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (avatarFrameUrl != null) 'avatarFrameUrl': avatarFrameUrl, // ✅
      // optional aliases (backend may use these)
      'seat_number': seatNumber,
      'user_id': userId,
      'name': username,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
  }

  void connect(String token) {

    final jwt = _cleanJwt(token);
    if (jwt.isEmpty) return;

    // Verify it looks like a JWT before connecting
    final parts = jwt.split('.');
    if (parts.length != 3) {
      AppLogger.error('Token malformed: ${parts.length} parts');
      return;
    }

    _token = jwt;

    if (jwt.isEmpty) {
      AppLogger.error('Socket connect aborted: empty token');
      return;
    }

    _token = jwt;

    // dispose old socket
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
        .setAuth({'token': jwt}) // ✅ EXACTLY what server expects
        .build();

    _socket = IO.io(AppConfig.socketUrl, options);

    _socket!.onConnectError((e) {
      print("❌ CONNECT ERROR: $e");
    });

    _socket!.onError((e) {
      print("❌ SOCKET ERROR: $e");
    });
    _setupListeners();
    _socket!.connect();

    AppLogger.info('Socket connection initiated (auth token set)');
  }



  Future<void> waitUntilConnected({Duration timeout = const Duration(seconds: 5)}) async {
    if (isConnected) return;

    final completer = Completer<void>();
    StreamSubscription<bool>? sub;

    sub = connectionStream.listen((connected) {
      if (connected && !completer.isCompleted) {
        completer.complete();
        sub?.cancel();
      }
    });

    try {
      await completer.future.timeout(timeout);
    } catch (_) {
      // ok
    } finally {
      await sub?.cancel();
    }
  }


  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connectionController.add(false);
    AppLogger.info('Socket disconnected');
  }


  // ----------------------------
  // Generic emit/on/off (WebRTC needs this)
  // ----------------------------
  void emit(String event, dynamic data) {
    if (_socket == null || !_socket!.connected) {
      AppLogger.warning('Cannot emit "$event": socket not connected');
      return;
    }
    _socket!.emit(event, data);
  }


  void off(String event) => _socket?.off(event);

  // ✅ Optional helper (clean)
  void offGiftListeners() {
    _socket?.off('gift');
    _socket?.off('gift_sent');
    _socket?.off('new_gift');
    _socket?.off('room_gift');
  }

  void on(String event, Function(dynamic) callback) {
    if (_socket == null) return;
    _socket!.on(event, callback);
  }



  void leaveMySeat({required int roomId, required int seatNumber}) {
    emit('leave_seat', {'roomId': roomId, 'seatNumber': seatNumber});
  }



  void removeUserFromSeat({
    required int roomId,
    required int seatNumber,
    required int targetUserId,
  }) {
    _log('emit remove_from_seat roomId=$roomId seat=$seatNumber target=$targetUserId');
    emit('remove_from_seat', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'targetUserId': targetUserId,
    });
  }



  void _log(String m) => print('📡 SOCKET | $m');

  void setSeatMute({
    required int roomId,
    required int seatNumber,
    required int targetUserId,
    required bool mute,
  }) {
    _log('emit set_seat_mute roomId=$roomId seat=$seatNumber target=$targetUserId mute=$mute');
    emit('set_seat_mute', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'targetUserId': targetUserId,
      'mute': mute,
    });
  }



  void adminRemoveFromSeat({
    required int roomId,
    required int seatNumber,
    required int targetUserId,
  }) {
    // try multiple event names (backend will ignore unknown)
    emit('kick_from_seat', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'targetUserId': targetUserId,
      'userId': targetUserId,
    });

    emit('remove_from_seat', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'targetUserId': targetUserId,
      'userId': targetUserId,
    });

    emit('admin_remove_from_seat', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'targetUserId': targetUserId,
      'userId': targetUserId,
    });
  }

  // ✅ Admin: change seat count
  void setSeatCount({required int roomId, required int seatCount}) {
    emit('set_seat_count', {'roomId': roomId, 'seatCount': seatCount});
  }

  // ----------------------------
  // Voice helpers
  // ----------------------------
  void joinVoice({required int roomId, required int userId}) {
    emit('user_joined_voice', {'roomId': roomId, 'userId': userId});
    AppLogger.info('📣 user_joined_voice room=$roomId user=$userId');
  }

  void sendSeatEffect(Map<String, dynamic> data) {
    _socket?.emit('seat_effect', data);
  }

  void leaveVoice({required int roomId, required int userId}) {
    emit('user_left_voice', {'roomId': roomId, 'userId': userId});
    AppLogger.info('📣 user_left_voice room=$roomId user=$userId');
  }

  void getVoiceUsers({required int roomId}) {
    emit('get_voice_users', {'roomId': roomId});
    AppLogger.info('📣 get_voice_users room=$roomId');
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt(); // ✅ handles 1.0
    return int.tryParse(v.toString());
  }

  int _toInt0(dynamic v) => _toInt(v) ?? 0;

  void _applyTokenToSocket(String token) {
    final s = _socket;
    if (s == null) return;

    // auth (handshake)
    s.auth = {'token': token};

    // headers (handshake)
    final io = s.io;

    // io.options can be dynamic/nullable depending on socket_io_client version
    final dynamic rawOpts = io.options;

    final Map<String, dynamic> opts =
    (rawOpts is Map) ? Map<String, dynamic>.from(rawOpts) : <String, dynamic>{};

    final dynamic rawExtra = opts['extraHeaders'];
    final Map<String, dynamic> extra =
    (rawExtra is Map) ? Map<String, dynamic>.from(rawExtra) : <String, dynamic>{};

    extra['Authorization'] = 'Bearer $token';
    opts['extraHeaders'] = extra;

    // ✅ write back
    io.options = opts;
  }

  void updateToken(String token) {
    final jwt = _cleanJwt(token);
    if (jwt.isEmpty) return;

    _token = jwt;
    disconnect();
    connect(jwt);
  }


  // ----------------------------
  // Listeners
  // ----------------------------
  void _setupListeners() {
    if (_socket == null) return;

    void _handleMuteChanged(dynamic data) {
      try {
        final map = Map<String, dynamic>.from(data);
        final seatNumber = _toInt(map['seatNumber']) ?? _toInt(map['seat_number']) ?? 0;
        final isMuted = map['isMuted'] ?? map['muted'];

        if (seatNumber == null || seatNumber <= 0) return;

        _seatUpdateController.add(SeatUpdate(
          seatNumber: seatNumber,
          isMuted: isMuted is bool ? isMuted : (isMuted.toString() == 'true'),
          type: SeatUpdateType.muteChanged,
        ));
        AppLogger.info('🎚️ muteChanged seat=$seatNumber muted=$isMuted');
      } catch (e) {
        AppLogger.error('Error parsing muteChanged: $e');
      }
    }

    void handleApprove(dynamic data) {
      try {
        final map = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        _approveMicController.add(map);
        AppLogger.info('🎧 approveMic parsed=$map');
      } catch (e) {
        AppLogger.error('approveMic parse error: $e');
      }
    }
    print('SOCKET TOKEN = "$_token"');

    // ✅ DM typing
    _socket?.on('dm_typing', (data) {
      try {
        if (data is Map) {
          final ev = TypingEvent.fromJson(Map<String, dynamic>.from(data));
          _typingController.add(ev);
        }
      } catch (_) {}
    });

    _socket?.on('seat_effect', (data) {
      print('🎬 seat_effect received: $data');
      _seatEffectController.add(Map<String, dynamic>.from(data));
    });

// ✅ DM receipts (delivered/read)
    _socket?.on('dm_receipt', (data) {
      try {
        if (data is Map) {
          final ev = ReceiptEvent.fromJson(Map<String, dynamic>.from(data));
          _receiptController.add(ev);
        }
      } catch (_) {}
    });

    _socket!.on('user_joined', (data) {
      try {
        print('🔥 user_joined RAW: $data');

        final map = Map<String, dynamic>.from(data);

        final event = SocketUserEvent(
          userId: map['userId'],
          username: map['username'] ?? 'User',
          roomId: map['roomId'] ?? 0, // ✅ FIX
          type: UserEventType.joined,
        );

        _userEventController.add(event);
      } catch (e) {
        print('user_joined parse error: $e');
      }
    });

    _socket!.on('user_left', (data) {
      try {
        print('🔥 user_left RAW: $data');

        final map = Map<String, dynamic>.from(data);

        final event = SocketUserEvent(
          userId: map['userId'],
          username: map['username'] ?? 'User',
          roomId: map['roomId'] ?? 0, // ✅ FIX
          type: UserEventType.left,
        );

        _userEventController.add(event);
      } catch (e) {
        print('user_left parse error: $e');
      }
    });

    _socket!.onConnect((_) {
      AppLogger.info('✅ Socket connected!');
      _connectionController.add(true);
    });


    _socket!.onAny((event, data) {
      AppLogger.info('🧪 onAny event=$event data=$data');
    });

    _socket!.onDisconnect((_) {
      AppLogger.info('❌ Socket disconnected');
      _connectionController.add(false);
    });

    _socket!.onReconnect((_) {
      AppLogger.info('🔁 Socket reconnected');

      final t = _token;
      if (t != null && t.isNotEmpty) {
        _applyTokenToSocket(t);
      }
      _reconnectController.add(null);
    });

    // ✅ DM message (backend emits this)
    _socket?.on('dm_new_message', (data) {
      try {
        if (data is Map) {
          final msg = IncomingMessage.fromJson(Map<String, dynamic>.from(data));
          _incomingMessageController.add(msg);
        }
      } catch (_) {}
    });

// ✅ optional: conversation list patch event
    _socket?.on('dm_conversation_updated', (data) {
      // We'll handle this in provider using a new stream/controller below,
      // OR you can just fallback to incomingMessage (dm_new_message) to patch list.
      // If you want, I can add a dedicated stream for this too.
    });

    _socket?.on('message:new', (data) {
      try {
        if (data is Map) {
          final msg = IncomingMessage.fromJson(Map<String, dynamic>.from(data));
          _incomingMessageController.add(msg);
        }
      } catch (_) {}
    });

    _socket?.on('seat_lock', (data) {
      _seatLockController.add(data);
    });



    _socket!.on('seat_mute_changed', _handleMuteChanged);
    _socket!.on('mute_changed', _handleMuteChanged);
    _socket!.on('seat_muted', _handleMuteChanged);
    _socket!.on('toggle_mute_result', _handleMuteChanged);
    _socket!.on('toggle_mute', _handleMuteChanged);
    _socket!.on('mic_muted', _handleMuteChanged);
    _socket!.on('mic_unmuted', _handleMuteChanged);
    _socket!.on('approve_mic', handleApprove);    // ✅ snake (matches your emit)


    _socket!.on('gift_error', (data) {
      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : (data?.toString() ?? 'Gift failed');
      _emitError(msg);
    });

// keep generic too
    _socket!.on('error', (data) {
      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : (data?.toString() ?? 'Socket error');
      _emitError(msg);
    });



    // ✅ WebRTC/Voice events: keep them available for WebRTCAudioService via .on(...)
    // (No parsing here; WebRTCAudioService reads them directly.)
    _socket!.on('voice_users', (data) {
      try {
        final map = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};

        final roomId = _toInt0(map['roomId'] ?? map['room_id']);
        final rawUsers = map['users'];

        final users = (rawUsers is List)
            ? rawUsers.map((e) {
          if (e is int) return e;
          if (e is num) return e.toInt();
          return int.tryParse('$e') ?? -1;
        }).where((id) => id > 0).toList()
            : <int>[];

        _voiceUsersController.add({
          'roomId': roomId,
          'users': users,
        });

        AppLogger.info('🎧 voice_users parsed roomId=$roomId users=$users raw=$data');
      } catch (e) {
        AppLogger.error('Error parsing voice_users: $e');
      }
    });


    _socket!.on('user_joined_voice', (data) {
      AppLogger.info('🎧 user_joined_voice raw=$data');
    });
    _socket!.on('user_left_voice', (data) {
      AppLogger.info('🎧 user_left_voice raw=$data');
    });
    _socket!.on('webrtc_offer', (data) {
      AppLogger.info('🎧 webrtc_offer raw=$data');
    });
    _socket!.on('webrtc_answer', (data) {
      AppLogger.info('🎧 webrtc_answer raw=$data');
    });
    _socket!.on('webrtc_ice_candidate', (data) {
      AppLogger.info('🎧 webrtc_ice_candidate raw=$data');
    });
    _socket!.on('approveMic', (data) {
      try {
        final map = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        _approveMicController.add(map);
        AppLogger.info('🎧 approveMic parsed=$map');
      } catch (e) {
        AppLogger.error('approveMic parse error: $e');
      }
    });




    // =======================
// Gifts (FIXED)
// Backend emits: event "gift" with wrapper: { roomId, type:'sent', giftEvent:{...} }
// Some backends might emit directly as "gift_sent" => {...}
// We support both.
// =======================

    GiftSentEvent? _parseGift(dynamic data) {
      try {
        if (data is! Map) return null;
        final map = Map<String, dynamic>.from(data);

        // 1) wrapper format: { giftEvent: {...} }
        final raw = map['giftEvent'];
        if (raw is Map) {
          return GiftSentEvent.fromJson(Map<String, dynamic>.from(raw));
        }

        // 2) direct format: { giftId, giftName, ... }
        return GiftSentEvent.fromJson(map);
      } catch (e) {
        AppLogger.error('Gift parse error: $e');
        return null;
      }
    }

    // ✅ Gifts: listen to server "gift" event and forward to giftStream
    _socket!.on('gift', (data) {
      final ev = _parseGift(data);
      if (ev != null) {
        _giftController.add(ev);
      }
    });

    _socket?.on('dm_reaction_updated', (data) {
      // { conversationId, messageId, reactions: { "❤️": 2, "😂": 1 }, myReaction: "❤️" }
      try {
        if (data is Map) {
          _reactionController.add(Map<String, dynamic>.from(data));
        }
      } catch (_) {}
    });

// Optional: support "gift_sent" if some backend emits it
    _socket!.on('gift_sent', (data) {
      final ev = _parseGift(data);
      if (ev != null) {
        _giftController.add(ev);
      }
    });

    _socket!.on('global_gift_broadcast', (data) {
      try {
        if (data is Map) {
          _globalGiftBroadcastController.add(Map<String, dynamic>.from(data));
        }
      } catch (e) {
        AppLogger.error('Global gift broadcast parse error: $e');
      }
    });

    // Chat
    _socket!.on('new_message', (data) {
      try {
        final message = SocketMessage.fromJson(Map<String, dynamic>.from(data));
        _messageController.add(message);
      } catch (e) {
        AppLogger.error('Error parsing new_message: $e');
      }
    });

    // Typing
    _socket!.on('typing', (data) {
      try {
        final event = SocketUserEvent.fromJson(
          Map<String, dynamic>.from(data),
          UserEventType.typing,
        );
        _userEventController.add(event);
      } catch (e) {
        AppLogger.error('Error parsing typing: $e');
      }
    });

    // Seats snapshot
    _socket!.on('room_seats_state', (data) {
      try {
        final state = RoomSeatsState.fromJson(Map<String, dynamic>.from(data));
        _roomStateController.add(state);
      } catch (e) {
        AppLogger.error('Error parsing room_seats_state: $e');
      }
    });

    // Seat updates
    _socket!.on('seat_occupied', (data) {
      try {
        final update = SeatUpdate.fromJson(
          Map<String, dynamic>.from(data),
          SeatUpdateType.occupied,
        );
        _seatUpdateController.add(update);
      } catch (e) {
        AppLogger.error('Error parsing seat_occupied: $e');
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
        AppLogger.error('Error parsing seat_released: $e');
      }
    });

    // Mic queue
    _socket!.on('mic_queue_updated', (data) {
      try {
        final map = Map<String, dynamic>.from(data);
        final roomId = _toInt0(map['roomId'] ?? map['room_id']);

        final raw = (map['queue'] as List?) ?? const [];
        final q = raw
            .map((e) => _toInt(e) ?? 0)
            .where((x) => x != 0)
            .toList();


        _micQueueController.add(MicQueueState(roomId: roomId, queueUserIds: q));
      } catch (e) {
        AppLogger.error('Error parsing mic_queue_updated: $e');
      }
    });




  }

  // ----------------------------
  // Room ops
  // ----------------------------
  void joinRoom({
    required int roomId,
    required int userId,
    required String username,
  }) {
    emit('join_room', {'roomId': roomId, 'userId': userId, 'username': username});
    emit('room:join', roomId);

    // ✅ REQUEST SNAPSHOT (try multiple names; server will ignore unknown)
    emit('init_room_seats', {'roomId': roomId});
    emit('get_room_seats_state', {'roomId': roomId});
    emit('request_room_seats_state', {'roomId': roomId});
    emit('get_room_state', {'roomId': roomId});
    emit('room_seats_state:get', {'roomId': roomId});
    AppLogger.info('🚪 Joined room $roomId as $username');

  }


  void leaveRoom({
    required int roomId,
    required int userId,
  }) {
    emit('leave_room', {'roomId': roomId, 'userId': userId});
    emit('room:leave', roomId);
    AppLogger.info('🚪 Left room $roomId');
  }

  // Chat helpers
  void sendMessage({
    required int roomId,
    required int userId,
    required String username,
    required String message,
  }) {
    emit('send_message', {
      'roomId': roomId,
      'userId': userId,
      'username': username,
      'message': message,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void sendRoomMessage({
    required int roomId,
    required int userId,
    required String username,
    required String message,
  }) {
    sendMessage(roomId: roomId, userId: userId, username: username, message: message);
  }

  void sendTyping({
    required int roomId,
    required int userId,
    required String username,
    required bool isTyping,
  }) {
    emit('typing', {'roomId': roomId, 'userId': userId, 'username': username, 'isTyping': isTyping});
  }

  // Mic queue
  void requestMic({required int roomId}) => emit('request_mic', {'roomId': roomId});
  void cancelMicRequest({required int roomId}) => emit('cancel_mic_request', {'roomId': roomId});
  void approveMic({required int roomId, required int userId}) => emit('approve_mic', {'roomId': roomId, 'targetUserId': userId});
  void rejectMic({required int roomId, required int userId}) => emit('reject_mic', {'roomId': roomId, 'targetUserId': userId});

  // Seats
  void leaveSeat({required int roomId, required int seatNumber}) => emit('leave_seat', {'roomId': roomId, 'seatNumber': seatNumber});
  DateTime? _lastToggleMuteAt;

  void toggleMute({
    required int roomId,
    required int seatNumber,
    required bool isMuted,
    int? userId,
  }) {
    final now = DateTime.now();
    if (_lastToggleMuteAt != null &&
        now.difference(_lastToggleMuteAt!).inMilliseconds < 400) {
      AppLogger.warning('toggleMute ignored (spam protection)');
      return;
    }
    _lastToggleMuteAt = now;

    emit('toggle_mute', {
      'roomId': roomId,
      'seatNumber': seatNumber,
      'isMuted': isMuted,

      // ✅ send both names (server will pick what it uses)
      if (userId != null) 'userId': userId,
      if (userId != null) 'targetUserId': userId,
    });

  }

  // Gifts
  void sendGift({
    required int roomId,
    required int receiverId,
    required int giftId,
    int quantity = 1,
    String? message,
  }) {
    emit('send_gift', {
      'roomId': roomId,
      'receiverId': receiverId,
      'giftId': giftId,
      'quantity': quantity,
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }


  void dispose() {
    _connectionController.close();
    _reconnectController.close();
    _messageController.close();
    _userEventController.close();
    _seatUpdateController.close();
    _roomStateController.close();
    _giftController.close();
    _globalGiftBroadcastController.close();
    _micQueueController.close();
    _voiceUsersController.close(); // ✅ ADD
    _approveMicController.close();
    _errorController.close();
    _typingController.close();
    _receiptController.close();
    _reactionController.close();

    disconnect();
  }
}

// ===========================
// Models (same as yours)
// ===========================

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
      username: (json['username'] ?? '') as String,
      message: (json['message'] ?? json['content'] ?? '') as String,
      timestamp: _i(json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      avatar: json['avatar'] as String? ?? json['avatarUrl'] as String?,
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
      username: (json['username'] ?? '') as String,
      roomId: _i(json['roomId']),
      type: type,
      isTyping: json['isTyping'] as bool?,
    );
  }
}

enum SeatUpdateType { occupied, vacated, muteChanged }

class SeatUpdate {
  final int? seatNumber;
  final int? userId;
  final String? username;
  final String? avatarUrl;
  final int? level;
  final bool? isMuted;
  final SeatUpdateType type;

  SeatUpdate({
    this.seatNumber,
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
      seatNumber: _ni(
          json['seatNumber'] ?? json['seat_number'] ?? json['number']),
      userId: _ni(json['userId'] ?? json['user_id']),
      username: (json['username'] ?? json['name']) as String?,
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url']) as String?,
      level: _ni(json['level']),
      isMuted: _nb(json['isMuted'] ?? json['muted']),
      type: type,
    );
  }
}

class RoomSeatsState {
  final int roomId;
  final int ownerId;
  final List<int> adminIds;
  final List<int> lockedSeats; // ✅ NEW

  /// ✅ NEW: how many seats this room has
  final int seatCount;

  /// backend may send only occupied seats
  final List<SeatData> seats;

  RoomSeatsState({
    required this.roomId,
    required this.ownerId,
    required this.adminIds,
    required this.seatCount,
    required this.seats,
    required this.lockedSeats, // ✅ ADD THIS

  });

  factory RoomSeatsState.fromJson(Map<String, dynamic> json) {
    int _i(dynamic v) => int.tryParse('$v') ?? 0;

    final rid = _i(json['roomId'] ?? json['room_id']);
    final owner = _i(json['ownerId'] ?? json['owner_id']);

    final rawLocked = (json['lockedSeats'] ?? json['locked_seats'] ?? const []) as List;
    final lockedSeats = rawLocked
        .map((e) => int.tryParse('$e'))
        .whereType<int>()
        .where((x) => x > 0)
        .toList();

    // ✅ NEW: read seatCount from backend keys (support many names)
    final seatCount = _i(
      json['seatCount'] ??
          json['seatsCount'] ??
          json['seats_count'] ??
          json['maxSeats'] ??
          (json['room'] is Map ? (json['room']['maxSeats']) : null) ??
          json['max_seats'] ??
          json['capacity'],
    );

    final rawAdmins = (json['adminIds'] ??
        json['admins'] ??
        json['admin_ids'] ??
        const [])
    as List;
    final adminIds = rawAdmins
        .map((e) {
      if (e is Map) return _i(e['id'] ?? e['userId']);
      return _i(e);
    })
        .where((id) => id != 0)
        .toList();

    final rawSeats = (json['seats'] ?? const []) as List;
    final seats = rawSeats
        .map((s) => SeatData.fromJson(Map<String, dynamic>.from(s)))
        .toList();

    // fallback if backend didn't send seatCount (very important)
    final fallbackCount = seats.isEmpty
        ? 1
        : seats.map((s) => s.seatNumber).reduce((a, b) => a > b ? a : b);

    return RoomSeatsState(
      roomId: rid,
      ownerId: owner,
      adminIds: adminIds,
      seatCount: seatCount > 0 ? seatCount : fallbackCount,
      seats: seats,
      lockedSeats: lockedSeats, // ✅ ADD THIS

    );
  }
}


class SeatData {
  final int seatNumber;
  final int? userId;
  final int? displayId;
  final String? username;
  final String? avatarUrl;
  final String? avatarFrameUrl; // ✅ NEW
  final RelationPartner? relationPartner;
  final int level;
  final bool isMuted;
  final bool isLocked;
  bool isSpeaking;

  SeatData({
    required this.seatNumber,
    required this.userId,
    this.displayId,
    required this.username,
    required this.avatarUrl,
    this.avatarFrameUrl, // ✅ NEW
    this.relationPartner,
    required this.level,
    required this.isMuted,
    required this.isLocked,
    this.isSpeaking = false,
  });

  factory SeatData.empty(int seatNumber) => SeatData(
    seatNumber: seatNumber,
    userId: null,
    displayId: null,
    username: null,
    avatarUrl: null,
    avatarFrameUrl: null, // ✅ NEW
    relationPartner: null,
    level: 0,
    isMuted: true,
    isLocked: false,
    isSpeaking: false,
  );

  SeatData copyWith({
    int? userId,
    int? displayId,
    String? username,
    String? avatarUrl,
    String? avatarFrameUrl,
    RelationPartner? relationPartner,
    int? level,
    bool? isMuted,
    bool? isLocked,
    bool? isSpeaking,
  }) {
    return SeatData(
      seatNumber: seatNumber,
      userId: userId ?? this.userId,
      displayId: displayId ?? this.displayId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarFrameUrl: avatarFrameUrl ?? this.avatarFrameUrl,
      relationPartner: relationPartner ?? this.relationPartner,
      level: level ?? this.level,
      isMuted: isMuted ?? this.isMuted,
      isLocked: isLocked ?? this.isLocked,
      isSpeaking: isSpeaking ?? this.isSpeaking,
    );
  }
  factory SeatData.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

    final seatNum = toInt(json['seatNumber'] ?? json['seat_number'] ?? json['number']);
    final rawUserId = (json['userId'] ?? json['user_id']);

    final rawMuted = json['isMuted'] ?? json['muted'];
    final rawLocked = json['isLocked'] ?? json['locked'];

    return SeatData(
      seatNumber: seatNum,
      userId: rawUserId == null ? null : toInt(rawUserId),
      displayId: (json['displayId'] ?? json['display_id'] ?? json['userDisplayId']) == null
          ? null
          : toInt(json['displayId'] ?? json['display_id'] ?? json['userDisplayId']),
      username: (json['username'] ?? json['name'])?.toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'])?.toString(),
      avatarFrameUrl: (json['frameImageUrl'] ?? json['avatarFrameUrl'] ?? json['avatar_frame_url'])?.toString(),
      relationPartner: json['relationPartner'] is Map<String, dynamic>
          ? RelationPartner.fromJson(json['relationPartner'] as Map<String, dynamic>)
          : null,
      level: toInt(json['level']),
      isMuted: rawMuted == true || rawMuted?.toString() == 'true',
      isLocked: rawLocked == true || rawLocked?.toString() == 'true',

    );
  }
}

class RelationPartner {
  final int id;
  final String name;
  final String? avatarUrl;

  const RelationPartner({
    required this.id,
    required this.name,
    required this.avatarUrl,
  });

  factory RelationPartner.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

    return RelationPartner(
      id: toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      avatarUrl: json['avatarUrl']?.toString(),
    );
  }
}



class MicQueueState {
  final int roomId;
  final List<int> queueUserIds;
  MicQueueState({required this.roomId, required this.queueUserIds});
}

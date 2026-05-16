import 'dart:async';

import 'package:samafox/services/socket_service.dart';

import '../models/gift_v2.dart';

/// Thin wrapper around the existing SocketService that exposes
/// strongly-typed streams for V2 gift events.
class GiftV2SocketService {
  GiftV2SocketService(this._socket);

  final SocketService _socket;
  final StreamController<GiftV2SendEvent> _sent = StreamController.broadcast();
  final StreamController<GiftV2SendEvent> _legendaryIncoming = StreamController.broadcast();
  final StreamController<GiftV2SendEvent> _broadcast = StreamController.broadcast();
  bool _bound = false;

  Stream<GiftV2SendEvent> get sentStream => _sent.stream;
  Stream<GiftV2SendEvent> get legendaryIncomingStream => _legendaryIncoming.stream;
  Stream<GiftV2SendEvent> get broadcastStream => _broadcast.stream;

  void bind() {
    if (_bound) return;
    _bound = true;
    _socket.on('gift_v2_sent', (data) => _dispatch(data, _sent));
    _socket.on('gift_v2_legendary_incoming', (data) => _dispatch(data, _legendaryIncoming));
    _socket.on('gift_v2_broadcast', (data) => _dispatch(data, _broadcast));
  }

  void unbind() {
    _socket.off('gift_v2_sent');
    _socket.off('gift_v2_legendary_incoming');
    _socket.off('gift_v2_broadcast');
    _bound = false;
  }

  void _dispatch(dynamic data, StreamController<GiftV2SendEvent> controller) {
    if (data is! Map) return;
    try {
      final event = GiftV2SendEvent.fromJson(Map<String, dynamic>.from(data));
      controller.add(event);
    } catch (_) {
      // ignore malformed payloads
    }
  }

  Future<void> dispose() async {
    unbind();
    await _sent.close();
    await _legendaryIncoming.close();
    await _broadcast.close();
  }
}

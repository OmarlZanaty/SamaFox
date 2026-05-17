import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:samafox/services/socket_service.dart';

import '../models/gift.dart';

/// Thin wrapper around the existing SocketService that exposes
/// strongly-typed streams for gift events.
class GiftSocketService {
  GiftSocketService(this._socket);

  final SocketService _socket;
  final StreamController<GiftSendEvent> _sent = StreamController.broadcast();
  final StreamController<GiftSendEvent> _legendaryIncoming = StreamController.broadcast();
  final StreamController<GiftSendEvent> _broadcast = StreamController.broadcast();
  bool _bound = false;

  Stream<GiftSendEvent> get sentStream => _sent.stream;
  Stream<GiftSendEvent> get legendaryIncomingStream => _legendaryIncoming.stream;
  Stream<GiftSendEvent> get broadcastStream => _broadcast.stream;

  void bind() {
    if (_bound) return;
    _bound = true;
    _socket.on('gift_sent', (data) => _dispatch(data, _sent));
    _socket.on('gift_legendary_incoming', (data) => _dispatch(data, _legendaryIncoming));
    _socket.on('gift_broadcast', (data) => _dispatch(data, _broadcast));
  }

  void unbind() {
    _socket.off('gift_sent');
    _socket.off('gift_legendary_incoming');
    _socket.off('gift_broadcast');
    _bound = false;
  }

  void _dispatch(dynamic data, StreamController<GiftSendEvent> controller) {
    if (data is! Map) return;
    try {
      final event = GiftSendEvent.fromJson(Map<String, dynamic>.from(data));
      controller.add(event);
    } catch (e, st) {
      debugPrint('[GiftSocketService] parse failed: $e\n$st\nraw=$data');
    }
  }

  Future<void> dispose() async {
    unbind();
    await _sent.close();
    await _legendaryIncoming.close();
    await _broadcast.close();
  }
}

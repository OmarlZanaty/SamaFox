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
  // A22 — شريط إعلان الهدية. A separate, deliberately light event: it
  // carries only who/what/to-whom, and one event covers a whole fan-out so a
  // gift to 20 people shows ONE bar instead of 20 stacked ones.
  final StreamController<GiftAnnouncement> _announcements = StreamController.broadcast();
  bool _bound = false;

  Stream<GiftSendEvent> get sentStream => _sent.stream;
  Stream<GiftSendEvent> get legendaryIncomingStream => _legendaryIncoming.stream;
  Stream<GiftSendEvent> get broadcastStream => _broadcast.stream;
  Stream<GiftAnnouncement> get announcementStream => _announcements.stream;

  void bind() {
    if (_bound) return;
    _bound = true;
    _socket.on('gift_sent', (data) => _dispatch(data, _sent));
    _socket.on('gift_legendary_incoming', (data) => _dispatch(data, _legendaryIncoming));
    _socket.on('gift_broadcast', (data) => _dispatch(data, _broadcast));
    _socket.on('gift_announcement', _dispatchAnnouncement);
  }

  void unbind() {
    _socket.off('gift_sent');
    _socket.off('gift_legendary_incoming');
    _socket.off('gift_broadcast');
    _socket.off('gift_announcement');
    _bound = false;
  }

  void _dispatchAnnouncement(dynamic data) {
    if (data is! Map) return;
    try {
      _announcements.add(GiftAnnouncement.fromJson(Map<String, dynamic>.from(data)));
    } catch (e) {
      debugPrint('[GiftSocketService] announcement parse failed: $e raw=$data');
    }
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
    await _announcements.close();
  }
}

/// A22 — "فلان أهدى هدية كذا إلى فلان" (or "إلى الجميع").
@immutable
class GiftAnnouncement {
  final int senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String giftName;
  final String giftIconUrl;
  final int quantity;

  /// How many people received this gift. > 1 renders "إلى الجميع".
  final int recipientCount;

  /// Named only for a single recipient; null for a fan-out.
  final String? recipientName;
  final int? roomId;

  const GiftAnnouncement({
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl,
    required this.giftName,
    required this.giftIconUrl,
    this.quantity = 1,
    this.recipientCount = 1,
    this.recipientName,
    this.roomId,
  });

  factory GiftAnnouncement.fromJson(Map<String, dynamic> json) {
    final gift = (json['gift'] as Map?) ?? const {};
    return GiftAnnouncement(
      senderId: (json['senderId'] as num?)?.toInt() ?? 0,
      senderName: json['senderName']?.toString() ?? 'مستخدم',
      senderAvatarUrl: json['senderAvatarUrl']?.toString(),
      giftName: (gift['nameAr'] ?? gift['name'])?.toString() ?? 'هدية',
      giftIconUrl: gift['iconUrl']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      recipientCount: (json['recipientCount'] as num?)?.toInt() ?? 1,
      recipientName: json['recipientName']?.toString(),
      roomId: (json['roomId'] as num?)?.toInt(),
    );
  }

  /// The line the bar shows, already in the client's requested wording.
  String get text => recipientCount > 1
      ? '$senderName أهدى $giftName إلى الجميع'
      : '$senderName أهدى $giftName إلى ${recipientName ?? 'مستخدم'}';
}

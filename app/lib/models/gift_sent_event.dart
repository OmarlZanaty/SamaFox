// lib/models/gift_sent_event.dart

class GiftSentEvent {
  final int? id;
  final int? roomId;

  final int? giftId;
  final String? giftName;
  final String? giftImageUrl;

  final int? fromUserId;
  final String? fromUserName;
  final String? fromUserAvatar;

  final int? toUserId;
  final String? toUserName;
  final String? toUserAvatar;

  final int? coinsSpent;
  final int? quantity;
  final String? message;
  final int? senderNewBalance;    // ✅ NEW
  final int? receiverNewBalance;  // ✅ NEW

  final DateTime? createdAt;

  GiftSentEvent({
    this.id,
    this.roomId,
    this.giftId,
    this.giftName,
    this.giftImageUrl,
    this.fromUserId,
    this.fromUserName,
    this.fromUserAvatar,
    this.toUserId,
    this.toUserName,
    this.toUserAvatar,
    this.coinsSpent,
    this.quantity,
    this.message,
    this.createdAt,
    this.senderNewBalance,
    this.receiverNewBalance,

  });

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  factory GiftSentEvent.fromJson(Map<String, dynamic> json) {
    // Backend emits:
    // giftEvent: {
    //   id, giftId, coinsSpent, quantity, message,
    //   gift: { id, name, imageUrl, ... }
    //   sender: { id, name, avatarUrl }
    //   receiver: { id, name, avatarUrl }
    //   createdAt
    // }

    final gift = (json['gift'] is Map) ? Map<String, dynamic>.from(json['gift']) : null;
    final sender = (json['sender'] is Map) ? Map<String, dynamic>.from(json['sender']) : null;
    final receiver = (json['receiver'] is Map) ? Map<String, dynamic>.from(json['receiver']) : null;

    final createdRaw = json['createdAt'];
    DateTime? createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw);
    } else if (createdRaw is int || createdRaw is num) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(_toInt(createdRaw) ?? 0);
    }

    return GiftSentEvent(
      id: _toInt(json['id']),
      roomId: _toInt(json['roomId']),

      giftId: _toInt(json['giftId'] ?? gift?['id']),
      giftName: (json['giftName'] ?? gift?['name'])?.toString(),
      giftImageUrl: (json['giftImageUrl'] ?? gift?['imageUrl'])?.toString(),

      fromUserId: _toInt(json['fromUserId'] ?? json['senderId'] ?? sender?['id']),
      fromUserName: (json['fromUserName'] ?? json['senderName'] ?? sender?['name'])?.toString(),
      fromUserAvatar: (json['fromUserAvatar'] ?? json['senderAvatar'] ?? sender?['avatarUrl'])?.toString(),

      senderNewBalance: json['senderNewBalance'] != null
          ? int.tryParse(json['senderNewBalance'].toString()) ?? _toInt(json['senderNewBalance'])
          : null,
      receiverNewBalance: json['receiverNewBalance'] != null
          ? int.tryParse(json['receiverNewBalance'].toString()) ?? _toInt(json['receiverNewBalance'])
          : null,

      toUserId: _toInt(json['toUserId'] ?? json['receiverId'] ?? receiver?['id']),
      toUserName: (json['toUserName'] ?? json['receiverName'] ?? receiver?['name'])?.toString(),
      toUserAvatar: (json['toUserAvatar'] ?? json['receiverAvatar'] ?? receiver?['avatarUrl'])?.toString(),

      coinsSpent: _toInt(json['coinsSpent']),
      quantity: _toInt(json['quantity']) ?? 1,
      message: json['message']?.toString(),

      createdAt: createdAt,
    );
  }
}

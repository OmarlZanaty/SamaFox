class GiftEvent {
  final int giftId;
  final String giftName;
  final String giftImageUrl;
  final int giftPrice;

  final int senderId;
  final String senderName;
  final String? senderAvatar;

  final int receiverId;
  final String receiverName;
  final String? receiverAvatar;

  final int roomId;
  final int timestamp;

  GiftEvent({
    required this.giftId,
    required this.giftName,
    required this.giftImageUrl,
    required this.giftPrice,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    required this.roomId,
    required this.timestamp,
  });

  factory GiftEvent.fromJson(Map<String, dynamic> json) => GiftEvent(
    giftId: json['giftId'] ?? 0,
    giftName: json['giftName'] ?? '',
    giftImageUrl: json['giftImageUrl'] ?? '',
    giftPrice: json['giftPrice'] ?? 0,
    senderId: json['senderId'] ?? 0,
    senderName: json['senderName'] ?? '',
    senderAvatar: json['senderAvatar'],
    receiverId: json['receiverId'] ?? 0,
    receiverName: json['receiverName'] ?? '',
    receiverAvatar: json['receiverAvatar'],
    roomId: json['roomId'] ?? 0,
    timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
  );
}

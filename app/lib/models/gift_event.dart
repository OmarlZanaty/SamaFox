class GiftEvent {
  final int giftId;
  final String giftNameAr;
  final String giftImageUrl;
  final String? giftAnimationUrl;
  final int coinsValue;
  final int senderId;
  final int receiverId;
  final String senderName;
  final String receiverName;
  final String? senderAvatarUrl;
  final String? receiverAvatarUrl;

  GiftEvent({
    required this.giftId,
    required this.giftNameAr,
    required this.giftImageUrl,
    this.giftAnimationUrl,
    required this.coinsValue,
    required this.senderId,
    required this.receiverId,
    required this.senderName,
    required this.receiverName,
    this.senderAvatarUrl,
    this.receiverAvatarUrl,
  });

  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  factory GiftEvent.fromJson(Map<dynamic, dynamic> j) => GiftEvent(
        giftId: _toInt(j['giftId']),
        giftNameAr: (j['giftNameAr'] ?? '').toString(),
        giftImageUrl: (j['giftImageUrl'] ?? '').toString(),
        giftAnimationUrl: j['giftAnimationUrl']?.toString(),
        coinsValue: _toInt(j['coinsValue']),
        senderId: _toInt(j['senderId']),
        senderName: (j['senderName'] ?? '').toString(),
        senderAvatarUrl: j['senderAvatarUrl']?.toString(),
        receiverId: _toInt(j['receiverId']),
        receiverName: (j['receiverName'] ?? '').toString(),
        receiverAvatarUrl: j['receiverAvatarUrl']?.toString(),
      );
}

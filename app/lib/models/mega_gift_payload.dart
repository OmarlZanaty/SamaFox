class MegaGiftPayload {
  final String senderName;
  final String senderAvatarUrl;
  final String receiverName;
  final String receiverAvatarUrl;
  final String giftNameAr;
  final String giftImageUrl;
  final String? giftAnimationUrl;
  final int coinsValue;
  final String roomName;
  final String roomId;

  MegaGiftPayload.fromJson(Map<dynamic, dynamic> j)
      : senderName = (j['senderName'] ?? '').toString(),
        senderAvatarUrl = (j['senderAvatarUrl'] ?? '').toString(),
        receiverName = (j['receiverName'] ?? '').toString(),
        receiverAvatarUrl = (j['receiverAvatarUrl'] ?? '').toString(),
        giftNameAr = (j['giftNameAr'] ?? '').toString(),
        giftImageUrl = (j['giftImageUrl'] ?? '').toString(),
        giftAnimationUrl = j['giftAnimationUrl']?.toString(),
        coinsValue = j['coinsValue'] is int
            ? j['coinsValue'] as int
            : int.tryParse((j['coinsValue'] ?? 0).toString()) ?? 0,
        roomName = (j['roomName'] ?? '').toString(),
        roomId = (j['roomId'] ?? '').toString();
}

import 'package:json_annotation/json_annotation.dart';
import 'user.dart';

part 'gift.g.dart';

enum GiftAnimationType {
  normal,
  dragon,
  rocket,
  castle,
}

@JsonSerializable()
class Gift {
  final int id;
  final String name;
  final String? nameAr;
  final String? description;
  final String? imageUrl;
  final String? animationUrl;
  final String? category;
  final String? rarity;
  final int priceCoins;
  final int? coinsValue;
  final int? sortOrder;

  /// NEW
  final String? animationKey;

  final bool isActive;

  Gift({
    required this.id,
    required this.name,
    this.nameAr,
    this.description,
    this.imageUrl,
    this.animationUrl,
    this.category,
    this.rarity,
    required this.priceCoins,
    this.coinsValue,
    this.sortOrder,
    this.animationKey,
    this.isActive = true,
  });

  String get displayName => (nameAr?.trim().isNotEmpty == true) ? nameAr! : name;
  int get displayCoinsValue => coinsValue ?? priceCoins;

  factory Gift.fromJson(Map<String, dynamic> json) => _$GiftFromJson(json);
  Map<String, dynamic> toJson() => _$GiftToJson(this);
}

@JsonSerializable()
class GiftTransaction {
  final int id;
  final int giftId;
  final int senderId;
  final int receiverId;
  final int? roomId;
  final int coinsSpent;
  /// Number of gifts sent. Added for quantity support.
  final int? quantity;
  /// Optional message attached to this gift transaction.
  final String? message;
  final String createdAt;
  final Gift? gift;
  final User? sender;
  final User? receiver;

  GiftTransaction({
    required this.id,
    required this.giftId,
    required this.senderId,
    required this.receiverId,
    this.roomId,
    required this.coinsSpent,
    this.quantity,
    this.message,
    required this.createdAt,
    this.gift,
    this.sender,
    this.receiver,
  });

  factory GiftTransaction.fromJson(Map<String, dynamic> json) =>
      _$GiftTransactionFromJson(json);
  Map<String, dynamic> toJson() => _$GiftTransactionToJson(this);
}

@JsonSerializable()
class SendGiftRequest {
  final int giftId;
  final int receiverId;
  final int? roomId;
  /// Number of gifts to send. Defaults to 1 if not provided.
  final int? quantity;
  /// Optional message to send with the gift.
  final String? message;

  SendGiftRequest({
    required this.giftId,
    required this.receiverId,
    this.roomId,
    this.quantity,
    this.message,
  });

  factory SendGiftRequest.fromJson(Map<String, dynamic> json) =>
      _$SendGiftRequestFromJson(json);
  Map<String, dynamic> toJson() => _$SendGiftRequestToJson(this);
}

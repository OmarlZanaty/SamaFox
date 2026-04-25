// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gift.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Gift _$GiftFromJson(Map<String, dynamic> json) => Gift(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      nameAr: json['nameAr'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      animationUrl: json['animationUrl'] as String?,
      category: json['category'] as String?,
      rarity: json['rarity'] as String?,
      priceCoins: ((json['priceCoins'] as num?) ??
              (json['coinsValue'] as num?) ??
              (json['price_coins'] as num?) ??
              (json['coins_value'] as num?) ??
              (json['price'] as num?) ??
              (json['cost'] as num?) ??
              0)
          .toInt(),
      coinsValue: ((json['coinsValue'] as num?) ??
              (json['coins_value'] as num?) ??
              (json['priceCoins'] as num?) ??
              (json['price_coins'] as num?) ??
              (json['price'] as num?) ??
              (json['cost'] as num?))
          ?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt(),
      animationKey: (json['animationKey'] ?? json['animation_key']) as String?,
      isActive: json['isActive'] as bool? ?? true,
    );

Map<String, dynamic> _$GiftToJson(Gift instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'nameAr': instance.nameAr,
      'description': instance.description,
      'imageUrl': instance.imageUrl,
      'animationUrl': instance.animationUrl,
      'category': instance.category,
      'rarity': instance.rarity,
      'priceCoins': instance.priceCoins,
      'coinsValue': instance.coinsValue,
      'sortOrder': instance.sortOrder,
      'animationKey': instance.animationKey,
      'isActive': instance.isActive,
    };

GiftTransaction _$GiftTransactionFromJson(Map<String, dynamic> json) =>
    GiftTransaction(
      id: (json['id'] as num).toInt(),
      giftId: (json['giftId'] as num).toInt(),
      senderId: (json['senderId'] as num).toInt(),
      receiverId: (json['receiverId'] as num).toInt(),
      roomId: (json['roomId'] as num?)?.toInt(),
      coinsSpent: (json['coinsSpent'] as num).toInt(),
      quantity: (json['quantity'] as num?)?.toInt(),
      message: json['message'] as String?,
      createdAt: json['createdAt'] as String,
      gift: json['gift'] == null
          ? null
          : Gift.fromJson(json['gift'] as Map<String, dynamic>),
      sender: json['sender'] == null
          ? null
          : User.fromJson(json['sender'] as Map<String, dynamic>),
      receiver: json['receiver'] == null
          ? null
          : User.fromJson(json['receiver'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GiftTransactionToJson(GiftTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'giftId': instance.giftId,
      'senderId': instance.senderId,
      'receiverId': instance.receiverId,
      'roomId': instance.roomId,
      'coinsSpent': instance.coinsSpent,
      'quantity': instance.quantity,
      'message': instance.message,
      'createdAt': instance.createdAt,
      'gift': instance.gift,
      'sender': instance.sender,
      'receiver': instance.receiver,
    };

SendGiftRequest _$SendGiftRequestFromJson(Map<String, dynamic> json) =>
    SendGiftRequest(
      giftId: (json['giftId'] as num).toInt(),
      receiverId: (json['receiverId'] as num).toInt(),
      roomId: (json['roomId'] as num?)?.toInt(),
      quantity: (json['quantity'] as num?)?.toInt(),
      message: json['message'] as String?,
    );

Map<String, dynamic> _$SendGiftRequestToJson(SendGiftRequest instance) =>
    <String, dynamic>{
      'giftId': instance.giftId,
      'receiverId': instance.receiverId,
      'roomId': instance.roomId,
      'quantity': instance.quantity,
      'message': instance.message,
    };

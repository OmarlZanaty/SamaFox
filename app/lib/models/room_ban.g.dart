// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_ban.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoomBan _$RoomBanFromJson(Map<String, dynamic> json) => RoomBan(
      id: (json['id'] as num).toInt(),
      roomId: (json['roomId'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      bannedBy: (json['bannedBy'] as num).toInt(),
      reason: json['reason'] as String?,
      bannedAt: json['bannedAt'] as String,
      expiresAt: json['expiresAt'] as String?,
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
      banner: json['banner'] == null
          ? null
          : User.fromJson(json['banner'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$RoomBanToJson(RoomBan instance) => <String, dynamic>{
      'id': instance.id,
      'roomId': instance.roomId,
      'userId': instance.userId,
      'bannedBy': instance.bannedBy,
      'reason': instance.reason,
      'bannedAt': instance.bannedAt,
      'expiresAt': instance.expiresAt,
      'user': instance.user?.toJson(),
      'banner': instance.banner?.toJson(),
    };

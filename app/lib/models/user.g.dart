// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      id: (json['id'] as num).toInt(),
      displayId: (json['displayId'] as num?)?.toInt(),
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      countryCode: json['countryCode'] as String?,
      country: json['country'] as String?,
      gender: json['gender'] as String?,
      birthday: json['birthday'] as String?,
      bio: json['bio'] as String?,
      level: (json['level'] as num?)?.toInt() ?? 1,
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      coins: (json['coins'] as num?)?.toInt() ?? 0,
      coinsBalance: (json['coinsBalance'] as num?)?.toInt() ?? 0,
      vipLevel: (json['vipLevel'] as num?)?.toInt() ?? 0,
      vipExpiresAt: json['vipExpiresAt'] as String?,
      isAdmin: json['isAdmin'] as bool? ?? false,
      isOnline: json['isOnline'] as bool? ?? false,
      followersCount: (json['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'displayId': instance.displayId,
      'name': instance.name,
      'email': instance.email,
      'phone': instance.phone,
      'avatarUrl': instance.avatarUrl,
      'countryCode': instance.countryCode,
      'country': instance.country,
      'gender': instance.gender,
      'birthday': instance.birthday,
      'bio': instance.bio,
      'level': instance.level,
      'xp': instance.xp,
      'coins': instance.coins,
      'coinsBalance': instance.coinsBalance,
      'vipLevel': instance.vipLevel,
      'vipExpiresAt': instance.vipExpiresAt,
      'isAdmin': instance.isAdmin,
      'isOnline': instance.isOnline,
      'followersCount': instance.followersCount,
      'followingCount': instance.followingCount,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };

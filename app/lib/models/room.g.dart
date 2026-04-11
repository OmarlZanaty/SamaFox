// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoomMember _$RoomMemberFromJson(Map<String, dynamic> json) => RoomMember(
      userId: (json['userId'] as num?)?.toInt(),
      role: json['role'] as String?,
      isMuted: json['isMuted'] as bool?,
      joinedAt: json['joinedAt'] as String?,
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
      id: (json['id'] as num?)?.toInt(),
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );

Map<String, dynamic> _$RoomMemberToJson(RoomMember instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'role': instance.role,
      'isMuted': instance.isMuted,
      'joinedAt': instance.joinedAt,
      'user': instance.user,
      'id': instance.id,
      'name': instance.name,
      'avatarUrl': instance.avatarUrl,
    };

Room _$RoomFromJson(Map<String, dynamic> json) => Room(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      roomNumber: json['roomNumber'] as String?,
      description: json['description'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      backgroundImageUrl: json['backgroundImageUrl'] as String?,
      isPublic: json['isPublic'] as bool? ?? true,
      currentMembers: (json['currentMembers'] as num?)?.toInt() ?? 0,
      maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 50,
      maxSeats: (json['maxSeats'] as num?)?.toInt() ?? 8,
      type: json['type'] as String? ?? 'voice',
      ownerId: (json['ownerId'] as num?)?.toInt(),
      owner: json['owner'] == null
          ? null
          : User.fromJson(json['owner'] as Map<String, dynamic>),
      members: (json['members'] as List<dynamic>?)
              ?.map((e) => RoomMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      membersCount: (json['membersCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      isLocked: json['isLocked'] as bool? ?? false,
      backgroundMusicUrl: json['backgroundMusicUrl'] as String?,
      muteGiftSounds: json['muteGiftSounds'] as bool? ?? false,
      muteEntranceSounds: json['muteEntranceSounds'] as bool? ?? false,
    );

Map<String, dynamic> _$RoomToJson(Room instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'roomNumber': instance.roomNumber,
      'description': instance.description,
      'coverImageUrl': instance.coverImageUrl,
      'backgroundImageUrl': instance.backgroundImageUrl,
      'isPublic': instance.isPublic,
      'currentMembers': instance.currentMembers,
      'maxMembers': instance.maxMembers,
      'maxSeats': instance.maxSeats,
      'type': instance.type,
      'ownerId': instance.ownerId,
      'owner': instance.owner?.toJson(),
      'members': instance.members?.map((e) => e.toJson()).toList(),
      'membersCount': instance.membersCount,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
      'isLocked': instance.isLocked,
      'backgroundMusicUrl': instance.backgroundMusicUrl,
      'muteGiftSounds': instance.muteGiftSounds,
      'muteEntranceSounds': instance.muteEntranceSounds,
    };

CreateRoomRequest _$CreateRoomRequestFromJson(Map<String, dynamic> json) =>
    CreateRoomRequest(
      name: json['name'] as String,
      roomNumber: json['roomNumber'] as String?,
      description: json['description'] as String?,
      coverImage: json['coverImage'] as String?,
      isPublic: json['isPublic'] as bool? ?? true,
      maxSeats: (json['maxSeats'] as num?)?.toInt() ?? 8,
      maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 50,
    );

Map<String, dynamic> _$CreateRoomRequestToJson(CreateRoomRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'roomNumber': instance.roomNumber,
      'description': instance.description,
      'coverImage': instance.coverImage,
      'isPublic': instance.isPublic,
      'maxSeats': instance.maxSeats,
      'maxMembers': instance.maxMembers,
    };

UpdateRoomRequest _$UpdateRoomRequestFromJson(Map<String, dynamic> json) =>
    UpdateRoomRequest(
      name: json['name'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      maxMembers: (json['maxMembers'] as num?)?.toInt(),
      maxSeats: (json['maxSeats'] as num?)?.toInt(),
      isPublic: json['isPublic'] as bool?,
    );

Map<String, dynamic> _$UpdateRoomRequestToJson(UpdateRoomRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'imageUrl': instance.imageUrl,
      'maxMembers': instance.maxMembers,
      'maxSeats': instance.maxSeats,
      'isPublic': instance.isPublic,
    };

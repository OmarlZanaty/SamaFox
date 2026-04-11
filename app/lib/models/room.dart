import 'package:json_annotation/json_annotation.dart';
import 'user.dart';

part 'room.g.dart';

@JsonSerializable()
class RoomMember {
  final int? userId;
  final String? role;
  final bool? isMuted;
  final String? joinedAt;
  final User? user;

  // For handling both RoomMember and User formats
  final int? id;
  final String? name;
  final String? avatarUrl;

  final int? ownerId;

  RoomMember({
    this.userId,
    this.role,
    this.isMuted,
    this.joinedAt,
    this.user,
    this.id,
    this.name,
    this.avatarUrl,
    this.ownerId,

  });

  factory RoomMember.fromJson(Map<String, dynamic> json) =>
      _$RoomMemberFromJson(json);
  Map<String, dynamic> toJson() => _$RoomMemberToJson(this);

  // Helper to get user ID from either format
  int? get userId_ => userId ?? id;

  // Helper to get User object (create one if only simple fields exist)
  User? get userObject => user ?? (id != null ? User(
    id: id!,
    name: name ?? '',
    avatarUrl: avatarUrl,
  ) : null);
}

@JsonSerializable(explicitToJson: true)
class Room {
  final int id;
  final String name;
  final String? roomNumber;
  final String? description;
  final String? coverImageUrl;
  final String? backgroundImageUrl;

  @JsonKey(defaultValue: true)
  final bool? isPublic;

  @JsonKey(defaultValue: 0)
  final int? currentMembers;

  @JsonKey(defaultValue: 50)
  final int? maxMembers;

  @JsonKey(defaultValue: 8)
  final int? maxSeats;

  @JsonKey(defaultValue: 'voice')
  final String? type;

  final int? ownerId;
  final User? owner;

  @JsonKey(defaultValue: [])
  final List<RoomMember>? members;

  @JsonKey(defaultValue: 0)
  final int? membersCount;

  final String? createdAt;
  final String? updatedAt;

  // Admin control fields
  @JsonKey(defaultValue: false)
  final bool? isLocked;

  final String? backgroundMusicUrl;

  @JsonKey(defaultValue: false)
  final bool? muteGiftSounds;

  @JsonKey(defaultValue: false)
  final bool? muteEntranceSounds;

  Room({
    required this.id,
    required this.name,
    this.roomNumber,
    this.description,
    this.coverImageUrl,
    this.backgroundImageUrl,
    this.isPublic,
    this.currentMembers,
    this.maxMembers,
    this.maxSeats,
    this.type,
    this.ownerId,
    this.owner,
    this.members,
    this.membersCount,
    this.createdAt,
    this.updatedAt,
    this.isLocked,
    this.backgroundMusicUrl,
    this.muteGiftSounds,
    this.muteEntranceSounds,
  });

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);
  Map<String, dynamic> toJson() => _$RoomToJson(this);

  // Helper getters with defaults
  bool get isPublicRoom => isPublic ?? true;
  int get currentMembersCount => currentMembers ?? 0;
  int get maxMembersLimit => maxMembers ?? 50;
  int get maxSeatsLimit => maxSeats ?? 8;
  String get roomType => type ?? 'voice';
  List<RoomMember> get roomMembers => members ?? [];
  int get totalMembersCount => membersCount ?? 0;
  bool get isRoomLocked => isLocked ?? false;
  bool get giftSoundsMuted => muteGiftSounds ?? false;
  bool get entranceSoundsMuted => muteEntranceSounds ?? false;

  bool isOwner(int userId) {
    if (owner == null) return false;
    return owner!.id == userId;
  }

  bool isMember(int userId) {
    if (members == null || members!.isEmpty) return false;
    return members!.any((m) => m.userId_ == userId);
  }



}

@JsonSerializable()
class CreateRoomRequest {
  final String name;
  final String? roomNumber;
  final String? description;
  final String? coverImage;
  final bool isPublic;
  final int maxSeats;
  final int maxMembers;

  CreateRoomRequest({
    required this.name,
    this.roomNumber,
    this.description,
    this.coverImage,
    this.isPublic = true,
    this.maxSeats = 8,
    this.maxMembers = 50,
  });

  factory CreateRoomRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateRoomRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateRoomRequestToJson(this);
}

@JsonSerializable()
class UpdateRoomRequest {
  final String? name;
  final String? description;
  final String? imageUrl;
  final int? maxMembers;
  final int? maxSeats;
  final bool? isPublic;

  UpdateRoomRequest({
    this.name,
    this.description,
    this.imageUrl,
    this.maxMembers,
    this.maxSeats,
    this.isPublic,
  });

  factory UpdateRoomRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateRoomRequestFromJson(json);
  Map<String, dynamic> toJson() => _$UpdateRoomRequestToJson(this);
}

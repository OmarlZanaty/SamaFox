import 'package:json_annotation/json_annotation.dart';

import '../utils/json_utils.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final int id;
  final int? displayId;
  final String name;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String? countryCode;
  final String? country;
  final String? gender;
  final String? birthday;
  final int? age;
  final int? liveRoomId; // #31: room this user is ACTUALLY in right now, guest or host (null if none)
  final String? bio;
  final String? avatarFrameUrl;
  @JsonKey(defaultValue: 1)
  final int? level;

  @JsonKey(defaultValue: 0)
  final int? xp;

  @JsonKey(name: 'coins', defaultValue: 0)
  final int? coins;

  @JsonKey(defaultValue: 0)
  final int? coinsBalance;

  @JsonKey(defaultValue: 0)
  final int? vipLevel;

  final String? vipExpiresAt;

  @JsonKey(defaultValue: false)
  final bool? isAdmin;

  @JsonKey(defaultValue: false)
  final bool? isOnline;

  @JsonKey(defaultValue: 0)
  final int? followersCount;

  @JsonKey(defaultValue: 0)
  final int? followingCount;

  final String? createdAt;
  final String? updatedAt;

  /// 'agent' (وكيل) | 'host' (مضيف) | null — from the hosting-agency system.
  final String? agencyRole;
  final String? agencyName;

  /// Real family/kingdom name — null when the user owns/joined no family.
  /// Never a placeholder; the room profile card only shows this badge when
  /// it's non-null.
  final String? familyName;

  /// Most recently unlocked achievements (newest first, capped server-side
  /// at 4) — feeds the room profile card's medals row.
  final List<AchievementBadge>? achievements;

  User({
    required this.id,
    this.displayId,
    required this.name,
    this.email,
    this.phone,
    this.avatarUrl,
    this.countryCode,
    this.country,
    this.gender,
    this.birthday,
    this.age,
    this.liveRoomId,
    this.bio,
    this.level,
    this.xp,
    this.coins,
    this.coinsBalance,
    this.vipLevel,
    this.vipExpiresAt,
    this.isAdmin,
    this.isOnline,
    this.followersCount,
    this.followingCount,
    this.createdAt,
    this.updatedAt,
    this.avatarFrameUrl,
    this.agencyRole,
    this.agencyName,
    this.familyName,
    this.achievements,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final source = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json;

    return User(
      id: asInt(source['id']),
      displayId: source['displayId'] == null ? null : asInt(source['displayId']),
      name: (source['name'] ?? '').toString(),
      email: source['email']?.toString(),
      phone: source['phone']?.toString(),
      avatarUrl: source['avatarUrl']?.toString(),
      countryCode: source['countryCode']?.toString(),
      country: source['country']?.toString(),
      gender: source['gender']?.toString(),
      birthday: source['birthday']?.toString(),
      age: source['age'] is int ? source['age'] as int : int.tryParse(source['age']?.toString() ?? ''),
      liveRoomId: source['liveRoomId'] is int ? source['liveRoomId'] as int : int.tryParse(source['liveRoomId']?.toString() ?? ''),
      bio: source['bio']?.toString(),
      level: asInt(source['level'], fallback: 1),
      xp: asInt(source['xp']),
      coins: asInt(source['coins']),
      coinsBalance: asInt(
        source['coinsBalance']
            ?? source['coins_balance']
            ?? source['userBalance']
            ?? source['coins'],  // ✅ ADD THIS as last fallback
      ),

      vipLevel: asInt(source['vipLevel']),
      vipExpiresAt: source['vipExpiresAt']?.toString(),
      isAdmin: asBool(source['isAdmin']),
      isOnline: asBool(source['isOnline']),
      followersCount: asInt(source['followersCount'] ?? source['followerCount']),
      followingCount: asInt(source['followingCount']),
      createdAt: source['createdAt']?.toString(),
      updatedAt: source['updatedAt']?.toString(),
      avatarFrameUrl: source['avatarFrameUrl']?.toString(),
      agencyRole: source['agencyRole']?.toString(),
      agencyName: source['agencyName']?.toString(),
      familyName: source['familyName']?.toString(),
      achievements: (source['achievements'] as List?)
          ?.whereType<Map>()
          .map((e) => AchievementBadge.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
  Map<String, dynamic> toJson() => _$UserToJson(this);

  // Helper getters with defaults
  int get userLevel => level ?? 1;
  int get userXp => xp ?? 0;
  int get userCoins => coins ?? 0;
  int get userCoinsBalance => coinsBalance ?? 0;
  int get userVipLevel => vipLevel ?? 0;
  bool get userIsAdmin => isAdmin ?? false;
  bool get userIsOnline => isOnline ?? false;
  int get userFollowersCount => followersCount ?? 0;
  int get userFollowingCount => followingCount ?? 0;
  int get publicDisplayId => (displayId != null && displayId! >= 10000) ? displayId! : id;

  User copyWith({
    int? id,
    int? displayId,
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    String? countryCode,
    String? country,
    String? gender,
    String? birthday,
    int? age,
    int? liveRoomId,
    String? bio,
    int? level,
    int? xp,
    int? coins,
    int? coinsBalance,
    int? vipLevel,
    String? vipExpiresAt,
    bool? isAdmin,
    bool? isOnline,
    int? followersCount,
    int? followingCount,
    String? createdAt,
    String? updatedAt,
    String? avatarFrameUrl,
    String? agencyRole,
    String? agencyName,
    String? familyName,
    List<AchievementBadge>? achievements,
  }) {
    return User(
      id: id ?? this.id,
      displayId: displayId ?? this.displayId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      countryCode: countryCode ?? this.countryCode,
      country: country ?? this.country,
      gender: gender ?? this.gender,
      birthday: birthday ?? this.birthday,
      age: age ?? this.age,
      liveRoomId: liveRoomId ?? this.liveRoomId,
      bio: bio ?? this.bio,
      level: level ?? this.level,
      xp: xp ?? this.xp,
      coins: coins ?? this.coins,
      coinsBalance: coinsBalance ?? this.coinsBalance,
      vipLevel: vipLevel ?? this.vipLevel,
      vipExpiresAt: vipExpiresAt ?? this.vipExpiresAt,
      isAdmin: isAdmin ?? this.isAdmin,
      isOnline: isOnline ?? this.isOnline,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      avatarFrameUrl: avatarFrameUrl ?? this.avatarFrameUrl,
      agencyRole: agencyRole ?? this.agencyRole,
      agencyName: agencyName ?? this.agencyName,
      familyName: familyName ?? this.familyName,
      achievements: achievements ?? this.achievements,
    );
  }
}

/// One unlocked achievement, as shown in the room profile card's medals row.
class AchievementBadge {
  final String name;
  final String iconUrl;

  const AchievementBadge({required this.name, required this.iconUrl});

  factory AchievementBadge.fromJson(Map<String, dynamic> json) => AchievementBadge(
        name: (json['name'] ?? '').toString(),
        iconUrl: (json['iconUrl'] ?? '').toString(),
      );
}

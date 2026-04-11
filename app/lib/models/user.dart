import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String? countryCode;
  final String? country;
  final String? gender;
  final String? birthday;
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

  User({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.avatarUrl,
    this.countryCode,
    this.country,
    this.gender,
    this.birthday,
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
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
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

  User copyWith({
    int? id,
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    String? countryCode,
    String? country,
    String? gender,
    String? birthday,
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
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      countryCode: countryCode ?? this.countryCode,
      country: country ?? this.country,
      gender: gender ?? this.gender,
      birthday: birthday ?? this.birthday,
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

    );
  }
}

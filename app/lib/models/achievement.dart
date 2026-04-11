class Achievement {
  final String id;
  final String name;
  final String description;
  final String iconUrl;
  final int target;
  final String metric;
  final DateTime createdAt;
  final DateTime updatedAt;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.target,
    required this.metric,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      iconUrl: json['iconUrl'] as String,
      target: json['target'] as int,
      metric: json['metric'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'iconUrl': iconUrl,
      'target': target,
      'metric': metric,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class UserAchievement {
  final String id;
  final int userId;
  final String achievementId;
  final DateTime unlockedAt;
  final Achievement? achievement;

  UserAchievement({
    required this.id,
    required this.userId,
    required this.achievementId,
    required this.unlockedAt,
    this.achievement,
  });

  factory UserAchievement.fromJson(Map<String, dynamic> json) {
    return UserAchievement(
      id: json['id'] as String,
      userId: json['userId'] as int,
      achievementId: json['achievementId'] as String,
      unlockedAt: DateTime.parse(json['unlockedAt'] as String),
      achievement: json['achievement'] != null
          ? Achievement.fromJson(json['achievement'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'achievementId': achievementId,
      'unlockedAt': unlockedAt.toIso8601String(),
      'achievement': achievement?.toJson(),
    };
  }

  UserAchievement copyWith({
    String? id,
    int? userId,
    String? achievementId,
    DateTime? unlockedAt,
    Achievement? achievement,
  }) {
    return UserAchievement(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      achievementId: achievementId ?? this.achievementId,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      achievement: achievement ?? this.achievement,
    );
  }
}

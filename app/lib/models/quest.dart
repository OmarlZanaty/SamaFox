class DailyQuest {
  final String id;
  final String name;
  final String description;
  final String metric;
  final int target;
  final int rewardCoins;
  final DateTime createdAt;
  final DateTime updatedAt;

  DailyQuest({
    required this.id,
    required this.name,
    required this.description,
    required this.metric,
    required this.target,
    required this.rewardCoins,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyQuest.fromJson(Map<String, dynamic> json) {
    return DailyQuest(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      metric: json['metric'] as String,
      target: json['target'] as int,
      rewardCoins: json['rewardCoins'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'metric': metric,
      'target': target,
      'rewardCoins': rewardCoins,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class QuestWithProgress extends DailyQuest {
  final int progress;
  final bool isComplete;
  final String? userQuestId;

  QuestWithProgress({
    required super.id,
    required super.name,
    required super.description,
    required super.metric,
    required super.target,
    required super.rewardCoins,
    required super.createdAt,
    required super.updatedAt,
    required this.progress,
    required this.isComplete,
    this.userQuestId,
  });

  factory QuestWithProgress.fromJson(Map<String, dynamic> json) {
    return QuestWithProgress(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      metric: json['metric'] as String,
      target: json['target'] as int,
      rewardCoins: json['rewardCoins'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      progress: json['progress'] as int? ?? 0,
      isComplete: json['isComplete'] as bool? ?? false,
      userQuestId: json['userQuestId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['progress'] = progress;
    map['isComplete'] = isComplete;
    map['userQuestId'] = userQuestId;
    return map;
  }

  double get progressPercentage => (progress / target * 100).clamp(0, 100);
}

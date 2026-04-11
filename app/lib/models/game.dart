class DiceRollResponse {
  final bool success;
  final int diceResult;
  final int xpEarned;
  final int leaderboardPoints;
  final int userXp;
  final int leaderboardRank;

  DiceRollResponse({
    required this.success,
    required this.diceResult,
    required this.xpEarned,
    required this.leaderboardPoints,
    required this.userXp,
    required this.leaderboardRank,
  });

  factory DiceRollResponse.fromJson(Map<String, dynamic> json) {
    return DiceRollResponse(
      success: json['success'] ?? false,
      diceResult: json['diceResult'] ?? 0,
      xpEarned: json['xpEarned'] ?? 0,
      leaderboardPoints: json['leaderboardPoints'] ?? 0,
      userXp: json['userXp'] ?? 0,
      leaderboardRank: json['leaderboardRank'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'diceResult': diceResult,
    'xpEarned': xpEarned,
    'leaderboardPoints': leaderboardPoints,
    'userXp': userXp,
    'leaderboardRank': leaderboardRank,
  };
}

class LeaderboardResponse {
  final List<LeaderboardEntry> leaderboard;

  LeaderboardResponse({required this.leaderboard});

  factory LeaderboardResponse.fromJson(Map<String, dynamic> json) {
    return LeaderboardResponse(
      leaderboard: (json['leaderboard'] as List)
          .map((e) => LeaderboardEntry.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'leaderboard': leaderboard.map((e) => e.toJson()).toList(),
  };
}

class LeaderboardEntry {
  final int id;
  final String name;
  final String? avatarUrl;
  final int level;
  final int xp;

  LeaderboardEntry({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.level,
    required this.xp,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      avatarUrl: json['avatarUrl'],
      level: json['level'] ?? 0,
      xp: json['xp'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'level': level,
    'xp': xp,
  };
}

class GameStats {
  final int id;
  final String name;
  final String? avatarUrl;
  final int level;
  final int xp;
  final int totalPoints;
  final int gamesPlayed;
  final int totalXpEarned;

  GameStats({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.level,
    required this.xp,
    required this.totalPoints,
    required this.gamesPlayed,
    required this.totalXpEarned,
  });

  factory GameStats.fromJson(Map<String, dynamic> json) {
    return GameStats(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      avatarUrl: json['avatarUrl'],
      level: json['level'] ?? 0,
      xp: json['xp'] ?? 0,
      totalPoints: json['totalPoints'] ?? 0,
      gamesPlayed: json['gamesPlayed'] ?? 0,
      totalXpEarned: json['totalXpEarned'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'level': level,
    'xp': xp,
    'totalPoints': totalPoints,
    'gamesPlayed': gamesPlayed,
    'totalXpEarned': totalXpEarned,
  };
}

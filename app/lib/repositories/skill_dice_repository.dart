import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the skill-dice round endpoints (نرد المهارة).
///
/// This is deliberately NOT a betting game: the entry price is fixed and known
/// before you pay, every entrant is guaranteed a reward, and the payout depends
/// on how well the mission was performed — never on odds applied to the stake.
/// The server owns the mission, the scoring and the reward table; see
/// backend/src/services/skillDice.service.ts.
class SkillDiceRepository {
  SkillDiceRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<DiceRound?> fetchRound() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/dice/round');
      final raw = res.data?['round'];
      if (raw is Map) return DiceRound.fromJson(Map<String, dynamic>.from(raw));
      return null;
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تحميل الجولة');
    }
  }

  /// Pays the fixed entry price for the current round.
  Future<DiceJoinResult> join(int entry) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/dice/round/join',
        data: {'entry': entry},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw SkillDiceException(body['message']?.toString() ?? 'تعذر دخول الجولة');
      }
      return DiceJoinResult(
        roundId: (body['roundId'] as num?)?.toInt() ?? 0,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        minReward: (body['minReward'] as num?)?.toInt() ?? 0,
        maxReward: (body['maxReward'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر دخول الجولة');
    }
  }

  /// Reports the faces the player stopped the dice on.
  Future<DiceSubmitResult> submit({required int roundId, required List<int> dice}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/dice/round/submit',
        data: {'roundId': roundId, 'dice': dice},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw SkillDiceException(body['message']?.toString() ?? 'تعذر تسجيل النتيجة');
      }
      return DiceSubmitResult(
        score: (body['score'] as num?)?.toInt() ?? 0,
        reward: (body['reward'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تسجيل النتيجة');
    }
  }

  SkillDiceException _translate(DioException e, {required String fallback}) {
    final data = e.response?.data;
    String? code;
    String? serverMessage;
    if (data is Map) {
      code = data['code']?.toString();
      serverMessage = data['message']?.toString();
    }
    return SkillDiceException(serverMessage ?? fallback, code: code);
  }
}

/// A live round as broadcast by the server (`dice_round_state`).
class DiceRound {
  final int roundId;
  final String phase; // join | play | result
  final int msLeft;
  final String? missionLabel;
  final List<int> entryTiers;
  final List<DicePlayer> players;

  const DiceRound({
    required this.roundId,
    required this.phase,
    required this.msLeft,
    required this.missionLabel,
    required this.entryTiers,
    required this.players,
  });

  bool get isJoining => phase == 'join';
  bool get isPlaying => phase == 'play';
  bool get isResult => phase == 'result';

  factory DiceRound.fromJson(Map<String, dynamic> json) {
    final mission = json['mission'];
    final tiers = (json['entryTiers'] as List?) ?? const [];
    final players = (json['players'] as List?) ?? const [];
    return DiceRound(
      roundId: (json['roundId'] as num?)?.toInt() ?? 0,
      phase: json['phase']?.toString() ?? 'join',
      msLeft: (json['msLeft'] as num?)?.toInt() ?? 0,
      missionLabel: mission is Map ? mission['label']?.toString() : null,
      entryTiers: tiers.map((e) => (e as num).toInt()).toList(),
      players: players
          .whereType<Map>()
          .map((p) => DicePlayer.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }
}

class DicePlayer {
  final int userId;
  final String name;
  final String? avatarUrl;
  final int entry;
  final bool submitted;

  const DicePlayer({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.entry,
    required this.submitted,
  });

  factory DicePlayer.fromJson(Map<String, dynamic> json) => DicePlayer(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        entry: (json['entry'] as num?)?.toInt() ?? 0,
        submitted: json['submitted'] == true,
      );
}

/// One podium row from `dice_round_result`.
class DicePodiumEntry {
  final int rank;
  final int userId;
  final String name;
  final String? avatarUrl;
  final int score;
  final int reward;

  const DicePodiumEntry({
    required this.rank,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.score,
    required this.reward,
  });

  factory DicePodiumEntry.fromJson(Map<String, dynamic> json) => DicePodiumEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        score: (json['score'] as num?)?.toInt() ?? 0,
        reward: (json['reward'] as num?)?.toInt() ?? 0,
      );
}

class DiceJoinResult {
  final int roundId;
  final int balance;
  final int minReward;
  final int maxReward;
  const DiceJoinResult({
    required this.roundId,
    required this.balance,
    required this.minReward,
    required this.maxReward,
  });
}

class DiceSubmitResult {
  final int score;
  final int reward;
  const DiceSubmitResult({required this.score, required this.reward});
}

class SkillDiceException implements Exception {
  final String message;
  final String? code;
  SkillDiceException(this.message, {this.code});
  @override
  String toString() => 'SkillDiceException(${code ?? '?'}: $message)';
}

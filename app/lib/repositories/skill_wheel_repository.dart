import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the skill-wheel round endpoints (عجلة المهارة).
///
/// This is deliberately NOT a roulette table: there are no betting zones and no
/// odds. The entry price is fixed and known before you pay, every entrant is
/// guaranteed a reward, and the payout depends on how close you stopped the
/// pointer to the announced target — never on chance applied to a stake. The
/// server owns the target, the scoring and the reward table; see
/// backend/src/services/skillWheel.service.ts.
class SkillWheelRepository {
  SkillWheelRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<WheelRound?> fetchRound() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/wheel/round');
      final raw = res.data?['round'];
      if (raw is Map) return WheelRound.fromJson(Map<String, dynamic>.from(raw));
      return null;
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تحميل الجولة');
    }
  }

  /// Pays the fixed entry price for the current round.
  Future<WheelJoinResult> join(int entry) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/wheel/round/join',
        data: {'entry': entry},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw SkillWheelException(body['message']?.toString() ?? 'تعذر دخول الجولة');
      }
      return WheelJoinResult(
        roundId: (body['roundId'] as num?)?.toInt() ?? 0,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        minReward: (body['minReward'] as num?)?.toInt() ?? 0,
        maxReward: (body['maxReward'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر دخول الجولة');
    }
  }

  /// Reports the pocket the player stopped the pointer on.
  Future<WheelSubmitResult> submit({required int roundId, required int landed}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/wheel/round/submit',
        data: {'roundId': roundId, 'landed': landed},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw SkillWheelException(body['message']?.toString() ?? 'تعذر تسجيل النتيجة');
      }
      return WheelSubmitResult(
        score: (body['score'] as num?)?.toInt() ?? 0,
        reward: (body['reward'] as num?)?.toInt() ?? 0,
        target: (body['target'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تسجيل النتيجة');
    }
  }

  SkillWheelException _translate(DioException e, {required String fallback}) {
    final data = e.response?.data;
    String? code;
    String? serverMessage;
    if (data is Map) {
      code = data['code']?.toString();
      serverMessage = data['message']?.toString();
    }
    return SkillWheelException(serverMessage ?? fallback, code: code);
  }
}

/// A live round as broadcast by the server (`wheel_round_state`).
class WheelRound {
  final int roundId;
  final String phase; // join | play | result
  final int msLeft;
  final int? target;
  final String? missionLabel;
  final List<int> entryTiers;
  final List<WheelPlayer> players;

  const WheelRound({
    required this.roundId,
    required this.phase,
    required this.msLeft,
    required this.target,
    required this.missionLabel,
    required this.entryTiers,
    required this.players,
  });

  bool get isJoining => phase == 'join';
  bool get isPlaying => phase == 'play';
  bool get isResult => phase == 'result';

  factory WheelRound.fromJson(Map<String, dynamic> json) {
    final mission = json['mission'];
    final tiers = (json['entryTiers'] as List?) ?? const [];
    final players = (json['players'] as List?) ?? const [];
    return WheelRound(
      roundId: (json['roundId'] as num?)?.toInt() ?? 0,
      phase: json['phase']?.toString() ?? 'join',
      msLeft: (json['msLeft'] as num?)?.toInt() ?? 0,
      target: mission is Map ? (mission['target'] as num?)?.toInt() : null,
      missionLabel: mission is Map ? mission['label']?.toString() : null,
      entryTiers: tiers.map((e) => (e as num).toInt()).toList(),
      players: players
          .whereType<Map>()
          .map((p) => WheelPlayer.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }
}

class WheelPlayer {
  final int userId;
  final String name;
  final String? avatarUrl;
  final int entry;
  final bool submitted;

  const WheelPlayer({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.entry,
    required this.submitted,
  });

  factory WheelPlayer.fromJson(Map<String, dynamic> json) => WheelPlayer(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        entry: (json['entry'] as num?)?.toInt() ?? 0,
        submitted: json['submitted'] == true,
      );
}

/// One podium row from `wheel_round_result`.
class WheelPodiumEntry {
  final int rank;
  final int userId;
  final String name;
  final String? avatarUrl;
  final int score;
  final int reward;

  const WheelPodiumEntry({
    required this.rank,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.score,
    required this.reward,
  });

  factory WheelPodiumEntry.fromJson(Map<String, dynamic> json) => WheelPodiumEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        score: (json['score'] as num?)?.toInt() ?? 0,
        reward: (json['reward'] as num?)?.toInt() ?? 0,
      );
}

class WheelJoinResult {
  final int roundId;
  final int balance;
  final int minReward;
  final int maxReward;
  const WheelJoinResult({
    required this.roundId,
    required this.balance,
    required this.minReward,
    required this.maxReward,
  });
}

class WheelSubmitResult {
  final int score;
  final int reward;
  final int target;
  const WheelSubmitResult({
    required this.score,
    required this.reward,
    required this.target,
  });
}

class SkillWheelException implements Exception {
  final String message;
  final String? code;
  SkillWheelException(this.message, {this.code});
  @override
  String toString() => 'SkillWheelException(${code ?? '?'}: $message)';
}

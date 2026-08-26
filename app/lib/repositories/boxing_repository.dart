import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the lion & tiger arena round endpoints (حلبة الأسد والنمر).
///
/// This is deliberately NOT a betting game: the entry price is fixed and known
/// before you pay, every fighter is guaranteed a reward, and the payout depends
/// on how well you land your own punches — never on odds applied to a stake.
/// Choosing الأسد or النمر picks the fighter you play as and nothing more.
/// The server owns the mission, the scoring and the reward table; see
/// backend/src/services/boxing.service.ts.
class BoxingRepository {
  BoxingRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<BoxingRound?> fetchRound() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/boxing/round');
      final raw = res.data?['round'];
      if (raw is Map) return BoxingRound.fromJson(Map<String, dynamic>.from(raw));
      return null;
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تحميل الجولة');
    }
  }

  /// Pays the fixed entry price for the current round and takes a corner.
  Future<BoxingJoinResult> join({required int entry, required String corner}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/boxing/round/join',
        data: {'entry': entry, 'corner': corner},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw BoxingException(body['message']?.toString() ?? 'تعذر دخول الجولة');
      }
      return BoxingJoinResult(
        roundId: (body['roundId'] as num?)?.toInt() ?? 0,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        minReward: (body['minReward'] as num?)?.toInt() ?? 0,
        maxReward: (body['maxReward'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر دخول الجولة');
    }
  }

  /// Reports the accuracy (0-100) of each punch the player threw.
  Future<BoxingSubmitResult> submit({required int roundId, required List<int> punches}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/boxing/round/submit',
        data: {'roundId': roundId, 'punches': punches},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw BoxingException(body['message']?.toString() ?? 'تعذر تسجيل النتيجة');
      }
      return BoxingSubmitResult(
        score: (body['score'] as num?)?.toInt() ?? 0,
        reward: (body['reward'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تسجيل النتيجة');
    }
  }

  BoxingException _translate(DioException e, {required String fallback}) {
    final data = e.response?.data;
    String? code;
    String? serverMessage;
    if (data is Map) {
      code = data['code']?.toString();
      serverMessage = data['message']?.toString();
    }
    return BoxingException(serverMessage ?? fallback, code: code);
  }
}

/// A live round as broadcast by the server (`boxing_round_state`).
class BoxingRound {
  final int roundId;
  final String phase; // join | play | result
  final int msLeft;
  final String? missionLabel;
  final List<int> entryTiers;
  final int punches;
  final List<BoxingPlayer> players;

  const BoxingRound({
    required this.roundId,
    required this.phase,
    required this.msLeft,
    required this.missionLabel,
    required this.entryTiers,
    required this.punches,
    required this.players,
  });

  bool get isJoining => phase == 'join';
  bool get isPlaying => phase == 'play';
  bool get isResult => phase == 'result';

  factory BoxingRound.fromJson(Map<String, dynamic> json) {
    final mission = json['mission'];
    final tiers = (json['entryTiers'] as List?) ?? const [];
    final players = (json['players'] as List?) ?? const [];
    return BoxingRound(
      roundId: (json['roundId'] as num?)?.toInt() ?? 0,
      phase: json['phase']?.toString() ?? 'join',
      msLeft: (json['msLeft'] as num?)?.toInt() ?? 0,
      missionLabel: mission is Map ? mission['label']?.toString() : null,
      entryTiers: tiers.map((e) => (e as num).toInt()).toList(),
      punches: (json['punches'] as num?)?.toInt() ?? 6,
      players: players
          .whereType<Map>()
          .map((p) => BoxingPlayer.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }
}

class BoxingPlayer {
  final int userId;
  final String name;
  final String? avatarUrl;
  final int entry;
  final String corner; // lion | tiger — cosmetic only
  final bool submitted;

  const BoxingPlayer({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.entry,
    required this.corner,
    required this.submitted,
  });

  factory BoxingPlayer.fromJson(Map<String, dynamic> json) => BoxingPlayer(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        entry: (json['entry'] as num?)?.toInt() ?? 0,
        corner: json['corner']?.toString() ?? 'lion',
        submitted: json['submitted'] == true,
      );
}

/// One podium row from `boxing_round_result`.
class BoxingPodiumEntry {
  final int rank;
  final int userId;
  final String name;
  final String? avatarUrl;
  final String corner;
  final int score;
  final int reward;

  const BoxingPodiumEntry({
    required this.rank,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.corner,
    required this.score,
    required this.reward,
  });

  factory BoxingPodiumEntry.fromJson(Map<String, dynamic> json) => BoxingPodiumEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        corner: json['corner']?.toString() ?? 'lion',
        score: (json['score'] as num?)?.toInt() ?? 0,
        reward: (json['reward'] as num?)?.toInt() ?? 0,
      );
}

class BoxingJoinResult {
  final int roundId;
  final int balance;
  final int minReward;
  final int maxReward;
  const BoxingJoinResult({
    required this.roundId,
    required this.balance,
    required this.minReward,
    required this.maxReward,
  });
}

class BoxingSubmitResult {
  final int score;
  final int reward;
  const BoxingSubmitResult({required this.score, required this.reward});
}

class BoxingException implements Exception {
  final String message;
  final String? code;
  BoxingException(this.message, {this.code});
  @override
  String toString() => 'BoxingException(${code ?? '?'}: $message)';
}

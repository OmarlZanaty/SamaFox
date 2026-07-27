import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the crash (طيّار) endpoints.
///
/// The server owns the crash point, the clock and every coin movement; this
/// client only animates the published curve and asks to bet / cash out. See
/// backend/src/services/crash.service.ts.
class CrashRepository {
  CrashRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<CrashStateSnapshot> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/crash/state');
      final body = res.data ?? const {};
      final raw = body['state'];
      return CrashStateSnapshot(
        state: raw is Map ? CrashState.fromJson(Map<String, dynamic>.from(raw)) : null,
        clientSeed: body['clientSeed']?.toString(),
        minBet: (body['minBet'] as num?)?.toInt() ?? 100,
        maxBet: (body['maxBet'] as num?)?.toInt() ?? 500000,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تحميل الجولة');
    }
  }

  /// Places a bet on one of the two panels. [autoCashOut] is settled by the
  /// server, so it still fires if the app is backgrounded.
  Future<CrashBetResult> placeBet({
    required int slot,
    required int amount,
    double? autoCashOut,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('games/crash/bet', data: {
        'slot': slot,
        'amount': amount,
        if (autoCashOut != null) 'autoCashOut': autoCashOut,
      });
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw CrashException(body['message']?.toString() ?? 'تعذر وضع الرهان');
      }
      return CrashBetResult(
        roundId: (body['roundId'] as num?)?.toInt() ?? 0,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        serverSeedHash: body['serverSeedHash']?.toString() ?? '',
        clientSeed: body['clientSeed']?.toString() ?? '',
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر وضع الرهان');
    }
  }

  /// Refunds a bet — only possible while betting is still open.
  Future<int> cancelBet(int slot) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/crash/cancel',
        data: {'slot': slot},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw CrashException(body['message']?.toString() ?? 'تعذر إلغاء الرهان');
      }
      return (body['balance'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر إلغاء الرهان');
    }
  }

  /// The server re-reads its own clock, so the multiplier paid is the one that
  /// was live when the request landed — not what our animation showed.
  Future<CrashCashOutResult> cashOut(int slot) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/crash/cashout',
        data: {'slot': slot},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw CrashException(body['message']?.toString() ?? 'تعذر السحب');
      }
      return CrashCashOutResult(
        multiplier: (body['multiplier'] as num?)?.toDouble() ?? 1.0,
        payout: (body['payout'] as num?)?.toInt() ?? 0,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر السحب');
    }
  }

  Future<List<CrashHistoryEntry>> fetchHistory() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/crash/history');
      final rows = (res.data?['history'] as List?) ?? const [];
      return rows
          .whereType<Map>()
          .map((e) => CrashHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تحميل السجل');
    }
  }

  /// Server seed, client seeds, nonce and the crash point recomputed from them.
  Future<CrashFairness> fetchFairness(int roundId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/crash/fair/$roundId');
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw CrashException(body['message']?.toString() ?? 'تعذر تحميل تفاصيل العدالة');
      }
      final round = Map<String, dynamic>.from(body['round'] as Map);
      final recomputed = Map<String, dynamic>.from(body['recomputed'] as Map);
      return CrashFairness(
        roundId: (round['roundId'] as num?)?.toInt() ?? roundId,
        nonce: (round['nonce'] as num?)?.toInt() ?? 0,
        crashPoint: (round['crashPoint'] as num?)?.toDouble() ?? 1.0,
        serverSeed: round['serverSeed']?.toString() ?? '',
        serverSeedHash: round['serverSeedHash']?.toString() ?? '',
        clientSeeds: ((round['clientSeeds'] as List?) ?? const []).map((e) => e.toString()).toList(),
        hash: recomputed['hash']?.toString() ?? '',
        recomputedCrashPoint: (recomputed['crashPoint'] as num?)?.toDouble() ?? 1.0,
        verified: body['verified'] == true,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تحميل تفاصيل العدالة');
    }
  }

  Future<String> setClientSeed(String seed) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/crash/seed',
        data: {'clientSeed': seed},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw CrashException(body['message']?.toString() ?? 'تعذر تغيير البذرة');
      }
      return body['clientSeed']?.toString() ?? seed;
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تغيير البذرة');
    }
  }

  Future<CrashStats> fetchStats() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/crash/stats');
      final body = res.data ?? const {};
      final stats = Map<String, dynamic>.from((body['stats'] as Map?) ?? const {});
      final bets = (body['bets'] as List?) ?? const [];
      return CrashStats(
        rounds: (stats['rounds'] as num?)?.toInt() ?? 0,
        wagered: (stats['wagered'] as num?)?.toInt() ?? 0,
        won: (stats['won'] as num?)?.toInt() ?? 0,
        net: (stats['net'] as num?)?.toInt() ?? 0,
        wins: (stats['wins'] as num?)?.toInt() ?? 0,
        losses: (stats['losses'] as num?)?.toInt() ?? 0,
        bestMultiplier: (stats['bestMultiplier'] as num?)?.toDouble() ?? 0,
        bestPayout: (stats['bestPayout'] as num?)?.toInt() ?? 0,
        averageRoundMultiplier: (stats['averageRoundMultiplier'] as num?)?.toDouble() ?? 0,
        bets: bets
            .whereType<Map>()
            .map((e) => CrashOwnBet.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر تحميل الإحصائيات');
    }
  }

  Future<void> sendChat(String text) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/crash/chat',
        data: {'text': text},
      );
      if ((res.data ?? const {})['success'] != true) {
        throw CrashException('تعذر إرسال الرسالة');
      }
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر إرسال الرسالة');
    }
  }

  Future<CrashRainClaim> claimRain() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('games/crash/rain/claim');
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw CrashException(body['message']?.toString() ?? 'تعذر استلام المطر');
      }
      return CrashRainClaim(
        amount: (body['amount'] as num?)?.toInt() ?? 0,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback: 'تعذر استلام المطر');
    }
  }

  CrashException _translate(DioException e, {required String fallback}) {
    final data = e.response?.data;
    String? code;
    String? serverMessage;
    if (data is Map) {
      code = data['code']?.toString();
      serverMessage = data['message']?.toString();
    }
    return CrashException(serverMessage ?? fallback, code: code);
  }
}

class CrashStateSnapshot {
  final CrashState? state;
  final String? clientSeed;
  final int minBet;
  final int maxBet;
  const CrashStateSnapshot({
    required this.state,
    required this.clientSeed,
    required this.minBet,
    required this.maxBet,
  });
}

/// A live round as broadcast on `crash_state`.
class CrashState {
  final int roundId;
  final int nonce;
  final String phase; // betting | flying | crashed
  final String serverSeedHash;
  final String? serverSeed; // revealed only after the crash
  final double? crashPoint; // known only after the crash
  final int msLeft;
  final int elapsedMs;
  final int minBet;
  final int maxBet;
  final int slots;
  final List<CrashBet> bets;
  final List<CrashHistoryTick> history;
  final CrashRain? rain;

  const CrashState({
    required this.roundId,
    required this.nonce,
    required this.phase,
    required this.serverSeedHash,
    required this.serverSeed,
    required this.crashPoint,
    required this.msLeft,
    required this.elapsedMs,
    required this.minBet,
    required this.maxBet,
    required this.slots,
    required this.bets,
    required this.history,
    required this.rain,
  });

  bool get isBetting => phase == 'betting';
  bool get isFlying => phase == 'flying';
  bool get isCrashed => phase == 'crashed';

  factory CrashState.fromJson(Map<String, dynamic> json) {
    final bets = (json['bets'] as List?) ?? const [];
    final history = (json['history'] as List?) ?? const [];
    final rain = json['rain'];
    return CrashState(
      roundId: (json['roundId'] as num?)?.toInt() ?? 0,
      nonce: (json['nonce'] as num?)?.toInt() ?? 0,
      phase: json['phase']?.toString() ?? 'betting',
      serverSeedHash: json['serverSeedHash']?.toString() ?? '',
      serverSeed: json['serverSeed']?.toString(),
      crashPoint: (json['crashPoint'] as num?)?.toDouble(),
      msLeft: (json['msLeft'] as num?)?.toInt() ?? 0,
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      minBet: (json['minBet'] as num?)?.toInt() ?? 100,
      maxBet: (json['maxBet'] as num?)?.toInt() ?? 500000,
      slots: (json['slots'] as num?)?.toInt() ?? 2,
      bets: bets
          .whereType<Map>()
          .map((e) => CrashBet.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      history: history
          .whereType<Map>()
          .map((e) => CrashHistoryTick(
                roundId: (e['roundId'] as num?)?.toInt() ?? 0,
                crashPoint: (e['crashPoint'] as num?)?.toDouble() ?? 1.0,
              ))
          .toList(),
      rain: rain is Map ? CrashRain.fromJson(Map<String, dynamic>.from(rain)) : null,
    );
  }
}

/// One row in the live-bets sidebar.
class CrashBet {
  final String betId;
  final int userId;
  final String name;
  final String? avatarUrl;
  final int slot;
  final int amount;
  final double? autoCashOut;
  final double? cashOutMultiplier;
  final int payout;
  final String status; // pending | win | loss | cancelled

  const CrashBet({
    required this.betId,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.slot,
    required this.amount,
    required this.autoCashOut,
    required this.cashOutMultiplier,
    required this.payout,
    required this.status,
  });

  bool get isWin => status == 'win';
  bool get isLoss => status == 'loss';

  factory CrashBet.fromJson(Map<String, dynamic> json) => CrashBet(
        betId: json['betId']?.toString() ?? '',
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        slot: (json['slot'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        autoCashOut: (json['autoCashOut'] as num?)?.toDouble(),
        cashOutMultiplier: (json['cashOutMultiplier'] as num?)?.toDouble(),
        payout: (json['payout'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? 'pending',
      );
}

class CrashHistoryTick {
  final int roundId;
  final double crashPoint;
  const CrashHistoryTick({required this.roundId, required this.crashPoint});
}

class CrashHistoryEntry {
  final int roundId;
  final int nonce;
  final double crashPoint;
  final String serverSeed;
  final String serverSeedHash;
  const CrashHistoryEntry({
    required this.roundId,
    required this.nonce,
    required this.crashPoint,
    required this.serverSeed,
    required this.serverSeedHash,
  });

  factory CrashHistoryEntry.fromJson(Map<String, dynamic> json) => CrashHistoryEntry(
        roundId: (json['roundId'] as num?)?.toInt() ?? 0,
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
        crashPoint: (json['crashPoint'] as num?)?.toDouble() ?? 1.0,
        serverSeed: json['serverSeed']?.toString() ?? '',
        serverSeedHash: json['serverSeedHash']?.toString() ?? '',
      );
}

class CrashFairness {
  final int roundId;
  final int nonce;
  final double crashPoint;
  final String serverSeed;
  final String serverSeedHash;
  final List<String> clientSeeds;
  final String hash;
  final double recomputedCrashPoint;
  final bool verified;

  const CrashFairness({
    required this.roundId,
    required this.nonce,
    required this.crashPoint,
    required this.serverSeed,
    required this.serverSeedHash,
    required this.clientSeeds,
    required this.hash,
    required this.recomputedCrashPoint,
    required this.verified,
  });
}

class CrashRain {
  final String id;
  final int amount;
  final int claimsLeft;
  final int expiresAt;
  const CrashRain({
    required this.id,
    required this.amount,
    required this.claimsLeft,
    required this.expiresAt,
  });

  factory CrashRain.fromJson(Map<String, dynamic> json) => CrashRain(
        id: json['id']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        claimsLeft: (json['claimsLeft'] as num?)?.toInt() ?? 0,
        expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
      );
}

class CrashChatMessage {
  final String id;
  final int userId;
  final String name;
  final String? avatarUrl;
  final String text;
  final int at;

  const CrashChatMessage({
    required this.id,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.text,
    required this.at,
  });

  factory CrashChatMessage.fromJson(Map<String, dynamic> json) => CrashChatMessage(
        id: json['id']?.toString() ?? '',
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        text: json['text']?.toString() ?? '',
        at: (json['at'] as num?)?.toInt() ?? 0,
      );
}

class CrashOwnBet {
  final String betId;
  final int amount;
  final double? cashOutMultiplier;
  final int payout;
  final String status;
  final int betTime;

  const CrashOwnBet({
    required this.betId,
    required this.amount,
    required this.cashOutMultiplier,
    required this.payout,
    required this.status,
    required this.betTime,
  });

  factory CrashOwnBet.fromJson(Map<String, dynamic> json) => CrashOwnBet(
        betId: json['betId']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        cashOutMultiplier: (json['cashOutMultiplier'] as num?)?.toDouble(),
        payout: (json['payout'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? 'loss',
        betTime: (json['betTime'] as num?)?.toInt() ?? 0,
      );
}

class CrashStats {
  final int rounds, wagered, won, net, wins, losses, bestPayout;
  final double bestMultiplier, averageRoundMultiplier;
  final List<CrashOwnBet> bets;

  const CrashStats({
    required this.rounds,
    required this.wagered,
    required this.won,
    required this.net,
    required this.wins,
    required this.losses,
    required this.bestMultiplier,
    required this.bestPayout,
    required this.averageRoundMultiplier,
    required this.bets,
  });
}

class CrashBetResult {
  final int roundId;
  final int balance;
  final String serverSeedHash;
  final String clientSeed;
  const CrashBetResult({
    required this.roundId,
    required this.balance,
    required this.serverSeedHash,
    required this.clientSeed,
  });
}

class CrashCashOutResult {
  final double multiplier;
  final int payout;
  final int balance;
  const CrashCashOutResult({
    required this.multiplier,
    required this.payout,
    required this.balance,
  });
}

class CrashRainClaim {
  final int amount;
  final int balance;
  const CrashRainClaim({required this.amount, required this.balance});
}

class CrashException implements Exception {
  final String message;
  final String? code;
  CrashException(this.message, {this.code});
  @override
  String toString() => 'CrashException(${code ?? '?'}: $message)';
}

import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the بلينكو (Plinko) endpoints.
///
/// The server owns the multiplier tables, the RNG, the ball path and every
/// payout — see backend/src/services/plinko.service.ts. This client only
/// animates a drop the server has already settled.
class PlinkoRepository {
  PlinkoRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<PlinkoState> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/plinko/state');
      final body = res.data ?? const {};
      return PlinkoState(
        layout: PlinkoLayout.fromJson(
            Map<String, dynamic>.from(body['layout'] as Map? ?? const {})),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        history: ((body['history'] as List?) ?? const [])
            .map(
                (e) => PlinkoDrop.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fairness: PlinkoFairness.fromJson(
          Map<String, dynamic>.from(body['fairness'] as Map? ?? const {}),
        ),
      );
    } on DioException catch (e) {
      throw _translate(e, 'تعذر تحميل اللعبة');
    }
  }

  Future<PlinkoDropResult> drop({
    required String risk,
    required int rows,
    required int amount,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/plinko/drop',
        data: {'risk': risk, 'rows': rows, 'amount': amount},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw PlinkoException(
            body['message']?.toString() ?? 'تعذر إسقاط الكرة');
      }
      return PlinkoDropResult(
        drop:
            PlinkoDrop.fromJson(Map<String, dynamic>.from(body['drop'] as Map)),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, 'تعذر إسقاط الكرة');
    }
  }

  Future<PlinkoFairness> setClientSeed(String seed) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/plinko/seed',
        data: {'clientSeed': seed},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw PlinkoException(
            body['message']?.toString() ?? 'تعذر تغيير البذرة');
      }
      return PlinkoFairness.fromJson(
          Map<String, dynamic>.from(body['fairness'] as Map));
    } on DioException catch (e) {
      throw _translate(e, 'تعذر تغيير البذرة');
    }
  }

  PlinkoException _translate(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return PlinkoException(data['message'].toString());
    }
    return PlinkoException(fallback);
  }
}

class PlinkoException implements Exception {
  PlinkoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PlinkoLayout {
  const PlinkoLayout({
    required this.minRows,
    required this.maxRows,
    required this.minBet,
    required this.maxBet,
    required this.tables,
  });

  final int minRows, maxRows, minBet, maxBet;

  /// risk → row count → multipliers, left slot to right slot.
  final Map<String, Map<int, List<double>>> tables;

  static const _fallbackRow = <double>[
    16,
    9,
    2,
    1.4,
    1.4,
    1.2,
    1.1,
    1,
    0.5,
    1,
    1.1,
    1.2,
    1.4,
    1.4,
    2,
    9,
    16,
  ];

  factory PlinkoLayout.fromJson(Map<String, dynamic> json) {
    final tables = <String, Map<int, List<double>>>{};
    final raw = json['tables'];
    if (raw is Map) {
      raw.forEach((risk, byRows) {
        if (byRows is! Map) return;
        final rows = <int, List<double>>{};
        byRows.forEach((rowCount, multipliers) {
          final n = int.tryParse(rowCount.toString());
          if (n == null || multipliers is! List) return;
          rows[n] = multipliers.map((m) => (m as num).toDouble()).toList();
        });
        tables[risk.toString()] = rows;
      });
    }
    return PlinkoLayout(
      minRows: (json['minRows'] as num?)?.toInt() ?? 8,
      maxRows: (json['maxRows'] as num?)?.toInt() ?? 16,
      minBet: (json['minBet'] as num?)?.toInt() ?? 10,
      maxBet: (json['maxBet'] as num?)?.toInt() ?? 50000,
      tables: tables,
    );
  }

  /// Falls back to the 16-row medium row so the board can always draw, even if
  /// the state call has not landed yet.
  List<double> multipliers(String risk, int rows) =>
      tables[risk]?[rows] ?? _fallbackRow;
}

class PlinkoFairness {
  const PlinkoFairness({
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
  });

  final String serverSeedHash, clientSeed;
  final int nonce;

  factory PlinkoFairness.fromJson(Map<String, dynamic> json) => PlinkoFairness(
        serverSeedHash: json['serverSeedHash']?.toString() ?? '',
        clientSeed: json['clientSeed']?.toString() ?? '',
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
      );
}

class PlinkoDrop {
  const PlinkoDrop({
    required this.nonce,
    required this.risk,
    required this.rows,
    required this.slot,
    required this.multiplier,
    required this.bet,
    required this.payout,
    required this.directions,
  });

  final int nonce, rows, slot, bet, payout;
  final String risk;
  final double multiplier;

  /// 0 = bounced left at that peg, 1 = bounced right. Empty for history rows,
  /// which only carry the settled outcome.
  final List<int> directions;

  factory PlinkoDrop.fromJson(Map<String, dynamic> json) => PlinkoDrop(
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
        risk: json['risk']?.toString() ?? 'medium',
        rows: (json['rows'] as num?)?.toInt() ?? 16,
        slot: (json['slot'] as num?)?.toInt() ?? 0,
        multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0,
        bet: (json['bet'] as num?)?.toInt() ?? 0,
        payout: (json['payout'] as num?)?.toInt() ?? 0,
        directions: ((json['directions'] as List?) ?? const [])
            .map((d) => (d as num).toInt())
            .toList(),
      );
}

class PlinkoDropResult {
  const PlinkoDropResult({required this.drop, required this.balance});
  final PlinkoDrop drop;
  final int balance;
}

class PlinkoState {
  const PlinkoState({
    required this.layout,
    required this.balance,
    required this.history,
    required this.fairness,
  });

  final PlinkoLayout layout;
  final int balance;
  final List<PlinkoDrop> history;
  final PlinkoFairness fairness;
}

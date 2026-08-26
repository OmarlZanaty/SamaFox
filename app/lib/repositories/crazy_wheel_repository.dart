import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the عجلة الحظ (Crazy Wheel) endpoints.
///
/// The server owns the wheel layout, the RNG, the top slot, every bonus-game
/// outcome and every payout — see backend/src/services/crazyWheel.service.ts.
/// This client only renders what the server already decided.
class CrazyWheelRepository {
  CrazyWheelRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<CrazyStateResponse> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/crazy/state');
      final body = res.data ?? const {};
      final raw = body['state'];
      return CrazyStateResponse(
        state: raw is Map ? CrazyState.fromJson(Map<String, dynamic>.from(raw)) : null,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        layout: body['layout'] is Map
            ? CrazyLayout.fromJson(Map<String, dynamic>.from(body['layout'] as Map))
            : null,
      );
    } on DioException catch (e) {
      throw _translate(e, 'تعذر تحميل الجولة');
    }
  }

  Future<CrazyBetResult> placeBet({required String segment, required int amount}) =>
      _betCall('games/crazy/bet', {'segment': segment, 'amount': amount}, 'تعذر وضع الرهان');

  Future<CrazyBetResult> clearBets() =>
      _betCall('games/crazy/clear', const {}, 'تعذر مسح الرهانات');

  Future<CrazyBetResult> repeatBets() =>
      _betCall('games/crazy/repeat', const {}, 'تعذر تكرار الرهان');

  /// Cash Hunt tile index (int) or Crazy Time flapper colour (String).
  Future<void> submitPick(Object pick) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('games/crazy/pick', data: {'pick': pick});
      if (res.data?['success'] != true) {
        throw CrazyWheelException(res.data?['message']?.toString() ?? 'تعذر تسجيل الاختيار');
      }
    } on DioException catch (e) {
      throw _translate(e, 'تعذر تسجيل الاختيار');
    }
  }

  Future<CrazyBetResult> _betCall(String path, Map<String, dynamic> data, String fallback) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: data);
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw CrazyWheelException(body['message']?.toString() ?? fallback);
      }
      final bets = (body['bets'] as Map?) ?? const {};
      return CrazyBetResult(
        bets: bets.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback);
    }
  }

  CrazyWheelException _translate(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      return CrazyWheelException(
        data['message']?.toString() ?? fallback,
        code: data['code']?.toString(),
      );
    }
    return CrazyWheelException(fallback);
  }
}

class CrazyStateResponse {
  final CrazyState? state;
  final int balance;
  final CrazyLayout? layout;
  const CrazyStateResponse({required this.state, required this.balance, required this.layout});
}

/// The fixed wheel layout — fetched once so the client never hard-codes an
/// order that could drift from the server's.
class CrazyLayout {
  final List<String> wheel; // 54 segment keys, in ring order
  final Map<String, int> payouts;
  final List<String> betSpots;
  final List<int> chipTiers;

  const CrazyLayout({
    required this.wheel,
    required this.payouts,
    required this.betSpots,
    required this.chipTiers,
  });

  factory CrazyLayout.fromJson(Map<String, dynamic> json) => CrazyLayout(
        wheel: ((json['wheel'] as List?) ?? const []).map((e) => e.toString()).toList(),
        payouts: ((json['payouts'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        betSpots: ((json['betSpots'] as List?) ?? const []).map((e) => e.toString()).toList(),
        chipTiers: ((json['chipTiers'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      );
}

class TopSlot {
  final String spot;
  final int multiplier;
  const TopSlot({required this.spot, required this.multiplier});

  factory TopSlot.fromJson(Map<String, dynamic> json) => TopSlot(
        spot: json['spot']?.toString() ?? '1',
        multiplier: (json['multiplier'] as num?)?.toInt() ?? 1,
      );
}

class CrazyHistoryEntry {
  final int roundId;
  final String segment;
  final int? multiplier;
  const CrazyHistoryEntry({required this.roundId, required this.segment, required this.multiplier});

  factory CrazyHistoryEntry.fromJson(Map<String, dynamic> json) => CrazyHistoryEntry(
        roundId: (json['roundId'] as num?)?.toInt() ?? 0,
        segment: json['segment']?.toString() ?? '1',
        multiplier: (json['multiplier'] as num?)?.toInt(),
      );
}

/// One live round as broadcast on `crazy_state`.
class CrazyState {
  /// betting | spinning | bonus_pick | bonus_reveal | result
  final String phase;
  final int roundId;
  final int msLeft;
  final int? resultIndex;
  final String? resultSegment;
  final TopSlot? topSlot;
  final String? bonusKind;
  final Map<String, dynamic>? bonus;
  final Map<String, int> totals;
  final Map<String, int> myBets;
  final Object? myPick;
  final int myPayout;
  final int myMultiplier;
  final int playerCount;
  final List<CrazyHistoryEntry> history;
  final List<int> chipTiers;

  const CrazyState({
    required this.phase,
    required this.roundId,
    required this.msLeft,
    required this.resultIndex,
    required this.resultSegment,
    required this.topSlot,
    required this.bonusKind,
    required this.bonus,
    required this.totals,
    required this.myBets,
    required this.myPick,
    required this.myPayout,
    required this.myMultiplier,
    required this.playerCount,
    required this.history,
    required this.chipTiers,
  });

  bool get isBetting => phase == 'betting';
  bool get isSpinning => phase == 'spinning';
  bool get isBonusPick => phase == 'bonus_pick';
  bool get isBonusReveal => phase == 'bonus_reveal';
  bool get isResult => phase == 'result';
  bool get inBonus => isBonusPick || isBonusReveal;

  factory CrazyState.fromJson(Map<String, dynamic> json) {
    final me = json['me'];
    final totalsRaw = (json['totals'] as Map?) ?? const {};
    return CrazyState(
      phase: json['phase']?.toString() ?? 'betting',
      roundId: (json['roundId'] as num?)?.toInt() ?? 0,
      msLeft: (json['msLeft'] as num?)?.toInt() ?? 0,
      resultIndex: (json['resultIndex'] as num?)?.toInt(),
      resultSegment: json['resultSegment']?.toString(),
      topSlot: json['topSlot'] is Map
          ? TopSlot.fromJson(Map<String, dynamic>.from(json['topSlot'] as Map))
          : null,
      bonusKind: json['bonusKind']?.toString(),
      bonus: json['bonus'] is Map ? Map<String, dynamic>.from(json['bonus'] as Map) : null,
      totals: totalsRaw.map(
        (k, v) => MapEntry(k.toString(), ((v as Map)['amount'] as num?)?.toInt() ?? 0),
      ),
      myBets: me is Map && me['bets'] is Map
          ? (me['bets'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : const {},
      myPick: me is Map ? me['pick'] : null,
      myPayout: me is Map ? ((me['payout'] as num?)?.toInt() ?? 0) : 0,
      myMultiplier: me is Map ? ((me['multiplier'] as num?)?.toInt() ?? 0) : 0,
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      history: ((json['history'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => CrazyHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      chipTiers: ((json['chipTiers'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
    );
  }

  /// The socket broadcast carries no `me` block (it is shared state), so keep
  /// the personal fields we already have rather than blanking the bet chips
  /// every time a round tick arrives.
  CrazyState withMineFrom(CrazyState? previous) {
    if (previous == null || previous.roundId != roundId) return this;
    if (myBets.isNotEmpty) return this;
    return CrazyState(
      phase: phase,
      roundId: roundId,
      msLeft: msLeft,
      resultIndex: resultIndex,
      resultSegment: resultSegment,
      topSlot: topSlot,
      bonusKind: bonusKind,
      bonus: bonus,
      totals: totals,
      myBets: previous.myBets,
      myPick: myPick ?? previous.myPick,
      myPayout: myPayout != 0 ? myPayout : previous.myPayout,
      myMultiplier: myMultiplier != 0 ? myMultiplier : previous.myMultiplier,
      playerCount: playerCount,
      history: history,
      chipTiers: chipTiers.isEmpty ? previous.chipTiers : chipTiers,
    );
  }
}

class CrazyBetResult {
  final Map<String, int> bets;
  final int balance;
  const CrazyBetResult({required this.bets, required this.balance});
}

class CrazyWheelException implements Exception {
  final String message;
  final String? code;
  CrazyWheelException(this.message, {this.code});
  @override
  String toString() => 'CrazyWheelException(${code ?? '?'}: $message)';
}

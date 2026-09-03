import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the القط الجشع (Greedy Cat) endpoints.
///
/// The server owns the round timer, the RNG and every payout — see
/// backend/src/services/greedyCat.service.ts. This client only renders what the
/// server already decided.
class GreedyCatRepository {
  GreedyCatRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<GreedyStateResponse> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/greedy/state');
      final body = res.data ?? const {};
      final raw = body['state'];
      return GreedyStateResponse(
        state: raw is Map
            ? GreedyState.fromJson(Map<String, dynamic>.from(raw))
            : null,
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        countryCode: body['countryCode']?.toString(),
        layout: body['layout'] is Map
            ? GreedyLayout.fromJson(
                Map<String, dynamic>.from(body['layout'] as Map))
            : null,
      );
    } on DioException catch (e) {
      throw _translate(e, 'تعذر تحميل الجولة');
    }
  }

  /// [target] is a symbol key, or `salad` / `pizza` for the category shortcut.
  Future<GreedyBetResult> placeBet({required String target, required int amount}) =>
      _betCall('games/greedy/bet', {'target': target, 'amount': amount},
          'تعذر وضع الرهان');

  Future<GreedyBetResult> clearBets() =>
      _betCall('games/greedy/clear', const {}, 'تعذر مسح الرهانات');

  Future<GreedyBetResult> repeatBets() =>
      _betCall('games/greedy/repeat', const {}, 'تعذر تكرار الرهان');

  /// [scope] is `region` or `global`.
  Future<List<GreedyRankRow>> fetchRanking(String scope) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'games/greedy/ranking',
        queryParameters: {'scope': scope},
      );
      final rows = (res.data?['ranking'] as List?) ?? const [];
      return rows
          .whereType<Map>()
          .map((e) => GreedyRankRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _translate(e, 'تعذر تحميل الترتيب');
    }
  }

  Future<GreedyBetResult> _betCall(
      String path, Map<String, dynamic> data, String fallback) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: data);
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw GreedyCatException(body['message']?.toString() ?? fallback);
      }
      final bets = (body['bets'] as Map?) ?? const {};
      final categories = (body['categories'] as Map?) ?? const {};
      return GreedyBetResult(
        bets: bets.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        categories: categories
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translate(e, fallback);
    }
  }

  GreedyCatException _translate(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      return GreedyCatException(
        data['message']?.toString() ?? fallback,
        code: data['code']?.toString(),
      );
    }
    return GreedyCatException(fallback);
  }
}

class GreedyStateResponse {
  final GreedyState? state;
  final int balance;
  final String? countryCode;
  final GreedyLayout? layout;
  const GreedyStateResponse({
    required this.state,
    required this.balance,
    required this.countryCode,
    required this.layout,
  });
}

/// One food card. Ring order is clockwise from 12 o'clock, and the client draws
/// the wheel in exactly the order the server sends.
class GreedySymbol {
  final String key;
  final String category; // salad | pizza
  final int multiplier;
  final int weight;
  final String nameAr;

  const GreedySymbol({
    required this.key,
    required this.category,
    required this.multiplier,
    required this.weight,
    required this.nameAr,
  });

  factory GreedySymbol.fromJson(Map<String, dynamic> json) => GreedySymbol(
        key: json['key']?.toString() ?? 'corn',
        category: json['category']?.toString() ?? 'salad',
        multiplier: (json['multiplier'] as num?)?.toInt() ?? 5,
        weight: (json['weight'] as num?)?.toInt() ?? 90,
        nameAr: json['nameAr']?.toString() ?? '',
      );
}

/// The fixed table — fetched once so the client never hard-codes a payout that
/// could drift from the server's.
class GreedyLayout {
  final List<GreedySymbol> symbols;
  final Map<String, List<String>> categories;
  final int categorySplit;
  final List<int> denominations;
  final int minBet;
  final double rtp;
  final List<int> jackpotMilestones;

  const GreedyLayout({
    required this.symbols,
    required this.categories,
    required this.categorySplit,
    required this.denominations,
    required this.minBet,
    required this.rtp,
    required this.jackpotMilestones,
  });

  factory GreedyLayout.fromJson(Map<String, dynamic> json) => GreedyLayout(
        symbols: ((json['symbols'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => GreedySymbol.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        categories: ((json['categories'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(
            k.toString(),
            ((v as List?) ?? const []).map((e) => e.toString()).toList(),
          ),
        ),
        categorySplit: (json['categorySplit'] as num?)?.toInt() ?? 4,
        denominations: ((json['denominations'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        minBet: (json['minBet'] as num?)?.toInt() ?? 100,
        rtp: (json['rtp'] as num?)?.toDouble() ?? 0.9719,
        jackpotMilestones: ((json['jackpotMilestones'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );

  int multiplierOf(String key) =>
      symbols.firstWhere(
        (s) => s.key == key,
        orElse: () => const GreedySymbol(
            key: '', category: 'salad', multiplier: 0, weight: 0, nameAr: ''),
      ).multiplier;

  int indexOf(String key) => symbols.indexWhere((s) => s.key == key);
}

class GreedyHistoryEntry {
  final int roundId;
  final String symbol;
  final int multiplier;

  const GreedyHistoryEntry({
    required this.roundId,
    required this.symbol,
    required this.multiplier,
  });

  factory GreedyHistoryEntry.fromJson(Map<String, dynamic> json) =>
      GreedyHistoryEntry(
        roundId: (json['roundId'] as num?)?.toInt() ?? 0,
        symbol: json['symbol']?.toString() ?? 'corn',
        multiplier: (json['multiplier'] as num?)?.toInt() ?? 0,
      );
}

class GreedyJackpot {
  final int pot;
  final List<int> milestones;
  final int reached;

  const GreedyJackpot({
    required this.pot,
    required this.milestones,
    required this.reached,
  });

  factory GreedyJackpot.fromJson(Map<String, dynamic> json) => GreedyJackpot(
        pot: (json['pot'] as num?)?.toInt() ?? 0,
        milestones: ((json['milestones'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        reached: (json['reached'] as num?)?.toInt() ?? 0,
      );

  static const empty =
      GreedyJackpot(pot: 0, milestones: <int>[], reached: 0);

  /// Fill toward the next unreached milestone, 0..1. Full once they are all in.
  double get progress {
    if (reached >= milestones.length) return 1;
    final next = milestones[reached];
    if (next <= 0) return 0;
    final floor = reached == 0 ? 0 : milestones[reached - 1];
    final span = next - floor;
    if (span <= 0) return 0;
    return ((pot - floor) / span).clamp(0.0, 1.0);
  }

  int? get nextMilestone =>
      reached >= milestones.length ? null : milestones[reached];
}

class GreedyRankRow {
  final int rank;
  final int userId;
  final String name;
  final String? avatarUrl;
  final int score;

  const GreedyRankRow({
    required this.rank,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.score,
  });

  factory GreedyRankRow.fromJson(Map<String, dynamic> json) => GreedyRankRow(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? 'لاعب',
        avatarUrl: json['avatarUrl']?.toString(),
        score: (json['score'] as num?)?.toInt() ?? 0,
      );
}

/// One live round as broadcast on `greedy_state`.
class GreedyState {
  /// betting | closing | spinning | result
  final String phase;
  final int roundId;
  final int msLeft;
  final int? resultIndex;
  final String? resultSymbol;
  final Map<String, int> totals;
  final String? hot;
  final int playerCount;
  final GreedyJackpot jackpot;
  final Map<String, int> myBets;
  final Map<String, int> myCategories;
  final int myStaked;
  final int myPayout;
  final int myMultiplier;
  final int todayNet;
  final int todayBest;
  final List<GreedyHistoryEntry> history;

  const GreedyState({
    required this.phase,
    required this.roundId,
    required this.msLeft,
    required this.resultIndex,
    required this.resultSymbol,
    required this.totals,
    required this.hot,
    required this.playerCount,
    required this.jackpot,
    required this.myBets,
    required this.myCategories,
    required this.myStaked,
    required this.myPayout,
    required this.myMultiplier,
    required this.todayNet,
    required this.todayBest,
    required this.history,
  });

  bool get isBetting => phase == 'betting';
  bool get isClosing => phase == 'closing';
  bool get isSpinning => phase == 'spinning';
  bool get isResult => phase == 'result';

  /// Cards and denominations only accept taps during the betting window.
  bool get acceptsBets => isBetting;

  /// Net for the round: what came back minus everything staked into it.
  int get myNet => myPayout - myStaked;

  factory GreedyState.fromJson(Map<String, dynamic> json) {
    final me = json['me'];
    final today = json['today'];
    final totalsRaw = (json['totals'] as Map?) ?? const {};
    return GreedyState(
      phase: json['phase']?.toString() ?? 'betting',
      roundId: (json['roundId'] as num?)?.toInt() ?? 0,
      msLeft: (json['msLeft'] as num?)?.toInt() ?? 0,
      resultIndex: (json['resultIndex'] as num?)?.toInt(),
      resultSymbol: json['resultSymbol']?.toString(),
      totals: totalsRaw.map(
        (k, v) => MapEntry(k.toString(), ((v as Map)['amount'] as num?)?.toInt() ?? 0),
      ),
      hot: json['hot']?.toString(),
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      jackpot: json['jackpot'] is Map
          ? GreedyJackpot.fromJson(
              Map<String, dynamic>.from(json['jackpot'] as Map))
          : GreedyJackpot.empty,
      myBets: me is Map && me['bets'] is Map
          ? (me['bets'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : const {},
      myCategories: me is Map && me['categories'] is Map
          ? (me['categories'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : const {},
      myStaked: me is Map ? ((me['staked'] as num?)?.toInt() ?? 0) : 0,
      myPayout: me is Map ? ((me['payout'] as num?)?.toInt() ?? 0) : 0,
      myMultiplier: me is Map ? ((me['multiplier'] as num?)?.toInt() ?? 0) : 0,
      todayNet: today is Map ? ((today['net'] as num?)?.toInt() ?? 0) : 0,
      todayBest: today is Map ? ((today['best'] as num?)?.toInt() ?? 0) : 0,
      history: ((json['history'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => GreedyHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// The socket broadcast carries no `me` block (it is shared state), so keep
  /// the personal fields we already have rather than blanking the bet badges
  /// every time a round tick arrives.
  GreedyState withMineFrom(GreedyState? previous) {
    if (previous == null || previous.roundId != roundId) return this;
    if (myBets.isNotEmpty) return this;
    return copyWith(
      bets: previous.myBets,
      categories: previous.myCategories,
      staked: previous.myStaked,
      payout: myPayout != 0 ? myPayout : previous.myPayout,
      multiplier: myMultiplier != 0 ? myMultiplier : previous.myMultiplier,
      todayNet: todayNet != 0 ? todayNet : previous.todayNet,
      todayBest: todayBest != 0 ? todayBest : previous.todayBest,
    );
  }

  GreedyState copyWith({
    Map<String, int>? bets,
    Map<String, int>? categories,
    int? staked,
    int? payout,
    int? multiplier,
    int? todayNet,
    int? todayBest,
  }) =>
      GreedyState(
        phase: phase,
        roundId: roundId,
        msLeft: msLeft,
        resultIndex: resultIndex,
        resultSymbol: resultSymbol,
        totals: totals,
        hot: hot,
        playerCount: playerCount,
        jackpot: jackpot,
        myBets: bets ?? myBets,
        myCategories: categories ?? myCategories,
        myStaked: staked ?? myStaked,
        myPayout: payout ?? myPayout,
        myMultiplier: multiplier ?? myMultiplier,
        todayNet: todayNet ?? this.todayNet,
        todayBest: todayBest ?? this.todayBest,
        history: history,
      );
}

class GreedyBetResult {
  final Map<String, int> bets;
  final Map<String, int> categories;
  final int balance;
  const GreedyBetResult({
    required this.bets,
    required this.categories,
    required this.balance,
  });
}

class GreedyCatException implements Exception {
  final String message;
  final String? code;
  GreedyCatException(this.message, {this.code});
  @override
  String toString() => 'GreedyCatException(${code ?? '?'}: $message)';
}

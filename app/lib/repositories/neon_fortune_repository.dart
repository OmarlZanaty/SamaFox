import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the نيون فورتشن (Neon Fortune: Tiger City) endpoints.
///
/// The server owns the reel weights, the paytable, the RNG, the free-spin round,
/// the vault bonus and the jackpot pools — see
/// backend/src/services/neonFortune.service.ts. This client only replays a spin
/// the server has already fully resolved.
class NeonFortuneRepository {
  NeonFortuneRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<NeonState> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/neon/state');
      final body = res.data ?? const {};
      return NeonState(
        layout: NeonLayout.fromJson(Map<String, dynamic>.from(body['layout'] as Map? ?? const {})),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        jackpots: _jackpots(body['jackpots']),
        history: ((body['history'] as List?) ?? const [])
            .map((e) => NeonSpinRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        feed: ((body['feed'] as List?) ?? const [])
            .map((e) => NeonFeedEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fairness: NeonFairness.fromJson(
          Map<String, dynamic>.from(body['fairness'] as Map? ?? const {}),
        ),
      );
    } on DioException catch (e) {
      throw NeonFortuneException(_message(e, 'تعذر تحميل اللعبة'));
    }
  }

  Future<NeonSpinResponse> spin({required int amount}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/neon/spin',
        data: {'amount': amount},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw NeonFortuneException(body['message']?.toString() ?? 'تعذر تنفيذ الجولة');
      }
      return NeonSpinResponse(
        spin: NeonSpin.fromJson(Map<String, dynamic>.from(body['spin'] as Map)),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        jackpots: _jackpots(body['jackpots']),
      );
    } on DioException catch (e) {
      throw NeonFortuneException(_message(e, 'تعذر تنفيذ الجولة'));
    }
  }

  /// Live pool values between spins, so the meters keep climbing while the
  /// player watches other people play.
  Future<NeonJackpotPoll> fetchJackpots() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/neon/jackpots');
      final body = res.data ?? const {};
      return NeonJackpotPoll(
        jackpots: _jackpots(body['jackpots']),
        feed: ((body['feed'] as List?) ?? const [])
            .map((e) => NeonFeedEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } on DioException catch (e) {
      throw NeonFortuneException(_message(e, 'تعذر تحديث الجوائز'));
    }
  }

  Future<NeonFairness> setClientSeed(String seed) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/neon/seed',
        data: {'clientSeed': seed},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw NeonFortuneException(body['message']?.toString() ?? 'تعذر تغيير البذرة');
      }
      return NeonFairness.fromJson(Map<String, dynamic>.from(body['fairness'] as Map));
    } on DioException catch (e) {
      throw NeonFortuneException(_message(e, 'تعذر تغيير البذرة'));
    }
  }

  Map<String, int> _jackpots(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map? ?? const {});
    return map.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
  }

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    return fallback;
  }
}

class NeonFortuneException implements Exception {
  NeonFortuneException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Layout ───────────────────────────────────────────────────────────────────

class NeonLayout {
  const NeonLayout({
    required this.reels,
    required this.rows,
    required this.lines,
    required this.paylines,
    required this.minBet,
    required this.maxBet,
    required this.betSteps,
    required this.paytable,
    required this.paySymbols,
    required this.scatterTrigger,
    required this.freeSpinsAwarded,
    required this.freeSpinsRetrigger,
    required this.freeSpinsCap,
    required this.wildMultipliers,
    required this.tokenTrigger,
    required this.vaultCapsules,
    required this.vaultMatch,
    required this.vaultConsolationMult,
    required this.jackpotTiers,
    required this.contributionRate,
    required this.tierThresholds,
  });

  final int reels, rows, lines;

  /// Row index per reel for each of the 20 paylines.
  final List<List<int>> paylines;
  final int minBet, maxBet;
  final List<int> betSteps;

  /// symbol id → [3, 4, 5] of a kind, as a multiple of the TOTAL bet.
  final Map<String, List<double>> paytable;
  final List<String> paySymbols;

  final int scatterTrigger, freeSpinsAwarded, freeSpinsRetrigger, freeSpinsCap;
  final List<int> wildMultipliers;
  final int tokenTrigger, vaultCapsules, vaultMatch, vaultConsolationMult;
  final List<String> jackpotTiers;
  final Map<String, double> contributionRate;
  final Map<String, num> tierThresholds;

  static NeonLayout fromJson(Map<String, dynamic> j) => NeonLayout(
        reels: (j['reels'] as num?)?.toInt() ?? 5,
        rows: (j['rows'] as num?)?.toInt() ?? 3,
        lines: (j['lines'] as num?)?.toInt() ?? 20,
        paylines: ((j['paylines'] as List?) ?? const [])
            .map((e) => (e as List).map((v) => (v as num).toInt()).toList())
            .toList(),
        minBet: (j['minBet'] as num?)?.toInt() ?? 50,
        maxBet: (j['maxBet'] as num?)?.toInt() ?? 20000,
        betSteps: ((j['betSteps'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        paytable: Map<String, dynamic>.from(j['paytable'] as Map? ?? const {}).map(
          (k, v) => MapEntry(k, (v as List).map((e) => (e as num).toDouble()).toList()),
        ),
        paySymbols: ((j['paySymbols'] as List?) ?? const []).map((e) => e.toString()).toList(),
        scatterTrigger: (j['scatterTrigger'] as num?)?.toInt() ?? 3,
        freeSpinsAwarded: (j['freeSpinsAwarded'] as num?)?.toInt() ?? 10,
        freeSpinsRetrigger: (j['freeSpinsRetrigger'] as num?)?.toInt() ?? 2,
        freeSpinsCap: (j['freeSpinsCap'] as num?)?.toInt() ?? 30,
        wildMultipliers:
            ((j['wildMultipliers'] as List?) ?? const [2, 3]).map((e) => (e as num).toInt()).toList(),
        tokenTrigger: (j['tokenTrigger'] as num?)?.toInt() ?? 3,
        vaultCapsules: (j['vaultCapsules'] as num?)?.toInt() ?? 9,
        vaultMatch: (j['vaultMatch'] as num?)?.toInt() ?? 3,
        vaultConsolationMult: (j['vaultConsolationMult'] as num?)?.toInt() ?? 4,
        jackpotTiers: ((j['jackpotTiers'] as List?) ?? const []).map((e) => e.toString()).toList(),
        contributionRate: Map<String, dynamic>.from(j['contributionRate'] as Map? ?? const {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        tierThresholds: Map<String, dynamic>.from(j['tierThresholds'] as Map? ?? const {})
            .map((k, v) => MapEntry(k, v as num)),
      );
}

// ── Spin result ──────────────────────────────────────────────────────────────

class NeonLineWin {
  const NeonLineWin({
    required this.line,
    required this.symbol,
    required this.count,
    required this.cells,
    required this.multiplier,
    required this.amount,
  });

  final int line;
  final String symbol;
  final int count;
  final List<int> cells;
  final int multiplier;
  final int amount;

  static NeonLineWin fromJson(Map<String, dynamic> j) => NeonLineWin(
        line: (j['line'] as num).toInt(),
        symbol: j['symbol'].toString(),
        count: (j['count'] as num).toInt(),
        cells: ((j['cells'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        multiplier: (j['multiplier'] as num?)?.toInt() ?? 1,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
      );
}

class NeonFreeSpinFrame {
  const NeonFreeSpinFrame({
    required this.index,
    required this.grid,
    required this.wildMultipliers,
    required this.wins,
    required this.win,
    required this.scatters,
    required this.retriggered,
    required this.spinsLeftAfter,
  });

  final int index;
  final List<String> grid;
  final Map<int, int> wildMultipliers;
  final List<NeonLineWin> wins;
  final int win;
  final int scatters;
  final int retriggered;
  final int spinsLeftAfter;

  static NeonFreeSpinFrame fromJson(Map<String, dynamic> j) => NeonFreeSpinFrame(
        index: (j['index'] as num).toInt(),
        grid: ((j['grid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        wildMultipliers: Map<String, dynamic>.from(j['wildMultipliers'] as Map? ?? const {})
            .map((k, v) => MapEntry(int.parse(k), (v as num).toInt())),
        wins: ((j['wins'] as List?) ?? const [])
            .map((e) => NeonLineWin.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        win: (j['win'] as num?)?.toInt() ?? 0,
        scatters: (j['scatters'] as num?)?.toInt() ?? 0,
        retriggered: (j['retriggered'] as num?)?.toInt() ?? 0,
        spinsLeftAfter: (j['spinsLeftAfter'] as num?)?.toInt() ?? 0,
      );
}

class NeonFreeSpinRound {
  const NeonFreeSpinRound({
    required this.spinsAwarded,
    required this.spinsPlayed,
    required this.frames,
    required this.total,
    required this.bestSingle,
  });

  final int spinsAwarded, spinsPlayed;
  final List<NeonFreeSpinFrame> frames;
  final int total, bestSingle;

  static NeonFreeSpinRound fromJson(Map<String, dynamic> j) => NeonFreeSpinRound(
        spinsAwarded: (j['spinsAwarded'] as num?)?.toInt() ?? 0,
        spinsPlayed: (j['spinsPlayed'] as num?)?.toInt() ?? 0,
        frames: ((j['frames'] as List?) ?? const [])
            .map((e) => NeonFreeSpinFrame.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        bestSingle: (j['bestSingle'] as num?)?.toInt() ?? 0,
      );
}

class NeonVaultRound {
  const NeonVaultRound({
    required this.capsules,
    required this.wonTier,
    required this.amount,
    required this.consolation,
  });

  /// What each of the nine capsules holds: a tier id, or 'SPARKLE'.
  final List<String> capsules;
  final String? wonTier;
  final int amount;
  final int consolation;

  static NeonVaultRound fromJson(Map<String, dynamic> j) => NeonVaultRound(
        capsules: ((j['capsules'] as List?) ?? const []).map((e) => e.toString()).toList(),
        wonTier: j['wonTier']?.toString(),
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        consolation: (j['consolation'] as num?)?.toInt() ?? 0,
      );
}

class NeonSpin {
  const NeonSpin({
    required this.bet,
    required this.grid,
    required this.wins,
    required this.baseWin,
    required this.scatters,
    required this.scatterCells,
    required this.freeSpinsTriggered,
    required this.freeSpins,
    required this.freeSpinsWin,
    required this.tokens,
    required this.tokenCells,
    required this.vaultTriggered,
    required this.vault,
    required this.vaultWin,
    required this.grandTotal,
    required this.tier,
  });

  final int bet;

  /// Row-major, 15 cells: index = row * 5 + reel.
  final List<String> grid;
  final List<NeonLineWin> wins;
  final int baseWin;

  final int scatters;
  final List<int> scatterCells;
  final bool freeSpinsTriggered;
  final NeonFreeSpinRound? freeSpins;
  final int freeSpinsWin;

  final int tokens;
  final List<int> tokenCells;
  final bool vaultTriggered;
  final NeonVaultRound? vault;
  final int vaultWin;

  final int grandTotal;
  final String? tier;

  static NeonSpin fromJson(Map<String, dynamic> j) => NeonSpin(
        bet: (j['bet'] as num?)?.toInt() ?? 0,
        grid: ((j['grid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        wins: ((j['wins'] as List?) ?? const [])
            .map((e) => NeonLineWin.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        baseWin: (j['baseWin'] as num?)?.toInt() ?? 0,
        scatters: (j['scatters'] as num?)?.toInt() ?? 0,
        scatterCells:
            ((j['scatterCells'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        freeSpinsTriggered: j['freeSpinsTriggered'] == true,
        freeSpins: j['freeSpins'] == null
            ? null
            : NeonFreeSpinRound.fromJson(Map<String, dynamic>.from(j['freeSpins'] as Map)),
        freeSpinsWin: (j['freeSpinsWin'] as num?)?.toInt() ?? 0,
        tokens: (j['tokens'] as num?)?.toInt() ?? 0,
        tokenCells: ((j['tokenCells'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        vaultTriggered: j['vaultTriggered'] == true,
        vault: j['vault'] == null
            ? null
            : NeonVaultRound.fromJson(Map<String, dynamic>.from(j['vault'] as Map)),
        vaultWin: (j['vaultWin'] as num?)?.toInt() ?? 0,
        grandTotal: (j['grandTotal'] as num?)?.toInt() ?? 0,
        tier: j['tier']?.toString(),
      );
}

class NeonSpinResponse {
  const NeonSpinResponse({required this.spin, required this.balance, required this.jackpots});
  final NeonSpin spin;
  final int balance;
  final Map<String, int> jackpots;
}

class NeonJackpotPoll {
  const NeonJackpotPoll({required this.jackpots, required this.feed});
  final Map<String, int> jackpots;
  final List<NeonFeedEntry> feed;
}

class NeonSpinRecord {
  const NeonSpinRecord({
    required this.nonce,
    required this.bet,
    required this.grandTotal,
    required this.freeSpinsTriggered,
    required this.vaultTier,
    required this.tier,
    required this.at,
  });

  final int nonce, bet, grandTotal;
  final bool freeSpinsTriggered;
  final String? vaultTier, tier;
  final int at;

  static NeonSpinRecord fromJson(Map<String, dynamic> j) => NeonSpinRecord(
        nonce: (j['nonce'] as num?)?.toInt() ?? 0,
        bet: (j['bet'] as num?)?.toInt() ?? 0,
        grandTotal: (j['grandTotal'] as num?)?.toInt() ?? 0,
        freeSpinsTriggered: j['freeSpinsTriggered'] == true,
        vaultTier: j['vaultTier']?.toString(),
        tier: j['tier']?.toString(),
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// One real win by one real player — the feed shows nothing else (D3).
class NeonFeedEntry {
  const NeonFeedEntry({
    required this.name,
    required this.amount,
    required this.tier,
    required this.jackpot,
    required this.at,
  });

  final String name;
  final int amount;
  final String? tier, jackpot;
  final int at;

  static NeonFeedEntry fromJson(Map<String, dynamic> j) => NeonFeedEntry(
        name: j['name']?.toString() ?? 'لاعب',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        tier: j['tier']?.toString(),
        jackpot: j['jackpot']?.toString(),
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class NeonFairness {
  const NeonFairness({
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
  });

  final String serverSeedHash, clientSeed;
  final int nonce;

  static NeonFairness fromJson(Map<String, dynamic> j) => NeonFairness(
        serverSeedHash: j['serverSeedHash']?.toString() ?? '',
        clientSeed: j['clientSeed']?.toString() ?? '',
        nonce: (j['nonce'] as num?)?.toInt() ?? 0,
      );
}

class NeonState {
  const NeonState({
    required this.layout,
    required this.balance,
    required this.jackpots,
    required this.history,
    required this.feed,
    required this.fairness,
  });

  final NeonLayout layout;
  final int balance;
  final Map<String, int> jackpots;
  final List<NeonSpinRecord> history;
  final List<NeonFeedEntry> feed;
  final NeonFairness fairness;
}

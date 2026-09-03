import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the أثيرفول (Aetherfall: Vaults of the Skyfire) endpoints.
///
/// The server owns the reel weights, the paytable, the RNG and every tumble
/// and bonus payout — see backend/src/services/aetherfall.service.ts. This
/// client only replays a spin the server has already fully resolved, frame by
/// frame.
class AetherfallRepository {
  AetherfallRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<AetherfallState> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/aetherfall/state');
      final body = res.data ?? const {};
      return AetherfallState(
        layout: AetherfallLayout.fromJson(
          Map<String, dynamic>.from(body['layout'] as Map? ?? const {}),
        ),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        history: ((body['history'] as List?) ?? const [])
            .map(
              (e) => AetherfallSpinRecord.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        fairness: AetherfallFairness.fromJson(
          Map<String, dynamic>.from(body['fairness'] as Map? ?? const {}),
        ),
      );
    } on DioException catch (e) {
      throw AetherfallException(_message(e, 'تعذر تحميل اللعبة'));
    }
  }

  Future<AetherfallSpinResponse> spin({required int amount}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/aetherfall/spin',
        data: {'amount': amount},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw AetherfallException(body['message']?.toString() ?? 'تعذر تنفيذ الجولة');
      }
      return AetherfallSpinResponse(
        spin: AetherfallSpin.fromJson(
          Map<String, dynamic>.from(body['spin'] as Map),
        ),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        fairness: AetherfallFairness(
          serverSeedHash: body['serverSeedHash']?.toString() ?? '',
          clientSeed: body['clientSeed']?.toString() ?? '',
          nonce: ((body['nonce'] as num?)?.toInt() ?? 0) + 1,
        ),
      );
    } on DioException catch (e) {
      throw AetherfallException(_message(e, 'تعذر تنفيذ الجولة'));
    }
  }

  Future<AetherfallFairness> setClientSeed(String seed) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/aetherfall/seed',
        data: {'clientSeed': seed},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw AetherfallException(body['message']?.toString() ?? 'تعذر تغيير البذرة');
      }
      return AetherfallFairness.fromJson(
        Map<String, dynamic>.from(body['fairness'] as Map),
      );
    } on DioException catch (e) {
      throw AetherfallException(_message(e, 'تعذر تغيير البذرة'));
    }
  }

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    return fallback;
  }
}

class AetherfallException implements Exception {
  AetherfallException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Layout ───────────────────────────────────────────────────────────────────

class AetherfallLayout {
  const AetherfallLayout({
    required this.cols,
    required this.rows,
    required this.minMatch,
    required this.minBet,
    required this.maxBet,
    required this.paytable,
    required this.chargeValues,
    required this.vaultKeyTrigger,
    required this.vaultBonusStartTumbles,
    required this.vaultRetriggerKeys,
    required this.vaultRetriggerTumbles,
    required this.constellationLockTarget,
    required this.tierThresholds,
    required this.standardSymbols,
  });

  final int cols, rows, minMatch, minBet, maxBet;

  /// symbol id → [9-11, 12-14, 15+] payout as a multiple of bet.
  final Map<String, List<double>> paytable;
  final List<int> chargeValues;
  final int vaultKeyTrigger, vaultBonusStartTumbles, vaultRetriggerKeys, vaultRetriggerTumbles;
  final int constellationLockTarget;

  /// tier name → minimum win/bet ratio.
  final Map<String, int> tierThresholds;
  final List<String> standardSymbols;

  static const _fallbackSymbols = ['L1', 'L2', 'L3', 'L4', 'H1', 'H2', 'H3', 'H4'];

  factory AetherfallLayout.fromJson(Map<String, dynamic> json) {
    final paytable = <String, List<double>>{};
    final rawTable = json['paytable'];
    if (rawTable is Map) {
      rawTable.forEach((sym, values) {
        if (values is List) {
          paytable[sym.toString()] = values.map((v) => (v as num).toDouble()).toList();
        }
      });
    }
    final tiers = <String, int>{};
    final rawTiers = json['tierThresholds'];
    if (rawTiers is Map) {
      rawTiers.forEach((k, v) => tiers[k.toString()] = (v as num?)?.toInt() ?? 0);
    }
    return AetherfallLayout(
      cols: (json['cols'] as num?)?.toInt() ?? 6,
      rows: (json['rows'] as num?)?.toInt() ?? 5,
      minMatch: (json['minMatch'] as num?)?.toInt() ?? 9,
      minBet: (json['minBet'] as num?)?.toInt() ?? 20,
      maxBet: (json['maxBet'] as num?)?.toInt() ?? 20000,
      paytable: paytable,
      chargeValues: ((json['chargeValues'] as List?) ?? const [2, 3, 5, 8, 12, 20, 35, 60])
          .map((v) => (v as num).toInt())
          .toList(),
      vaultKeyTrigger: (json['vaultKeyTrigger'] as num?)?.toInt() ?? 4,
      vaultBonusStartTumbles: (json['vaultBonusStartTumbles'] as num?)?.toInt() ?? 12,
      vaultRetriggerKeys: (json['vaultRetriggerKeys'] as num?)?.toInt() ?? 3,
      vaultRetriggerTumbles: (json['vaultRetriggerTumbles'] as num?)?.toInt() ?? 3,
      constellationLockTarget: (json['constellationLockTarget'] as num?)?.toInt() ?? 3,
      tierThresholds: tiers,
      standardSymbols: ((json['standardSymbols'] as List?) ?? _fallbackSymbols)
          .map((s) => s.toString())
          .toList(),
    );
  }
}

class AetherfallFairness {
  const AetherfallFairness({
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
  });

  final String serverSeedHash, clientSeed;
  final int nonce;

  factory AetherfallFairness.fromJson(Map<String, dynamic> json) => AetherfallFairness(
        serverSeedHash: json['serverSeedHash']?.toString() ?? '',
        clientSeed: json['clientSeed']?.toString() ?? '',
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
      );
}

class AetherfallState {
  const AetherfallState({
    required this.layout,
    required this.balance,
    required this.history,
    required this.fairness,
  });

  final AetherfallLayout layout;
  final int balance;
  final List<AetherfallSpinRecord> history;
  final AetherfallFairness fairness;
}

class AetherfallSpinRecord {
  const AetherfallSpinRecord({
    required this.nonce,
    required this.bet,
    required this.grandTotal,
    required this.bonusTriggered,
    required this.tier,
    required this.at,
  });

  final int nonce, bet, grandTotal;
  final bool bonusTriggered;
  final String? tier;
  final int at;

  factory AetherfallSpinRecord.fromJson(Map<String, dynamic> json) => AetherfallSpinRecord(
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
        bet: (json['bet'] as num?)?.toInt() ?? 0,
        grandTotal: (json['grandTotal'] as num?)?.toInt() ?? 0,
        bonusTriggered: json['bonusTriggered'] == true,
        tier: json['tier']?.toString(),
        at: (json['at'] as num?)?.toInt() ?? 0,
      );
}

// ── Spin payload ─────────────────────────────────────────────────────────────

class AetherfallWinEntry {
  const AetherfallWinEntry({required this.symbol, required this.count, required this.amount});
  final String symbol;
  final int count;
  final double amount;

  factory AetherfallWinEntry.fromJson(Map<String, dynamic> json) => AetherfallWinEntry(
        symbol: json['symbol']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class AetherfallChargeCell {
  const AetherfallChargeCell({required this.index, required this.value});
  final int index;
  final int value;

  factory AetherfallChargeCell.fromJson(Map<String, dynamic> json) => AetherfallChargeCell(
        index: (json['index'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toInt() ?? 0,
      );
}

class AetherfallFrame {
  const AetherfallFrame({
    required this.phase,
    required this.grid,
    required this.wins,
    required this.winningCells,
    required this.chargeCells,
    this.tumbleNumber,
    this.tumblesLeftAfter,
    this.retriggerAdded,
    this.isStarburst = false,
    this.chargeBankAfter,
    this.locksAfter,
    this.lockedCells = const [],
  });

  final String phase; // 'base' | 'bonus'
  final List<String> grid; // 30 symbol ids
  final List<AetherfallWinEntry> wins;
  final List<int> winningCells;
  final List<AetherfallChargeCell> chargeCells;

  final int? tumbleNumber;
  final int? tumblesLeftAfter;
  final int? retriggerAdded;
  final bool isStarburst;
  final int? chargeBankAfter;
  final int? locksAfter;

  /// Bonus only: board indices currently pinned by a Constellation Lock.
  final List<int> lockedCells;

  bool get hadWin => wins.isNotEmpty;

  Set<int> get clearedCells =>
      {...winningCells, ...chargeCells.map((c) => c.index)};

  factory AetherfallFrame.fromJson(Map<String, dynamic> json) => AetherfallFrame(
        phase: json['phase']?.toString() ?? 'base',
        grid: ((json['grid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        wins: ((json['wins'] as List?) ?? const [])
            .map((e) => AetherfallWinEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        winningCells: ((json['winningCells'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        chargeCells: ((json['chargeCells'] as List?) ?? const [])
            .map((e) => AetherfallChargeCell.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        tumbleNumber: (json['tumbleNumber'] as num?)?.toInt(),
        tumblesLeftAfter: (json['tumblesLeftAfter'] as num?)?.toInt(),
        retriggerAdded: (json['retriggerAdded'] as num?)?.toInt(),
        isStarburst: json['isStarburst'] == true,
        chargeBankAfter: (json['chargeBankAfter'] as num?)?.toInt(),
        locksAfter: (json['locksAfter'] as num?)?.toInt(),
        lockedCells: ((json['lockedCells'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}

class AetherfallSpin {
  const AetherfallSpin({
    required this.bet,
    required this.initialGrid,
    required this.vaultKeysInitial,
    required this.bonusTriggered,
    required this.frames,
    required this.baseWin,
    required this.baseCharge,
    required this.baseTotal,
    required this.bonusWin,
    required this.bonusCharge,
    required this.bonusTumblesUsed,
    required this.bonusTotal,
    required this.grandTotal,
    required this.tier,
  });

  final int bet;
  final List<String> initialGrid;
  final int vaultKeysInitial;
  final bool bonusTriggered;
  final List<AetherfallFrame> frames;
  final double baseWin;
  final int baseCharge;
  final int baseTotal;
  final double bonusWin;
  final int bonusCharge;
  final int bonusTumblesUsed;
  final int bonusTotal;
  final int grandTotal;
  final String? tier;

  factory AetherfallSpin.fromJson(Map<String, dynamic> json) => AetherfallSpin(
        bet: (json['bet'] as num?)?.toInt() ?? 0,
        initialGrid: ((json['initialGrid'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        vaultKeysInitial: (json['vaultKeysInitial'] as num?)?.toInt() ?? 0,
        bonusTriggered: json['bonusTriggered'] == true,
        frames: ((json['frames'] as List?) ?? const [])
            .map((e) => AetherfallFrame.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        baseWin: (json['baseWin'] as num?)?.toDouble() ?? 0,
        baseCharge: (json['baseCharge'] as num?)?.toInt() ?? 0,
        baseTotal: (json['baseTotal'] as num?)?.toInt() ?? 0,
        bonusWin: (json['bonusWin'] as num?)?.toDouble() ?? 0,
        bonusCharge: (json['bonusCharge'] as num?)?.toInt() ?? 0,
        bonusTumblesUsed: (json['bonusTumblesUsed'] as num?)?.toInt() ?? 0,
        bonusTotal: (json['bonusTotal'] as num?)?.toInt() ?? 0,
        grandTotal: (json['grandTotal'] as num?)?.toInt() ?? 0,
        tier: json['tier']?.toString(),
      );
}

class AetherfallSpinResponse {
  const AetherfallSpinResponse({
    required this.spin,
    required this.balance,
    required this.fairness,
  });

  final AetherfallSpin spin;
  final int balance;

  /// The seed pair this spin was drawn from, so the fairness sheet can keep its
  /// nonce current without a second round trip.
  final AetherfallFairness fairness;
}

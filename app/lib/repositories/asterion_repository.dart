import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the أستيريون (Citadel of Asterion) endpoints.
///
/// The server owns the symbol weights, the paytable, the RNG, every tumble, the
/// Storm Orb values and the whole Skyfall Trials feature — see
/// backend/src/services/asterion.service.ts. This client only replays a spin the
/// server has already fully resolved, frame by frame.
class AsterionRepository {
  AsterionRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<AsterionState> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/asterion/state');
      final body = res.data ?? const {};
      return AsterionState(
        layout: AsterionLayout.fromJson(
          Map<String, dynamic>.from(body['layout'] as Map? ?? const {}),
        ),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        history: ((body['history'] as List?) ?? const [])
            .map((e) => AsterionSpinRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fairness: AsterionFairness.fromJson(
          Map<String, dynamic>.from(body['fairness'] as Map? ?? const {}),
        ),
      );
    } on DioException catch (e) {
      throw AsterionException(_message(e, 'تعذر تحميل اللعبة'));
    }
  }

  Future<AsterionSpinResponse> spin({required int amount}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/asterion/spin',
        data: {'amount': amount},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw AsterionException(body['message']?.toString() ?? 'تعذر تنفيذ الجولة');
      }
      return AsterionSpinResponse(
        spin: AsterionSpin.fromJson(Map<String, dynamic>.from(body['spin'] as Map)),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        fairness: AsterionFairness(
          serverSeedHash: body['serverSeedHash']?.toString() ?? '',
          clientSeed: body['clientSeed']?.toString() ?? '',
          nonce: ((body['nonce'] as num?)?.toInt() ?? 0) + 1,
        ),
      );
    } on DioException catch (e) {
      throw AsterionException(_message(e, 'تعذر تنفيذ الجولة'));
    }
  }

  Future<AsterionFairness> setClientSeed(String seed) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/asterion/seed',
        data: {'clientSeed': seed},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw AsterionException(body['message']?.toString() ?? 'تعذر تغيير البذرة');
      }
      return AsterionFairness.fromJson(Map<String, dynamic>.from(body['fairness'] as Map));
    } on DioException catch (e) {
      throw AsterionException(_message(e, 'تعذر تغيير البذرة'));
    }
  }

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    return fallback;
  }
}

class AsterionException implements Exception {
  AsterionException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Layout ───────────────────────────────────────────────────────────────────

class AsterionLayout {
  const AsterionLayout({
    required this.cols,
    required this.rows,
    required this.minMatch,
    required this.minBet,
    required this.maxBet,
    required this.maxWinMultiple,
    required this.paytable,
    required this.orbValues,
    required this.crestTrigger,
    required this.trialSpins,
    required this.crestRetrigger,
    required this.retriggerSpins,
    required this.tierThresholds,
    required this.standardSymbols,
  });

  final int cols, rows, minMatch, minBet, maxBet, maxWinMultiple;

  /// symbol id → [8-9, 10-11, 12+] payout as a multiple of the total bet.
  final Map<String, List<double>> paytable;
  final List<int> orbValues;
  final int crestTrigger, trialSpins, crestRetrigger, retriggerSpins;

  /// tier name → minimum win/bet ratio.
  final Map<String, int> tierThresholds;
  final List<String> standardSymbols;

  static const _fallbackSymbols = ['L1', 'L2', 'L3', 'L4', 'H1', 'H2', 'H3', 'H4'];

  factory AsterionLayout.fromJson(Map<String, dynamic> json) {
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
    return AsterionLayout(
      cols: (json['cols'] as num?)?.toInt() ?? 6,
      rows: (json['rows'] as num?)?.toInt() ?? 5,
      minMatch: (json['minMatch'] as num?)?.toInt() ?? 8,
      minBet: (json['minBet'] as num?)?.toInt() ?? 20,
      maxBet: (json['maxBet'] as num?)?.toInt() ?? 20000,
      maxWinMultiple: (json['maxWinMultiple'] as num?)?.toInt() ?? 5000,
      paytable: paytable,
      orbValues: ((json['orbValues'] as List?) ??
              const [2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 50, 100, 250])
          .map((v) => (v as num).toInt())
          .toList(),
      crestTrigger: (json['crestTrigger'] as num?)?.toInt() ?? 4,
      trialSpins: (json['trialSpins'] as num?)?.toInt() ?? 15,
      crestRetrigger: (json['crestRetrigger'] as num?)?.toInt() ?? 3,
      retriggerSpins: (json['retriggerSpins'] as num?)?.toInt() ?? 5,
      tierThresholds: tiers,
      standardSymbols:
          ((json['standardSymbols'] as List?) ?? _fallbackSymbols).map((s) => s.toString()).toList(),
    );
  }
}

class AsterionFairness {
  const AsterionFairness({
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
  });

  final String serverSeedHash, clientSeed;
  final int nonce;

  factory AsterionFairness.fromJson(Map<String, dynamic> json) => AsterionFairness(
        serverSeedHash: json['serverSeedHash']?.toString() ?? '',
        clientSeed: json['clientSeed']?.toString() ?? '',
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
      );
}

class AsterionState {
  const AsterionState({
    required this.layout,
    required this.balance,
    required this.history,
    required this.fairness,
  });

  final AsterionLayout layout;
  final int balance;
  final List<AsterionSpinRecord> history;
  final AsterionFairness fairness;
}

class AsterionSpinRecord {
  const AsterionSpinRecord({
    required this.nonce,
    required this.bet,
    required this.grandTotal,
    required this.trialTriggered,
    required this.tier,
    required this.at,
  });

  final int nonce, bet, grandTotal;
  final bool trialTriggered;
  final String? tier;
  final int at;

  factory AsterionSpinRecord.fromJson(Map<String, dynamic> json) => AsterionSpinRecord(
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
        bet: (json['bet'] as num?)?.toInt() ?? 0,
        grandTotal: (json['grandTotal'] as num?)?.toInt() ?? 0,
        trialTriggered: json['trialTriggered'] == true,
        tier: json['tier']?.toString(),
        at: (json['at'] as num?)?.toInt() ?? 0,
      );
}

// ── Spin payload ─────────────────────────────────────────────────────────────

class AsterionWinEntry {
  const AsterionWinEntry({required this.symbol, required this.count, required this.amount});
  final String symbol;
  final int count;
  final double amount;

  factory AsterionWinEntry.fromJson(Map<String, dynamic> json) => AsterionWinEntry(
        symbol: json['symbol']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class AsterionOrb {
  const AsterionOrb({required this.index, required this.value});
  final int index;
  final int value;

  factory AsterionOrb.fromJson(Map<String, dynamic> json) => AsterionOrb(
        index: (json['index'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toInt() ?? 0,
      );
}

class AsterionFrame {
  const AsterionFrame({
    required this.phase,
    required this.grid,
    required this.orbCells,
    required this.wins,
    required this.winningCells,
    this.sequenceWin,
    this.sequenceMultiplier,
    this.sequenceTotal,
    this.spinNumber,
    this.spinsLeftAfter,
    this.crestCount,
    this.retriggerAdded,
    this.trialMultiplierAfter,
  });

  final String phase; // 'base' | 'trial'
  final List<String> grid; // 30 symbol ids
  final List<AsterionOrb> orbCells;
  final List<AsterionWinEntry> wins;
  final List<int> winningCells;

  /// Present on the frame that ends a sequence — the one where nothing wins.
  final double? sequenceWin;
  final int? sequenceMultiplier;
  final int? sequenceTotal;

  /// Trial only, on the first frame of a free spin.
  final int? spinNumber;
  final int? spinsLeftAfter;
  final int? crestCount;
  final int? retriggerAdded;

  /// Trial only, on the last frame of a free spin.
  final int? trialMultiplierAfter;

  bool get hadWin => wins.isNotEmpty;
  bool get endsSequence => sequenceWin != null;

  factory AsterionFrame.fromJson(Map<String, dynamic> json) => AsterionFrame(
        phase: json['phase']?.toString() ?? 'base',
        grid: ((json['grid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        orbCells: ((json['orbCells'] as List?) ?? const [])
            .map((e) => AsterionOrb.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        wins: ((json['wins'] as List?) ?? const [])
            .map((e) => AsterionWinEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        winningCells:
            ((json['winningCells'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        sequenceWin: (json['sequenceWin'] as num?)?.toDouble(),
        sequenceMultiplier: (json['sequenceMultiplier'] as num?)?.toInt(),
        sequenceTotal: (json['sequenceTotal'] as num?)?.toInt(),
        spinNumber: (json['spinNumber'] as num?)?.toInt(),
        spinsLeftAfter: (json['spinsLeftAfter'] as num?)?.toInt(),
        crestCount: (json['crestCount'] as num?)?.toInt(),
        retriggerAdded: (json['retriggerAdded'] as num?)?.toInt(),
        trialMultiplierAfter: (json['trialMultiplierAfter'] as num?)?.toInt(),
      );
}

class AsterionSpin {
  const AsterionSpin({
    required this.bet,
    required this.initialGrid,
    required this.initialOrbs,
    required this.crestsInitial,
    required this.trialTriggered,
    required this.frames,
    required this.baseWin,
    required this.baseMultiplier,
    required this.baseTotal,
    required this.trialWin,
    required this.trialSpins,
    required this.trialRetriggers,
    required this.trialMultiplier,
    required this.trialTotal,
    required this.uncappedTotal,
    required this.capped,
    required this.grandTotal,
    required this.tier,
  });

  final int bet;
  final List<String> initialGrid;
  final List<AsterionOrb> initialOrbs;
  final int crestsInitial;
  final bool trialTriggered;
  final List<AsterionFrame> frames;

  final double baseWin;
  final int baseMultiplier;
  final int baseTotal;

  final double trialWin;
  final int trialSpins;
  final int trialRetriggers;
  final int trialMultiplier;
  final int trialTotal;

  /// What the spin paid before the platform's win ceiling, and whether it bit.
  final int uncappedTotal;
  final bool capped;
  final int grandTotal;
  final String? tier;

  factory AsterionSpin.fromJson(Map<String, dynamic> json) => AsterionSpin(
        bet: (json['bet'] as num?)?.toInt() ?? 0,
        initialGrid:
            ((json['initialGrid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        initialOrbs: ((json['initialOrbs'] as List?) ?? const [])
            .map((e) => AsterionOrb.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        crestsInitial: (json['crestsInitial'] as num?)?.toInt() ?? 0,
        trialTriggered: json['trialTriggered'] == true,
        frames: ((json['frames'] as List?) ?? const [])
            .map((e) => AsterionFrame.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        baseWin: (json['baseWin'] as num?)?.toDouble() ?? 0,
        baseMultiplier: (json['baseMultiplier'] as num?)?.toInt() ?? 0,
        baseTotal: (json['baseTotal'] as num?)?.toInt() ?? 0,
        trialWin: (json['trialWin'] as num?)?.toDouble() ?? 0,
        trialSpins: (json['trialSpins'] as num?)?.toInt() ?? 0,
        trialRetriggers: (json['trialRetriggers'] as num?)?.toInt() ?? 0,
        trialMultiplier: (json['trialMultiplier'] as num?)?.toInt() ?? 0,
        trialTotal: (json['trialTotal'] as num?)?.toInt() ?? 0,
        uncappedTotal: (json['uncappedTotal'] as num?)?.toInt() ?? 0,
        capped: json['capped'] == true,
        grandTotal: (json['grandTotal'] as num?)?.toInt() ?? 0,
        tier: json['tier']?.toString(),
      );
}

class AsterionSpinResponse {
  const AsterionSpinResponse({
    required this.spin,
    required this.balance,
    required this.fairness,
  });

  final AsterionSpin spin;
  final int balance;

  /// The seed pair this spin was drawn from, so the fairness sheet can keep its
  /// nonce current without a second round trip.
  final AsterionFairness fairness;
}

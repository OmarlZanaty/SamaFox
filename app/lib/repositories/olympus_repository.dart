import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the بوابات أوليمبوس (Gates of Olympus) endpoints.
///
/// The server owns the symbol weights, the paytable, the RNG, every tumble, the
/// lightning multipliers and the whole free-spins feature — see
/// backend/src/services/olympus.service.ts. This client only replays a spin the
/// server has already fully resolved, frame by frame. It never decides a
/// symbol, a cascade, a multiplier or a payout.
class OlympusRepository {
  OlympusRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<OlympusState> fetchState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('games/olympus/state');
      final body = res.data ?? const {};
      return OlympusState(
        layout: OlympusLayout.fromJson(
          Map<String, dynamic>.from(body['layout'] as Map? ?? const {}),
        ),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        history: ((body['history'] as List?) ?? const [])
            .map((e) => OlympusSpinRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fairness: OlympusFairness.fromJson(
          Map<String, dynamic>.from(body['fairness'] as Map? ?? const {}),
        ),
      );
    } on DioException catch (e) {
      throw OlympusException(_message(e, 'تعذر تحميل اللعبة'));
    }
  }

  Future<OlympusSpinResponse> spin({required int amount}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/olympus/spin',
        data: {'amount': amount},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw OlympusException(body['message']?.toString() ?? 'تعذر تنفيذ الجولة');
      }
      return OlympusSpinResponse(
        spin: OlympusSpin.fromJson(Map<String, dynamic>.from(body['spin'] as Map)),
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        // The nonce the server reports is the one this spin consumed, so the
        // next one is +1 — same as أثيرفول, and it keeps the fairness sheet
        // current without a second round trip.
        fairness: OlympusFairness(
          serverSeedHash: body['serverSeedHash']?.toString() ?? '',
          clientSeed: body['clientSeed']?.toString() ?? '',
          nonce: ((body['nonce'] as num?)?.toInt() ?? 0) + 1,
        ),
      );
    } on DioException catch (e) {
      throw OlympusException(_message(e, 'تعذر تنفيذ الجولة'));
    }
  }

  Future<OlympusFairness> setClientSeed(String seed) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/olympus/seed',
        data: {'clientSeed': seed},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw OlympusException(body['message']?.toString() ?? 'تعذر تغيير البذرة');
      }
      return OlympusFairness.fromJson(Map<String, dynamic>.from(body['fairness'] as Map));
    } on DioException catch (e) {
      throw OlympusException(_message(e, 'تعذر تغيير البذرة'));
    }
  }

  /// Reveals the server seed this player's spins were drawn from and commits to
  /// a fresh one, so past nonces can be recomputed and checked.
  ///
  /// The server answers `{ revealed: { serverSeed, serverSeedHash, nonce },
  /// serverSeedHash }` — the old pair nested, the new commitment at the top —
  /// and does not echo the client seed back at all. So the caller has to pass
  /// the seed it already holds; reading it off this response would blank the
  /// field the player just set.
  Future<OlympusSeedReveal> rotateServerSeed({required String clientSeed}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('games/olympus/seed/rotate');
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw OlympusException(body['message']?.toString() ?? 'تعذر تدوير البذرة');
      }
      final revealed = Map<String, dynamic>.from(body['revealed'] as Map? ?? const {});
      return OlympusSeedReveal(
        revealedServerSeed: revealed['serverSeed']?.toString() ?? '',
        fairness: OlympusFairness(
          serverSeedHash: body['serverSeedHash']?.toString() ?? '',
          clientSeed: clientSeed,
          // Rotating commits to a fresh seed, so the round counter starts over.
          nonce: 0,
        ),
      );
    } on DioException catch (e) {
      throw OlympusException(_message(e, 'تعذر تدوير البذرة'));
    }
  }

  /// Recomputes a spin from a revealed seed pair.
  ///
  /// Settles nothing and touches no balance — it runs the same pure function
  /// the live spin uses. Two callers: a player checking a past round against
  /// the seeds they were given, and the debug scenario sheet, which replays
  /// known-good nonces to exercise every branch of the animation.
  Future<OlympusSpin> verifySpin({
    required String serverSeed,
    required String clientSeed,
    required int nonce,
    required int bet,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/olympus/verify',
        data: {
          'serverSeed': serverSeed,
          'clientSeed': clientSeed,
          'nonce': nonce,
          'bet': bet,
        },
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw OlympusException(body['message']?.toString() ?? 'تعذر التحقق');
      }
      return OlympusSpin.fromJson(Map<String, dynamic>.from(body['spin'] as Map));
    } on DioException catch (e) {
      throw OlympusException(_message(e, 'تعذر التحقق'));
    }
  }

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    return fallback;
  }
}

class OlympusException implements Exception {
  OlympusException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Layout ───────────────────────────────────────────────────────────────────

/// Everything the client needs to draw the board and the paytable before the
/// first spin. Every field has a fallback matching the server's own default, so
/// a partial or older payload still renders a correct board.
class OlympusLayout {
  const OlympusLayout({
    required this.cols,
    required this.rows,
    required this.minMatch,
    required this.minBet,
    required this.maxBet,
    required this.maxWinMultiple,
    required this.paytable,
    required this.multValues,
    required this.scatterTrigger,
    required this.freeSpins,
    required this.scatterRetrigger,
    required this.retriggerSpins,
    required this.tierThresholds,
    required this.standardSymbols,
  });

  final int cols, rows, minMatch, minBet, maxBet, maxWinMultiple;

  /// symbol id → [8-9, 10-11, 12+] payout as a multiple of the total bet.
  final Map<String, List<double>> paytable;

  /// Every lightning multiplier face value the game can deal.
  final List<int> multValues;

  final int scatterTrigger, freeSpins, scatterRetrigger, retriggerSpins;

  /// tier name → minimum win/bet ratio.
  final Map<String, int> tierThresholds;

  /// Cheapest first — the paytable and the help sheet read this order.
  final List<String> standardSymbols;

  static const _fallbackSymbols = [
    'GEM_BLUE',
    'GEM_GREEN',
    'GEM_YELLOW',
    'GEM_PURPLE',
    'GEM_RED',
    'RING',
    'CHALICE',
    'HOURGLASS',
    'CROWN',
  ];

  factory OlympusLayout.fromJson(Map<String, dynamic> json) {
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
    return OlympusLayout(
      cols: (json['cols'] as num?)?.toInt() ?? 6,
      rows: (json['rows'] as num?)?.toInt() ?? 5,
      minMatch: (json['minMatch'] as num?)?.toInt() ?? 8,
      minBet: (json['minBet'] as num?)?.toInt() ?? 20,
      maxBet: (json['maxBet'] as num?)?.toInt() ?? 20000,
      maxWinMultiple: (json['maxWinMultiple'] as num?)?.toInt() ?? 5000,
      paytable: paytable,
      multValues: ((json['multValues'] as List?) ??
              const [2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 50, 100, 250, 500])
          .map((v) => (v as num).toInt())
          .toList(),
      scatterTrigger: (json['scatterTrigger'] as num?)?.toInt() ?? 4,
      freeSpins: (json['freeSpins'] as num?)?.toInt() ?? 15,
      scatterRetrigger: (json['scatterRetrigger'] as num?)?.toInt() ?? 3,
      retriggerSpins: (json['retriggerSpins'] as num?)?.toInt() ?? 5,
      tierThresholds: tiers,
      standardSymbols: ((json['standardSymbols'] as List?) ?? _fallbackSymbols)
          .map((s) => s.toString())
          .toList(),
    );
  }
}

class OlympusFairness {
  const OlympusFairness({
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
  });

  final String serverSeedHash, clientSeed;
  final int nonce;

  factory OlympusFairness.fromJson(Map<String, dynamic> json) => OlympusFairness(
        serverSeedHash: json['serverSeedHash']?.toString() ?? '',
        clientSeed: json['clientSeed']?.toString() ?? '',
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
      );
}

class OlympusSeedReveal {
  const OlympusSeedReveal({required this.revealedServerSeed, required this.fairness});
  final String revealedServerSeed;
  final OlympusFairness fairness;
}

class OlympusState {
  const OlympusState({
    required this.layout,
    required this.balance,
    required this.history,
    required this.fairness,
  });

  final OlympusLayout layout;
  final int balance;
  final List<OlympusSpinRecord> history;
  final OlympusFairness fairness;
}

class OlympusSpinRecord {
  const OlympusSpinRecord({
    required this.nonce,
    required this.bet,
    required this.grandTotal,
    required this.freeTriggered,
    required this.tier,
    required this.at,
  });

  final int nonce, bet, grandTotal;
  final bool freeTriggered;
  final String? tier;
  final int at;

  factory OlympusSpinRecord.fromJson(Map<String, dynamic> json) => OlympusSpinRecord(
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
        bet: (json['bet'] as num?)?.toInt() ?? 0,
        grandTotal: (json['grandTotal'] as num?)?.toInt() ?? 0,
        freeTriggered: json['freeTriggered'] == true,
        tier: json['tier']?.toString(),
        at: (json['at'] as num?)?.toInt() ?? 0,
      );
}

// ── Spin payload ─────────────────────────────────────────────────────────────

class OlympusWinEntry {
  const OlympusWinEntry({required this.symbol, required this.count, required this.amount});
  final String symbol;
  final int count;
  final double amount;

  factory OlympusWinEntry.fromJson(Map<String, dynamic> json) => OlympusWinEntry(
        symbol: json['symbol']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// One lightning multiplier on the board, with the face value it will add.
class OlympusMultCell {
  const OlympusMultCell({required this.index, required this.value});
  final int index;
  final int value;

  factory OlympusMultCell.fromJson(Map<String, dynamic> json) => OlympusMultCell(
        index: (json['index'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toInt() ?? 2,
      );
}

/// One board state in a cascade, exactly as the server resolved it.
///
/// A frame is the board *before* removal: [winningCells] are the cells that are
/// about to burst. Multipliers are never in [winningCells] — they are inert
/// scenery that falls with gravity and is only collected when the tumbles stop.
class OlympusFrame {
  const OlympusFrame({
    required this.phase,
    required this.grid,
    required this.multCells,
    required this.wins,
    required this.winningCells,
    this.sequenceWin,
    this.sequenceMultiplier,
    this.sequenceTotal,
    this.spinNumber,
    this.spinsLeftAfter,
    this.scatterCount,
    this.retriggerAdded,
    this.freeMultiplierAfter,
  });

  final String phase; // 'base' | 'free'

  /// 30 symbol ids, row-major.
  final List<String> grid;
  final List<OlympusMultCell> multCells;
  final List<OlympusWinEntry> wins;
  final List<int> winningCells;

  /// Present on the last frame of a sequence — the frame where nothing wins.
  final double? sequenceWin;
  final int? sequenceMultiplier;
  final int? sequenceTotal;

  /// Free spins only, on the first frame of each spin.
  final int? spinNumber;
  final int? spinsLeftAfter;
  final int? scatterCount;
  final int? retriggerAdded;

  /// Free spins only, on the last frame of a spin: the meter after this spin.
  final int? freeMultiplierAfter;

  bool get hadWin => wins.isNotEmpty;

  /// Sum of every multiplier showing in this frame. Only meaningful on the
  /// frame where the cascade stopped — that is where the server reads it.
  int get multiplierTotal => multCells.fold(0, (a, m) => a + m.value);

  factory OlympusFrame.fromJson(Map<String, dynamic> json) => OlympusFrame(
        phase: json['phase']?.toString() ?? 'base',
        grid: ((json['grid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        multCells: ((json['multCells'] as List?) ?? const [])
            .map((e) => OlympusMultCell.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        wins: ((json['wins'] as List?) ?? const [])
            .map((e) => OlympusWinEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        winningCells:
            ((json['winningCells'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        sequenceWin: (json['sequenceWin'] as num?)?.toDouble(),
        sequenceMultiplier: (json['sequenceMultiplier'] as num?)?.toInt(),
        sequenceTotal: (json['sequenceTotal'] as num?)?.toInt(),
        spinNumber: (json['spinNumber'] as num?)?.toInt(),
        spinsLeftAfter: (json['spinsLeftAfter'] as num?)?.toInt(),
        scatterCount: (json['scatterCount'] as num?)?.toInt(),
        retriggerAdded: (json['retriggerAdded'] as num?)?.toInt(),
        freeMultiplierAfter: (json['freeMultiplierAfter'] as num?)?.toInt(),
      );
}

class OlympusSpin {
  const OlympusSpin({
    required this.bet,
    required this.initialGrid,
    required this.initialMults,
    required this.scattersInitial,
    required this.freeTriggered,
    required this.frames,
    required this.baseWin,
    required this.baseMultiplier,
    required this.baseTotal,
    required this.freeWin,
    required this.freeSpins,
    required this.freeRetriggers,
    required this.freeMultiplier,
    required this.freeTotal,
    required this.uncappedTotal,
    required this.capped,
    required this.grandTotal,
    required this.tier,
  });

  final int bet;
  final List<String> initialGrid;
  final List<OlympusMultCell> initialMults;
  final int scattersInitial;
  final bool freeTriggered;
  final List<OlympusFrame> frames;

  /// Raw symbol win in base play, before the lightning multiplier.
  final double baseWin;
  final int baseMultiplier;
  final int baseTotal;

  final double freeWin;
  final int freeSpins, freeRetriggers, freeMultiplier, freeTotal;

  /// Before the 5,000× ceiling — kept so the client can say honestly when the
  /// cap bit rather than quietly showing a smaller number.
  final int uncappedTotal;
  final bool capped;
  final int grandTotal;
  final String? tier;

  factory OlympusSpin.fromJson(Map<String, dynamic> json) => OlympusSpin(
        bet: (json['bet'] as num?)?.toInt() ?? 0,
        initialGrid:
            ((json['initialGrid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        initialMults: ((json['initialMults'] as List?) ?? const [])
            .map((e) => OlympusMultCell.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        scattersInitial: (json['scattersInitial'] as num?)?.toInt() ?? 0,
        freeTriggered: json['freeTriggered'] == true,
        frames: ((json['frames'] as List?) ?? const [])
            .map((e) => OlympusFrame.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        baseWin: (json['baseWin'] as num?)?.toDouble() ?? 0,
        baseMultiplier: (json['baseMultiplier'] as num?)?.toInt() ?? 0,
        baseTotal: (json['baseTotal'] as num?)?.toInt() ?? 0,
        freeWin: (json['freeWin'] as num?)?.toDouble() ?? 0,
        freeSpins: (json['freeSpins'] as num?)?.toInt() ?? 0,
        freeRetriggers: (json['freeRetriggers'] as num?)?.toInt() ?? 0,
        freeMultiplier: (json['freeMultiplier'] as num?)?.toInt() ?? 0,
        freeTotal: (json['freeTotal'] as num?)?.toInt() ?? 0,
        uncappedTotal: (json['uncappedTotal'] as num?)?.toInt() ?? 0,
        capped: json['capped'] == true,
        grandTotal: (json['grandTotal'] as num?)?.toInt() ?? 0,
        tier: json['tier']?.toString(),
      );
}

class OlympusSpinResponse {
  const OlympusSpinResponse({
    required this.spin,
    required this.balance,
    required this.fairness,
  });

  final OlympusSpin spin;
  final int balance;

  /// The seed pair this spin was drawn from, so the fairness sheet stays current
  /// without a second round trip.
  final OlympusFairness fairness;
}

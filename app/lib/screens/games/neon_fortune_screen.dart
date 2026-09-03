import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/neon_fortune_repository.dart';
import 'neon_fortune_help.dart';
import 'neon_fortune_sfx.dart';
import 'neon_fortune_strings.dart';
import 'neon_fortune_symbols.dart';
import 'neon_fortune_vault.dart';

/// نيون فورتشن — Neon Fortune: Tiger City.
///
/// Original fictional 5×3 / 20-payline game with four progressive pools, a
/// free-spin round (اندفاع الأفق) and a pick bonus (خزنة الأضواء). See
/// docs/neon-fortune-design-review.md for the design, and
/// NEON_FORTUNE_ARTWORK_BRIEF.md for the art.
///
/// Everything that decides a symbol, a payline, a feature or a payout is
/// server-side (backend/src/services/neonFortune.service.ts). This screen asks
/// for one fully-resolved spin per tap and replays it — it never decides an
/// outcome, and the reels only ever reveal a grid the server already fixed.
class NeonFortuneScreen extends StatefulWidget {
  const NeonFortuneScreen({super.key});

  @override
  State<NeonFortuneScreen> createState() => _NeonFortuneScreenState();
}

class _NeonFortuneScreenState extends State<NeonFortuneScreen> {
  final _repo = NeonFortuneRepository();
  final _sfx = NeonFortuneSfx();
  final _rand = math.Random();

  NeonLayout? _layout;
  NeonArt? _art;

  int _balance = 0;
  int _bet = 100;
  Map<String, int> _jackpots = const {};
  List<NeonFeedEntry> _feed = const [];
  NeonLuckyDrop _lucky = NeonLuckyDrop.empty;
  bool _claimingLucky = false;

  bool _loading = true;
  bool _busy = false;
  String? _notice;

  bool _muted = false;
  bool _reducedMotion = false;
  bool _auto = false;
  bool _stopRequested = false;

  // ── Board ────────────────────────────────────────────────────────────────
  /// Row-major, 15 cells. Populated with a resting grid before the first spin.
  List<String> _grid = List<String>.filled(15, 'TEN');
  final Set<int> _spinningReels = {};
  Set<int> _highlighted = {};
  Map<int, int> _wildMultipliers = const {};
  Timer? _blurTimer;

  // ── HUD ──────────────────────────────────────────────────────────────────
  int _lastWin = 0;
  int _displayWin = 0;
  String? _lineLabel;

  bool _inFreeSpins = false;
  int _freeSpinsLeft = 0;
  int _freeSpinsTotal = 0;
  int _freeSpinsWinSoFar = 0;
  bool _skipFeature = false;

  // ── Overlays ─────────────────────────────────────────────────────────────
  bool _showRushIntro = false;
  NeonVaultRound? _vault;
  Completer<void>? _vaultCompleter;
  _Settlement? _settlement;
  Completer<void>? _settlementCompleter;
  String? _celebrationTier;
  int _celebrationAmount = 0;

  Timer? _jackpotPoll;
  Timer? _luckyTicker;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _blurTimer?.cancel();
    _jackpotPoll?.cancel();
    _luckyTicker?.cancel();
    _sfx.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final results = await Future.wait([_repo.fetchState(), NeonArt.load()]);
      final state = results[0] as NeonState;
      final art = results[1] as NeonArt;
      if (!mounted) return;
      setState(() {
        _layout = state.layout;
        _art = art;
        _balance = state.balance;
        _jackpots = state.jackpots;
        _feed = state.feed;
        _lucky = state.lucky;
        _bet = state.layout.betSteps.contains(_bet) ? _bet : state.layout.minBet;
        _grid = _restingGrid();
        _loading = false;
      });
      _jackpotPoll = Timer.periodic(const Duration(seconds: 12), (_) => _pollJackpots());
      // Ticks only while the chest is counting down, so the label stays honest
      // without repainting the screen once a second forever.
      _luckyTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _lucky.canClaim) return;
        if (_lucky.remaining == Duration.zero) {
          _refreshLucky();
        } else {
          setState(() {});
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notice = e.toString();
      });
    }
  }

  Future<void> _pollJackpots() async {
    if (_busy) return;
    try {
      final poll = await _repo.fetchJackpots();
      if (!mounted) return;
      setState(() {
        _jackpots = poll.jackpots;
        _feed = poll.feed;
      });
    } catch (_) {
      // The meters keep their last value; a failed poll is not worth a notice.
    }
  }

  Future<void> _refreshLucky() async {
    try {
      final lucky = await _repo.fetchLuckyDrop();
      if (!mounted) return;
      setState(() => _lucky = lucky);
    } catch (_) {
      // The chest keeps its last known state; a failed poll is not a notice.
    }
  }

  /// Opens the free coin chest. The server owns the cooldown — this only asks.
  Future<void> _claimLucky() async {
    if (_claimingLucky || !_lucky.canClaim) return;
    setState(() => _claimingLucky = true);
    final strings = NeonStrings.of(context);
    try {
      final claim = await _repo.claimLuckyDrop();
      if (!mounted) return;
      setState(() {
        _balance = claim.balance;
        _lucky = claim.lucky;
        _notice = null;
      });
      _sfx.lineWin();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kNeonPlum,
          content: Text(
            strings.luckyClaimed(neonCoins(claim.reward)),
            style: const TextStyle(color: kNeonGold, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _sfx.error();
      setState(() => _notice = e.toString());
      await _refreshLucky();
    } finally {
      if (mounted) setState(() => _claimingLucky = false);
    }
  }

  /// A plausible still board for before the first spin — decoration only, it is
  /// never scored and is replaced by the server's grid on the first tap.
  List<String> _restingGrid() {
    const pool = ['TEN', 'J', 'Q', 'K', 'A', 'COIN', 'LANTERN', 'KOI', 'CRANE'];
    return List<String>.generate(15, (_) => pool[_rand.nextInt(pool.length)]);
  }

  String _randomSymbol() {
    const pool = [
      'TEN', 'TEN', 'J', 'J', 'Q', 'Q', 'K', 'A', 'COIN', 'LANTERN',
      'KOI', 'CRANE', 'PANTHER', 'TIGER', 'WILD', 'SCATTER', 'TOKEN',
    ];
    return pool[_rand.nextInt(pool.length)];
  }

  // ── Spinning ─────────────────────────────────────────────────────────────

  Future<void> _spin() async {
    final layout = _layout;
    if (layout == null || _busy) return;

    if (_balance < _bet) {
      _sfx.error();
      setState(() => _auto = false);
      await _showLowBalance();
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
      _highlighted = {};
      _wildMultipliers = const {};
      _lineLabel = null;
      _lastWin = 0;
      _displayWin = 0;
      _spinningReels.addAll(List.generate(layout.reels, (i) => i));
    });

    _sfx.spinStart();
    if (!_reducedMotion) _startBlur();
    final spinStartedAt = DateTime.now();

    NeonSpinResponse res;
    try {
      res = await _repo.spin(amount: _bet);
    } catch (e) {
      _stopBlur();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _auto = false;
        _spinningReels.clear();
        _notice = e.toString();
      });
      _sfx.error();
      return;
    }

    if (!mounted) return;
    setState(() {
      _balance = res.balance;
      _jackpots = res.jackpots;
    });

    // Hold the reels for a beat even on a fast response, so the spin reads as a
    // spin rather than a flicker.
    final elapsed = DateTime.now().difference(spinStartedAt).inMilliseconds;
    final minimum = _reducedMotion ? 120 : 520;
    if (elapsed < minimum) {
      await Future<void>.delayed(Duration(milliseconds: minimum - elapsed));
    }

    await _revealGrid(res.spin.grid, wildMultipliers: const {});
    if (!mounted) return;

    await _playWins(res.spin.wins, res.spin.baseWin);

    if (res.spin.freeSpinsTriggered && res.spin.freeSpins != null) {
      await _playFreeSpins(res.spin.freeSpins!, res.spin.scatterCells);
    }
    if (res.spin.vaultTriggered && res.spin.vault != null) {
      await _playVault(res.spin.vault!, res.spin.tokenCells);
    }

    if (!mounted) return;
    setState(() {
      _lastWin = res.spin.grandTotal;
      _displayWin = res.spin.grandTotal;
    });

    final tier = res.spin.tier;
    if (tier != null && tier != 'WIN') {
      await _celebrate(tier, res.spin.grandTotal);
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (_auto && !_stopRequested && mounted) {
      if (_balance < _bet) {
        setState(() {
          _auto = false;
          _notice = NeonStrings.of(context).autoStoppedLowBalance;
        });
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted && _auto && !_stopRequested) _spin();
    } else if (_stopRequested) {
      setState(() {
        _stopRequested = false;
        _auto = false;
      });
    }
  }

  void _startBlur() {
    _blurTimer?.cancel();
    _blurTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted || _spinningReels.isEmpty) return;
      setState(() {
        for (final reel in _spinningReels) {
          for (var row = 0; row < 3; row++) {
            _grid[row * 5 + reel] = _randomSymbol();
          }
        }
      });
    });
  }

  void _stopBlur() {
    _blurTimer?.cancel();
    _blurTimer = null;
  }

  /// Stops the reels left to right onto the grid the server already decided.
  Future<void> _revealGrid(List<String> grid, {required Map<int, int> wildMultipliers}) async {
    final reels = _layout?.reels ?? 5;
    for (var reel = 0; reel < reels; reel++) {
      if (!mounted) return;
      setState(() {
        for (var row = 0; row < 3; row++) {
          final i = row * 5 + reel;
          if (i < grid.length) _grid[i] = grid[i];
        }
        _spinningReels.remove(reel);
        _wildMultipliers = wildMultipliers;
      });
      _sfx.reelStop();
      if (!_reducedMotion && !_skipFeature) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    _stopBlur();
  }

  /// Walks the winning lines one at a time so each is actually readable, then
  /// counts the total up into the win box.
  Future<void> _playWins(List<NeonLineWin> wins, int total) async {
    if (wins.isEmpty) {
      setState(() => _highlighted = {});
      return;
    }

    _sfx.lineWin();
    if (!_reducedMotion && !_skipFeature && wins.length > 1) {
      final strings = NeonStrings.of(context);
      for (final win in wins.take(6)) {
        if (!mounted) return;
        setState(() {
          _highlighted = win.cells.toSet();
          _lineLabel = strings.lineWin(win.line + 1, neonCoins(win.amount));
        });
        await Future<void>.delayed(const Duration(milliseconds: 420));
      }
    }

    if (!mounted) return;
    final strings = NeonStrings.of(context);
    setState(() {
      _highlighted = wins.expand((w) => w.cells).toSet();
      _lineLabel = wins.length == 1
          ? strings.line(wins.first.line + 1)
          : strings.winningLines(wins.length);
    });
    await _countUp(total);
  }

  Future<void> _countUp(int target) async {
    if (target <= 0) return;
    if (_reducedMotion || _skipFeature) {
      setState(() => _displayWin = target);
      return;
    }
    const steps = 14;
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      setState(() => _displayWin = (target * i / steps).round());
      await Future<void>.delayed(const Duration(milliseconds: 28));
    }
  }

  // ── Skyline Rush ─────────────────────────────────────────────────────────

  Future<void> _playFreeSpins(NeonFreeSpinRound round, List<int> scatterCells) async {
    _sfx.scatterLand();
    if (!mounted) return;
    setState(() {
      _highlighted = scatterCells.toSet();
      _lineLabel = null;
    });
    await Future<void>.delayed(Duration(milliseconds: _reducedMotion ? 200 : 600));

    _sfx.freeSpinsStart();
    setState(() {
      _showRushIntro = true;
      _inFreeSpins = true;
      _freeSpinsTotal = round.spinsAwarded;
      _freeSpinsLeft = round.spinsAwarded;
      _freeSpinsWinSoFar = 0;
      _skipFeature = false;
    });
    await Future<void>.delayed(Duration(milliseconds: _reducedMotion ? 400 : 1500));
    if (!mounted) return;
    setState(() => _showRushIntro = false);

    for (final frame in round.frames) {
      if (!mounted) return;
      setState(() {
        _freeSpinsLeft = frame.spinsLeftAfter;
        _freeSpinsTotal = math.max(_freeSpinsTotal, frame.index + frame.spinsLeftAfter);
        _highlighted = {};
        _spinningReels.addAll(List.generate(_layout?.reels ?? 5, (i) => i));
      });
      if (!_reducedMotion && !_skipFeature) {
        _startBlur();
        await Future<void>.delayed(const Duration(milliseconds: 280));
      }
      await _revealGrid(frame.grid, wildMultipliers: frame.wildMultipliers);
      if (!mounted) return;

      setState(() => _freeSpinsWinSoFar += frame.win);
      if (frame.win > 0) {
        await _playWins(frame.wins, _freeSpinsWinSoFar);
      }
      if (frame.retriggered > 0) {
        _sfx.scatterLand();
        setState(() => _lineLabel = NeonStrings.of(context).extraSpins(frame.retriggered));
        if (!_skipFeature) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      if (!_skipFeature && !_reducedMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    }

    if (!mounted) return;
    setState(() {
      _inFreeSpins = false;
      _wildMultipliers = const {};
    });

    final strings = NeonStrings.of(context);
    await _showSettlement(
      _Settlement(
        title: strings.rushName,
        total: round.total,
        rows: [
          (strings.spinsPlayed, '${round.spinsPlayed}'),
          (strings.bestSpin, neonCoins(round.bestSingle)),
          (strings.roundTotal, neonCoins(round.total)),
        ],
      ),
    );
  }

  // ── Vault of Lights ──────────────────────────────────────────────────────

  Future<void> _playVault(NeonVaultRound vault, List<int> tokenCells) async {
    _sfx.tokenLand();
    if (!mounted) return;
    setState(() {
      _highlighted = tokenCells.toSet();
      _lineLabel = null;
    });
    await Future<void>.delayed(Duration(milliseconds: _reducedMotion ? 200 : 650));

    _sfx.vaultOpen();
    final completer = Completer<void>();
    setState(() {
      _vault = vault;
      _vaultCompleter = completer;
    });
    await completer.future;
    if (!mounted) return;
    setState(() {
      _vault = null;
      _vaultCompleter = null;
    });
  }

  Future<void> _showSettlement(_Settlement settlement) async {
    final completer = Completer<void>();
    if (!mounted) return;
    setState(() {
      _settlement = settlement;
      _settlementCompleter = completer;
    });
    await completer.future;
    if (!mounted) return;
    setState(() {
      _settlement = null;
      _settlementCompleter = null;
      _skipFeature = false;
    });
  }

  Future<void> _celebrate(String tier, int amount) async {
    _sfx.celebration(tier);
    if (!_reducedMotion) HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _celebrationTier = tier;
      _celebrationAmount = amount;
    });
    await Future<void>.delayed(Duration(milliseconds: _reducedMotion ? 500 : 1600));
    if (!mounted) return;
    setState(() => _celebrationTier = null);
  }

  Future<void> _showLowBalance() async {
    final strings = NeonStrings.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: strings.direction,
        child: AlertDialog(
          backgroundColor: kNeonPlum,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(strings.lowBalanceTitle, style: const TextStyle(color: kNeonText)),
          content: Text(
            strings.lowBalanceBody,
            style: const TextStyle(color: kNeonTextDim, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _lowerBet();
              },
              child: Text(strings.lowerBet, style: const TextStyle(color: kNeonLime)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.ok, style: const TextStyle(color: kNeonCyan)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bet ──────────────────────────────────────────────────────────────────

  void _lowerBet() {
    final steps = _layout?.betSteps ?? const [50, 100, 250, 500, 1000];
    final i = steps.indexOf(_bet);
    if (i > 0) {
      setState(() => _bet = steps[i - 1]);
      _sfx.betChange();
    }
  }

  void _raiseBet() {
    final steps = _layout?.betSteps ?? const [50, 100, 250, 500, 1000];
    final i = steps.indexOf(_bet);
    if (i >= 0 && i < steps.length - 1) {
      setState(() => _bet = steps[i + 1]);
      _sfx.betChange();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: NeonStrings.of(context).direction,
      child: Scaffold(
        backgroundColor: kNeonInk,
        body: Stack(
          children: [
            const Positioned.fill(child: _CityBackdrop()),
            SafeArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kNeonCyan))
                  : _layout == null
                      ? _loadFailed()
                      : _cabinet(),
            ),
            if (_showRushIntro) Positioned.fill(child: _rushIntro()),
            if (_vault != null)
              Positioned.fill(
                child: NeonVaultOverlay(
                  vault: _vault!,
                  reducedMotion: _reducedMotion,
                  onFinished: () => _vaultCompleter?.complete(),
                ),
              ),
            if (_settlement != null) Positioned.fill(child: _settlementPanel(_settlement!)),
            if (_celebrationTier != null)
              Positioned.fill(child: IgnorePointer(child: _celebration(_celebrationTier!))),
          ],
        ),
      ),
    );
  }

  Widget _loadFailed() {
    final strings = NeonStrings.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _notice ?? strings.loadFailed,
            style: const TextStyle(color: kNeonText, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () {
              setState(() => _loading = true);
              _boot();
            },
            child: Text(strings.retry, style: const TextStyle(color: kNeonCyan)),
          ),
        ],
      ),
    );
  }

  Widget _cabinet() {
    return LayoutBuilder(
      builder: (context, box) {
        // The bands from §2 of the design review: header, event strip, crown,
        // cabinet, ribbon, controls, footer. The cabinet takes whatever is left
        // after the fixed rows, so the layout holds from 9:16 to 9:20 without
        // reflowing.
        final tight = box.maxHeight < 640;
        return Column(
          children: [
            _header(),
            if (!tight) _eventStrip(),
            _jackpotCrown(),
            Expanded(child: Center(child: _reels())),
            _ribbon(),
            _controls(),
            _footer(),
          ],
        );
      },
    );
  }

  Widget _header() {
    final strings = NeonStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              strings.ar ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: kNeonText,
            ),
            tooltip: strings.back,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kNeonPlum.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kNeonGold.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on_rounded, color: kNeonGold, size: 18),
                const SizedBox(width: 6),
                Text(
                  neonCoins(_balance),
                  style: const TextStyle(
                    color: kNeonGold,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => setState(() {
              _reducedMotion = !_reducedMotion;
            }),
            icon: Icon(
              _reducedMotion ? Icons.motion_photos_off_rounded : Icons.motion_photos_on_rounded,
              color: _reducedMotion ? kNeonTextDim : kNeonCyan,
            ),
            tooltip: strings.reducedMotion,
          ),
          IconButton(
            onPressed: () => setState(() {
              _muted = !_muted;
              _sfx.enabled = !_muted;
            }),
            icon: Icon(
              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _muted ? kNeonTextDim : kNeonCyan,
            ),
            tooltip: strings.sound,
          ),
          IconButton(
            onPressed: () => NeonFortuneHelp.show(
              context,
              layout: _layout!,
              jackpots: _jackpots,
              lucky: _lucky,
            ),
            icon: const Icon(Icons.info_outline_rounded, color: kNeonCyan),
            tooltip: strings.rules,
          ),
        ],
      ),
    );
  }

  /// Real wins by real players. Empty until somebody actually wins — nothing
  /// here is invented (design review D3).
  Widget _eventStrip() {
    final strings = NeonStrings.of(context);
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 8),
            child: _luckyChest(strings),
          ),
          Expanded(child: _feedList(strings)),
        ],
      ),
    );
  }

  /// The free coin chest: claimable on a server-owned cooldown, no purchase and
  /// no ad in the path.
  Widget _luckyChest(NeonStrings strings) {
    final ready = _lucky.canClaim && _lucky.reward > 0;
    return GestureDetector(
      onTap: ready && !_claimingLucky ? _claimLucky : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: ready
                ? [kNeonGold.withValues(alpha: 0.32), kNeonPlum]
                : [kNeonPlum.withValues(alpha: 0.8), kNeonInk],
          ),
          border: Border.all(
            color: (ready ? kNeonGold : kNeonTextDim).withValues(alpha: ready ? 0.9 : 0.35),
          ),
          boxShadow: ready
              ? [BoxShadow(color: kNeonGold.withValues(alpha: 0.35), blurRadius: 12)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ready ? Icons.card_giftcard_rounded : Icons.lock_clock_rounded,
              color: ready ? kNeonGold : kNeonTextDim,
              size: 18,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.luckyDrop,
                  style: TextStyle(
                    color: ready ? kNeonGold : kNeonTextDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _claimingLucky
                      ? '…'
                      : ready
                          ? neonCoins(_lucky.reward)
                          : strings.luckyIn(strings.duration(_lucky.remaining)),
                  style: TextStyle(
                    color: ready ? kNeonText : kNeonTextDim.withValues(alpha: 0.8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedList(NeonStrings strings) {
    return _feed.isEmpty
        ? Center(
            child: Text(
              strings.feedEmpty,
              style: TextStyle(color: kNeonTextDim.withValues(alpha: 0.7), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          )
        : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _feed.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final e = _feed[i];
                final gold = e.jackpot != null;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: kNeonPlum.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (gold ? kNeonGold : kNeonViolet).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        gold ? Icons.emoji_events_rounded : Icons.bolt_rounded,
                        color: gold ? kNeonGold : kNeonCyan,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        e.name,
                        style: const TextStyle(color: kNeonText, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        neonCoins(e.amount),
                        style: TextStyle(
                          color: gold ? kNeonGold : kNeonLime,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
  }

  Widget _jackpotCrown() {
    final strings = NeonStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(
        children: [
          Text(
            strings.title,
            style: const TextStyle(
              color: kNeonText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              shadows: [
                Shadow(color: kNeonMagenta, blurRadius: 18),
                Shadow(color: kNeonViolet, blurRadius: 26),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: kJackpotTiers.map((tier) {
              final color = kJackpotColors[tier] ?? kNeonGold;
              return Expanded(
                child: GestureDetector(
                  onTap: () => NeonFortuneHelp.show(
                    context,
                    layout: _layout!,
                    jackpots: _jackpots,
                    lucky: _lucky,
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withValues(alpha: 0.28), kNeonPlum.withValues(alpha: 0.9)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.75)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          strings.tier(tier),
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          neonCoins(_jackpots[tier] ?? 0),
                          style: const TextStyle(
                            color: kNeonText,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _reels() {
    final reels = _layout?.reels ?? 5;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: AspectRatio(
        aspectRatio: 5 / 3.35,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const RadialGradient(
              colors: [Color(0x33EA35D7), Color(0xCC17062E)],
            ),
            border: Border.all(color: kNeonViolet.withValues(alpha: 0.85), width: 2),
            boxShadow: [
              BoxShadow(color: kNeonViolet.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: Row(
            children: List.generate(reels, (reel) {
              // A reel that is still turning gets a light motion veil; the
              // symbols under it are placeholders until the server's grid is
              // revealed for this reel.
              final spinning = _spinningReels.contains(reel) && !_reducedMotion;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Opacity(
                    opacity: spinning ? 0.72 : 1,
                    child: Column(
                      children: List.generate(3, (row) {
                        final i = row * 5 + reel;
                        final symbol = i < _grid.length ? _grid[i] : 'TEN';
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.5),
                            child: NeonSymbolTile(
                              symbol: symbol,
                              art: _art?.forSymbol(symbol),
                              highlighted: _highlighted.contains(i),
                              dimmed: _highlighted.isNotEmpty && !_highlighted.contains(i),
                              multiplier: _wildMultipliers[i],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _ribbon() {
    final strings = NeonStrings.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: kNeonPlum.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kNeonCyan.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          if (_inFreeSpins) ...[
            const Icon(Icons.auto_awesome_rounded, color: kNeonMagenta, size: 16),
            const SizedBox(width: 6),
            Text(
              strings.rushCounter(_freeSpinsLeft, _freeSpinsTotal),
              style: const TextStyle(color: kNeonMagenta, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            // Skips the remaining animation, never the result: every frame is
            // still shown, just without the pauses between them.
            if (!_skipFeature)
              GestureDetector(
                onTap: () => setState(() => _skipFeature = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: kNeonCyan.withValues(alpha: 0.7)),
                  ),
                  child: Text(
                    strings.skip,
                    style: const TextStyle(color: kNeonCyan, fontSize: 11.5),
                  ),
                ),
              ),
            const Spacer(),
            Text(
              neonCoins(_freeSpinsWinSoFar),
              style: const TextStyle(color: kNeonGold, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ] else ...[
            Text(
              _lineLabel ?? strings.lastWin,
              style: const TextStyle(color: kNeonTextDim, fontSize: 12.5),
            ),
            const Spacer(),
            Text(
              neonCoins(_displayWin > 0 ? _displayWin : _lastWin),
              style: TextStyle(
                color: (_displayWin > 0 || _lastWin > 0) ? kNeonGold : kNeonTextDim,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _controls() {
    final strings = NeonStrings.of(context);
    final canSpin = !_busy && !_loading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Column(
        children: [
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _notice!,
                style: const TextStyle(color: Color(0xFFFF6D54), fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            children: [
              _roundButton(
                icon: Icons.remove_rounded,
                onTap: canSpin ? _lowerBet : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: kNeonInk.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kNeonGold.withValues(alpha: 0.55)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        strings.bet,
                        style: const TextStyle(color: kNeonTextDim, fontSize: 10.5),
                      ),
                      Text(
                        neonCoins(_bet),
                        style: const TextStyle(
                          color: kNeonGold,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _roundButton(
                icon: Icons.add_rounded,
                onTap: canSpin ? _raiseBet : null,
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: canSpin ? _spin : null,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: canSpin
                          ? [kNeonLime, const Color(0xFF4FA614)]
                          : [kNeonTextDim.withValues(alpha: 0.5), kNeonPlum],
                    ),
                    boxShadow: canSpin
                        ? [BoxShadow(color: kNeonLime.withValues(alpha: 0.5), blurRadius: 20)]
                        : null,
                  ),
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(color: kNeonInk, strokeWidth: 3),
                          )
                        : Text(
                            strings.spin,
                            style: const TextStyle(
                              color: kNeonInk,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _roundButton(
                icon: _auto ? Icons.stop_rounded : Icons.autorenew_rounded,
                color: _auto ? kNeonMagenta : kNeonCyan,
                onTap: () {
                  if (_auto) {
                    setState(() {
                      _stopRequested = true;
                      _auto = false;
                    });
                  } else {
                    setState(() {
                      _auto = true;
                      _stopRequested = false;
                    });
                    if (!_busy) _spin();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundButton({required IconData icon, VoidCallback? onTap, Color color = kNeonCyan}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kNeonPlum.withValues(alpha: 0.9),
          border: Border.all(
            color: (onTap == null ? kNeonTextDim : color).withValues(alpha: 0.7),
          ),
        ),
        child: Icon(icon, color: onTap == null ? kNeonTextDim : color, size: 22),
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 14, right: 14),
      child: Text(
        NeonStrings.of(context).footer,
        textAlign: TextAlign.center,
        style: TextStyle(color: kNeonTextDim.withValues(alpha: 0.65), fontSize: 10.5),
      ),
    );
  }

  // ── Overlays ─────────────────────────────────────────────────────────────

  Widget _rushIntro() {
    final strings = NeonStrings.of(context);
    return Container(
      color: kNeonInk.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: kNeonMagenta, size: 54),
            const SizedBox(height: 12),
            Text(
              strings.rushFreeSpins(_freeSpinsTotal),
              style: const TextStyle(
                color: kNeonText,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: kNeonMagenta, blurRadius: 22)],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.rushSubtitle,
              style: const TextStyle(color: kNeonTextDim, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settlementPanel(_Settlement s) {
    return Container(
      color: kNeonInk.withValues(alpha: 0.93),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: kNeonPlum,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kNeonMagenta.withValues(alpha: 0.8), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.title,
                style: const TextStyle(
                  color: kNeonMagenta,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              ...s.rows.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(r.$1, style: const TextStyle(color: kNeonTextDim, fontSize: 13.5)),
                      const Spacer(),
                      Text(
                        r.$2,
                        style: const TextStyle(
                          color: kNeonText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kNeonLime,
                    foregroundColor: kNeonInk,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _settlementCompleter?.complete(),
                  child: Text(
                    NeonStrings.of(context).carryOn,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _celebration(String tier) {
    final label = NeonStrings.of(context).celebration(tier);
    final color = switch (tier) {
      'CITY_LIGHTS' => kNeonGold,
      'MEGA_WIN' => kNeonMagenta,
      _ => kNeonCyan,
    };
    return Container(
      color: kNeonInk.withValues(alpha: 0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 26)],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              neonCoins(_celebrationAmount),
              style: const TextStyle(
                color: kNeonText,
                fontSize: 44,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Settlement {
  const _Settlement({required this.title, required this.total, required this.rows});
  final String title;
  final int total;
  final List<(String, String)> rows;
}

/// Low-contrast skyline behind the cabinet: decoration that frames the reels
/// rather than competing with them.
class _CityBackdrop extends StatelessWidget {
  const _CityBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.1,
          colors: [Color(0xFF2B0B52), kNeonInk],
        ),
      ),
      child: CustomPaint(painter: _SkylinePainter(), size: Size.infinite),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(7);
    final building = Paint()..color = const Color(0xFF1E0840);
    final window = Paint()..color = kNeonCyan.withValues(alpha: 0.16);

    var x = 0.0;
    while (x < size.width) {
      final w = 26.0 + rand.nextDouble() * 30;
      final h = 70.0 + rand.nextDouble() * 150;
      final top = size.height - h;
      canvas.drawRect(Rect.fromLTWH(x, top, w, h), building);

      for (var wy = top + 10; wy < size.height - 12; wy += 16) {
        for (var wx = x + 6; wx < x + w - 8; wx += 12) {
          if (rand.nextDouble() > 0.55) {
            canvas.drawRect(Rect.fromLTWH(wx, wy, 4, 6), window);
          }
        }
      }
      x += w + 4;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/neon_fortune_repository.dart';
import 'neon_fortune_help.dart';
import 'neon_fortune_sfx.dart';
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

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _blurTimer?.cancel();
    _jackpotPoll?.cancel();
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
        _bet = state.layout.betSteps.contains(_bet) ? _bet : state.layout.minBet;
        _grid = _restingGrid();
        _loading = false;
      });
      _jackpotPoll = Timer.periodic(const Duration(seconds: 12), (_) => _pollJackpots());
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
          _notice = 'توقف التشغيل التلقائي — الرصيد غير كافٍ';
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
      for (final win in wins.take(6)) {
        if (!mounted) return;
        setState(() {
          _highlighted = win.cells.toSet();
          _lineLabel = 'خط ${win.line + 1} · ${neonCoins(win.amount)}';
        });
        await Future<void>.delayed(const Duration(milliseconds: 420));
      }
    }

    if (!mounted) return;
    setState(() {
      _highlighted = wins.expand((w) => w.cells).toSet();
      _lineLabel = wins.length == 1 ? 'خط ${wins.first.line + 1}' : '${wins.length} خطوط رابحة';
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
        setState(() => _lineLabel = '+${frame.retriggered} لفات إضافية');
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

    await _showSettlement(
      _Settlement(
        title: 'اندفاع الأفق',
        total: round.total,
        rows: [
          ('عدد اللفات', '${round.spinsPlayed}'),
          ('أكبر لفة', neonCoins(round.bestSingle)),
          ('إجمالي الجولة', neonCoins(round.total)),
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
    await showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: kNeonPlum,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('الرصيد لا يكفي', style: TextStyle(color: kNeonText)),
          content: const Text(
            'اختر رهانًا أقل، أو اجمع عملاتك اليومية من الصفحة الرئيسية.',
            style: TextStyle(color: kNeonTextDim, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _lowerBet();
              },
              child: const Text('خفض الرهان', style: TextStyle(color: kNeonLime)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسنًا', style: TextStyle(color: kNeonCyan)),
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
      textDirection: TextDirection.rtl,
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

  Widget _loadFailed() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _notice ?? 'تعذر تحميل اللعبة',
              style: const TextStyle(color: kNeonText, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                setState(() => _loading = true);
                _boot();
              },
              child: const Text('إعادة المحاولة', style: TextStyle(color: kNeonCyan)),
            ),
          ],
        ),
      );

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward_rounded, color: kNeonText),
            tooltip: 'رجوع',
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
            tooltip: 'تقليل الحركة',
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
            tooltip: 'الصوت',
          ),
          IconButton(
            onPressed: () => NeonFortuneHelp.show(
              context,
              layout: _layout!,
              jackpots: _jackpots,
            ),
            icon: const Icon(Icons.info_outline_rounded, color: kNeonCyan),
            tooltip: 'القواعد وجدول الأرباح',
          ),
        ],
      ),
    );
  }

  /// Real wins by real players. Empty until somebody actually wins — nothing
  /// here is invented (design review D3).
  Widget _eventStrip() {
    return SizedBox(
      height: 42,
      child: _feed.isEmpty
          ? Center(
              child: Text(
                'أكبر الأرباح تظهر هنا فور حدوثها',
                style: TextStyle(color: kNeonTextDim.withValues(alpha: 0.7), fontSize: 12),
              ),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
            ),
    );
  }

  Widget _jackpotCrown() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(
        children: [
          const Text(
            'نيون فورتشن',
            style: TextStyle(
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
                          kJackpotNames[tier] ?? tier,
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
              'اندفاع الأفق $_freeSpinsLeft/$_freeSpinsTotal',
              style: const TextStyle(color: kNeonMagenta, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              neonCoins(_freeSpinsWinSoFar),
              style: const TextStyle(color: kNeonGold, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ] else ...[
            Text(
              _lineLabel ?? 'آخر فوز',
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
                      const Text('الرهان', style: TextStyle(color: kNeonTextDim, fontSize: 10.5)),
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
                        : const Text(
                            'أدر',
                            style: TextStyle(
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
        'يعمل بعملات سمافوكس — لا تُحوَّل إلى نقود ولا تُسحب.',
        textAlign: TextAlign.center,
        style: TextStyle(color: kNeonTextDim.withValues(alpha: 0.65), fontSize: 10.5),
      ),
    );
  }

  // ── Overlays ─────────────────────────────────────────────────────────────

  Widget _rushIntro() {
    return Container(
      color: kNeonInk.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: kNeonMagenta, size: 54),
            const SizedBox(height: 12),
            Text(
              '$_freeSpinsTotal لفات مجانية',
              style: const TextStyle(
                color: kNeonText,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: kNeonMagenta, blurRadius: 22)],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اندفاع الأفق — نفس الرهان، بلا خصم',
              style: TextStyle(color: kNeonTextDim, fontSize: 14),
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
                  child: const Text(
                    'متابعة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
    final label = switch (tier) {
      'CITY_LIGHTS' => 'أضواء المدينة',
      'MEGA_WIN' => 'فوز ضخم',
      'BIG_WIN' => 'فوز كبير',
      _ => 'فوز',
    };
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

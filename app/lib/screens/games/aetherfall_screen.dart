import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../repositories/aetherfall_repository.dart';
import 'aetherfall_bonus.dart';
import 'aetherfall_celebration.dart';
import 'aetherfall_grid.dart';
import 'aetherfall_help.dart';
import 'aetherfall_sfx.dart';
import 'aetherfall_symbols.dart';

const _bgTop = Color(0xFF0F1638);
const _bgBottom = Color(0xFF07030F);
const _cyan = Color(0xFF4DD8E6);
const _ember = Color(0xFFFF8A3D);
const _mint = Color(0xFF7CE8B0);
const _copper = Color(0xFFC98A4B);

const _betSteps = [20, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 20000];

/// أثيرفول — Aetherfall: Vaults of the Skyfire.
///
/// Original fictional pay-anywhere / cascading-symbol game — see
/// AETHERFALL_ARTWORK_BRIEF.md at the repo root for the creative-distinction
/// notes and every art prompt.
///
/// Everything that decides a symbol, a tumble, the Skyfire Vault bonus or a
/// payout is server-side (backend/src/services/aetherfall.service.ts). This
/// screen requests one fully-resolved spin per IGNITE tap and replays its
/// frames — it never decides an outcome itself.
class AetherfallScreen extends StatefulWidget {
  const AetherfallScreen({super.key});

  @override
  State<AetherfallScreen> createState() => _AetherfallScreenState();
}

class _AetherfallScreenState extends State<AetherfallScreen> {
  final _repo = AetherfallRepository();
  final _sfx = AetherfallSfx();

  AetherfallLayout? _layout;
  AetherfallArt? _art;
  int _balance = 0;
  int _bet = 100;

  bool _loading = true;
  bool _busy = false;
  String? _notice;

  bool _muted = false;
  bool _reducedMotion = false;

  bool _auto = false;
  bool _stopRequested = false;

  // ── Board state ──────────────────────────────────────────────────────────
  List<String?> _displayGrid = List<String?>.filled(30, null);
  Set<int> _highlighted = {};
  Set<int> _clearing = {};
  Map<int, int> _chargeValues = {};

  // ── HUD state ────────────────────────────────────────────────────────────
  double _sequenceWin = 0;
  int _tumbleCount = 0;
  int _skyfireCharge = 0;
  int _starShards = 0;

  bool _inBonus = false;
  int _bonusTumblesLeft = 0;
  int _bonusChargeBank = 0;
  int _bonusLocks = 0;

  String? _transientBanner;
  String _heroMood = 'idle'; // idle | win | bonus

  // ── Overlays ─────────────────────────────────────────────────────────────
  bool _showBonusTransition = false;
  int _bonusTransitionTumbles = 12;
  Completer<void>? _bonusTransitionCompleter;

  String? _celebrationTier;
  int _celebrationAmount = 0;
  Completer<void>? _celebrationCompleter;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _sfx.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final state = await _repo.fetchState();
      final art = await AetherfallArt.load();
      if (!mounted) return;
      setState(() {
        _layout = state.layout;
        _balance = state.balance;
        _art = art;
        _bet = _betSteps.firstWhere(
          (b) => b >= state.layout.minBet,
          orElse: () => state.layout.minBet,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notice = 'تعذر تحميل اللعبة';
      });
    }
  }

  // ── Bet controls ─────────────────────────────────────────────────────────

  void _stepBet(int direction) {
    if (_busy || _layout == null) return;
    final options = _betSteps.where(
      (b) => b >= _layout!.minBet && b <= _layout!.maxBet,
    ).toList();
    if (options.isEmpty) return;
    final idx = options.indexWhere((b) => b >= _bet);
    var newIdx = (idx < 0 ? options.length - 1 : idx) + direction;
    newIdx = newIdx.clamp(0, options.length - 1);
    setState(() => _bet = options[newIdx]);
  }

  // ── Spin orchestration ───────────────────────────────────────────────────

  Future<void> _ignite() async {
    if (_busy || _loading || _layout == null) return;
    if (_bet > _balance) {
      setState(() => _notice = 'رصيدك لا يكفي');
      _sfx.error();
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
      _sequenceWin = 0;
      _tumbleCount = 0;
      _skyfireCharge = 0;
      _highlighted = {};
      _clearing = {};
      _chargeValues = {};
      _heroMood = 'idle';
    });
    _sfx.ignite();

    AetherfallSpinResponse response;
    try {
      response = await _repo.spin(amount: _bet);
    } catch (e) {
      _sfx.error();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = e is AetherfallException ? e.message : 'تعذر تنفيذ الجولة';
        _auto = false;
      });
      return;
    }

    await _playSpin(response.spin);
    if (!mounted) return;

    setState(() {
      _balance = response.balance;
      _starShards += (response.spin.grandTotal / 50).floor();
      _busy = false;
    });

    if (_auto && !_stopRequested && mounted) {
      if (_bet > _balance) {
        setState(() {
          _auto = false;
          _notice = 'تم إيقاف اللعب التلقائي — الرصيد غير كافٍ';
        });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 450));
      if (mounted && _auto && !_stopRequested) unawaited(_ignite());
    } else {
      _stopRequested = false;
    }
  }

  void _stopAuto() {
    setState(() {
      _auto = false;
      _stopRequested = true;
    });
  }

  Future<void> _playSpin(AetherfallSpin spin) async {
    // Initial population.
    setState(() => _displayGrid = List<String?>.from(spin.initialGrid));
    _sfx.chamberPopulate();
    await _wait(420);

    var bonusTransitionShown = false;
    int bonusHighestCharge = 0;
    int bonusCascades = 0;

    for (final frame in spin.frames) {
      if (frame.phase == 'bonus' && frame.tumbleNumber == 1 && !bonusTransitionShown) {
        bonusTransitionShown = true;
        await _enterBonusTransition();
      }

      if (frame.phase == 'bonus' && frame.tumbleNumber != null) {
        setState(() {
          _inBonus = true;
          _bonusTumblesLeft = frame.tumblesLeftAfter ?? _bonusTumblesLeft;
        });
        if ((frame.retriggerAdded ?? 0) > 0) {
          _sfx.keyCollect();
          await _flashBanner('+${frame.retriggerAdded} TUMBLES');
        }
      }

      if (frame.isStarburst) {
        _sfx.starburst();
        unawaited(_flashBanner('starburst'));
      }

      setState(() {
        _displayGrid = List<String?>.from(frame.grid);
        _highlighted = {};
        _clearing = {};
        _chargeValues = {for (final c in frame.chargeCells) c.index: c.value};
      });
      await _wait(180);

      if (frame.hadWin) {
        final tumbleAmount = frame.wins.fold<double>(0, (a, w) => a + w.amount);
        final tumbleCharge = frame.chargeCells.fold<int>(0, (a, c) => a + c.value);

        setState(() {
          _highlighted = frame.winningCells.toSet();
          _tumbleCount++;
          _sequenceWin += tumbleAmount;
          _heroMood = 'win';
          if (frame.phase == 'base') {
            _skyfireCharge += tumbleCharge;
          } else {
            _skyfireCharge = frame.chargeBankAfter ?? _skyfireCharge;
            _bonusChargeBank = frame.chargeBankAfter ?? _bonusChargeBank;
            _bonusLocks = frame.locksAfter ?? _bonusLocks;
            if (tumbleCharge > 0) {
              final maxThisFrame =
                  frame.chargeCells.map((c) => c.value).fold<int>(0, (a, b) => a > b ? a : b);
              if (maxThisFrame > bonusHighestCharge) bonusHighestCharge = maxThisFrame;
            }
            bonusCascades++;
          }
        });
        _sfx.winDiscovery();
        if (tumbleCharge > 0) _sfx.chargeLanding();
        await _wait(700);

        setState(() => _clearing = frame.clearedCells);
        _sfx.dissolve();
        await _wait(260);

        setState(() {
          final cleared = List<String?>.from(_displayGrid);
          for (final i in frame.clearedCells) {
            cleared[i] = null;
          }
          _displayGrid = cleared;
          _highlighted = {};
          _clearing = {};
          _chargeValues = {};
        });
        _sfx.refill();
        await _wait(240);
      }
    }

    // Never hide the math: show base win → charge contribution → total.
    if (spin.baseCharge > 0 && spin.baseWin > 0) {
      await _flashBanner(
        'math:${spin.baseWin.round()} × (1+${spin.baseCharge}%) = ${spin.baseTotal}',
      );
    }

    if (spin.bonusTriggered) {
      setState(() => _heroMood = 'bonus');
      _sfx.bonusSummary();
      await _showBonusSummary(
        totalCoins: spin.bonusTotal,
        highestCharge: bonusHighestCharge,
        cascadeCount: bonusCascades == 0 ? spin.bonusTumblesUsed : bonusCascades,
      );
      setState(() {
        _inBonus = false;
        _bonusLocks = 0;
      });
    }

    if (spin.tier != null) {
      setState(() => _heroMood = 'win');
      _sfx.celebration(spin.tier!);
      await _showCelebration(spin.tier!, spin.grandTotal);
    }

    if (mounted) setState(() => _heroMood = 'idle');
  }

  Future<void> _wait(int ms) => Future.delayed(
        Duration(milliseconds: _reducedMotion ? (ms * 0.4).round() : ms),
      );

  Future<void> _flashBanner(String text) async {
    setState(() => _transientBanner = text);
    await _wait(1100);
    if (mounted) setState(() => _transientBanner = null);
  }

  Future<void> _enterBonusTransition() {
    final completer = Completer<void>();
    _bonusTransitionCompleter = completer;
    setState(() {
      _bonusTransitionTumbles = _layout?.vaultBonusStartTumbles ?? 12;
      _showBonusTransition = true;
    });
    return completer.future;
  }

  void _onBonusTransitionDone() {
    if (_bonusTransitionCompleter == null || _bonusTransitionCompleter!.isCompleted) return;
    setState(() => _showBonusTransition = false);
    _bonusTransitionCompleter!.complete();
  }

  Future<void> _showCelebration(String tier, int amount) {
    final completer = Completer<void>();
    _celebrationCompleter = completer;
    setState(() {
      _celebrationTier = tier;
      _celebrationAmount = amount;
    });
    return completer.future;
  }

  void _onCelebrationDone() {
    if (_celebrationCompleter == null || _celebrationCompleter!.isCompleted) return;
    setState(() => _celebrationTier = null);
    _celebrationCompleter!.complete();
  }

  Future<void> _showBonusSummary({
    required int totalCoins,
    required int highestCharge,
    required int cascadeCount,
  }) {
    if (!mounted) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => BonusSummarySheet(
        totalCoins: totalCoins,
        highestCharge: highestCharge,
        cascadeCount: cascadeCount,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bgTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SETTINGS',
                  style: TextStyle(color: _cyan, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _cyan,
                  title: const Text('Sound', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Music and effects', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: !_muted,
                  onChanged: (on) {
                    setState(() {
                      _muted = !on;
                      _sfx.enabled = on;
                    });
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _cyan,
                  title: const Text('Reduced Motion', style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Shortens animations and removes screen shake',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  value: _reducedMotion,
                  onChanged: (on) {
                    setState(() => _reducedMotion = on);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () {
                    setState(() => _starShards = 0);
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Reset session stats', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openHelp() {
    if (_layout == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AetherfallHelpSheet(layout: _layout!),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBottom,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
            // The skybox swaps when the Skyfire Vault opens. The gradient stays
            // underneath so the screen still reads correctly if the art is
            // missing from the bundle.
            image: DecorationImage(
              image: AssetImage(
                _inBonus
                    ? 'assets/images/aetherfall/bg_bonus_vault.png'
                    : 'assets/images/aetherfall/bg_observatory.png',
              ),
              fit: BoxFit.cover,
              opacity: 0.55,
              onError: (_, __) {},
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _cyan))
              : Stack(
                  children: [
                    Column(
                      children: [
                        _topBar(),
                        if (_notice != null) _noticeBar(),
                        Expanded(child: _playfield()),
                        _bottomBar(),
                      ],
                    ),
                    if (_transientBanner != null) _bannerOverlay(),
                    if (_showBonusTransition)
                      Positioned.fill(
                        child: SkyfireVaultTransition(
                          tumbles: _bonusTransitionTumbles,
                          reducedMotion: _reducedMotion,
                          art: _art,
                          onDone: _onBonusTransitionDone,
                        ),
                      ),
                    if (_celebrationTier != null)
                      Positioned.fill(
                        child: CelebrationOverlay(
                          tier: _celebrationTier!,
                          amount: _celebrationAmount,
                          reducedMotion: _reducedMotion,
                          art: _art,
                          onDone: _onCelebrationDone,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Row(
          children: [
            const Text(
              'AETHERFALL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
            ),
            const Spacer(),
            _coinBadge(),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _muted = !_muted;
                  _sfx.enabled = !_muted;
                });
                _sfx.mute();
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
              onPressed: _openSettings,
            ),
            IconButton(
              icon: const Icon(Icons.help_outline_rounded, color: Colors.white70, size: 20),
              onPressed: _openHelp,
            ),
          ],
        ),
      );

  Widget _coinBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, color: _copper, size: 12),
            const SizedBox(width: 6),
            Text(
              '$_balance',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );

  Widget _noticeBar() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
        ),
        child: Text(_notice!, style: const TextStyle(color: Colors.white, fontSize: 12)),
      );

  Widget _playfield() {
    final cols = _layout?.cols ?? 6;
    final rows = _layout?.rows ?? 5;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          _HeroPortrait(mood: _heroMood),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkyfireChargeMeter(charge: _skyfireCharge),
              const Spacer(),
              _sideStat('SEQUENCE\nWIN', _sequenceWin.round().toString(), _cyan, alignEnd: true),
            ],
          ),
          Row(
            children: [
              Text(
                'TUMBLES $_tumbleCount',
                style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                'SHARDS $_starShards',
                style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: AetherfallGrid(
                cols: cols,
                rows: rows,
                grid: _displayGrid,
                highlighted: _highlighted,
                clearing: _clearing,
                chargeValues: _chargeValues,
                art: _art,
              ),
            ),
          ),
          if (_inBonus)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: BonusHud(
                tumblesLeft: _bonusTumblesLeft,
                chargeBank: _bonusChargeBank,
                locks: _bonusLocks,
                lockTarget: _layout?.constellationLockTarget ?? 3,
                art: _art,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sideStat(String label, String value, Color color, {required bool alignEnd}) => Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1, height: 1.2),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _bannerOverlay() {
    final text = _transientBanner!;
    Widget content;
    if (text == 'starburst') {
      content = const StarburstBanner();
    } else if (text.startsWith('math:')) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _bgTop.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cyan.withValues(alpha: 0.5)),
        ),
        child: Text(
          text.substring(5),
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: _mint.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(color: _bgBottom, fontWeight: FontWeight.w900, fontSize: 13),
        ),
      );
    }
    return Positioned(
      top: 90,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 200),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final canPlay = !_busy && !_loading && _layout != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              _betControl(canPlay),
              const SizedBox(width: 10),
              Expanded(child: _igniteButton(canPlay)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_auto)
                _pillButton('STOP', Colors.redAccent, _stopAuto)
              else
                SizedBox(
                  width: 160,
                  child: _SkinnedButton(
                    asset: 'btn_auto',
                    tint: _copper,
                    height: 38,
                    enabled: canPlay,
                    onTap: () {
                      setState(() {
                        _auto = true;
                        _stopRequested = false;
                      });
                      unawaited(_ignite());
                    },
                    child: const Text(
                      'AUTO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _betControl(bool enabled) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 20),
              onPressed: enabled ? () => _stepBet(-1) : null,
            ),
            SizedBox(
              width: 56,
              child: Text(
                '$_bet',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 20),
              onPressed: enabled ? () => _stepBet(1) : null,
            ),
          ],
        ),
      );

  Widget _igniteButton(bool enabled) => _SkinnedButton(
        asset: 'btn_ignite',
        tint: _cyan,
        height: 52,
        enabled: enabled,
        onTap: _ignite,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: _bgBottom),
              )
            : const Text(
                'IGNITE',
                style: TextStyle(
                  color: _bgBottom,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: 1.5,
                ),
              ),
      );

  Widget _pillButton(String label, Color color, VoidCallback? onTap) => SizedBox(
        width: 160,
        height: 38,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color.withValues(alpha: onTap == null ? 0.3 : 0.8)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null ? color.withValues(alpha: 0.4) : color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ),
      );
}

/// The Skyfire Charge readout, drawn inside the delivered meter frame.
///
/// The fill is deliberately not a percentage of anything real — charge is
/// uncapped and a sequence can bank far more than a barful — so it eases toward
/// full on a curve that keeps moving without ever pretending to be a limit. The
/// exact figure is printed on top, which is the number that actually matters.
class _SkyfireChargeMeter extends StatelessWidget {
  const _SkyfireChargeMeter({required this.charge});

  final int charge;

  /// 0 at no charge, approaching 1 as charge climbs. 60% is the halfway point.
  double get _fill => 1 - math.exp(-charge / 60.0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SKYFIRE\nCHARGE',
            style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1, height: 1.2),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 34,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Fill sits under the frame so the frame's trim caps its ends.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                  child: LayoutBuilder(
                    builder: (context, c) => AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOut,
                      width: c.maxWidth * _fill,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_ember, Color(0xFFFFD08A)]),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(color: _ember.withValues(alpha: 0.55), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/aetherfall/meter_frame.png',
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '+$charge%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: _bgBottom, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A control skinned with one of the delivered pill PNGs.
///
/// The label is drawn by the app rather than baked into the art, so it stays
/// crisp and translatable. If the PNG is missing the button falls back to a
/// tinted rounded rectangle, so the screen is never left without a control.
class _SkinnedButton extends StatelessWidget {
  const _SkinnedButton({
    required this.asset,
    required this.tint,
    required this.height,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final String asset;
  final Color tint;
  final double height;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(height / 2),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/aetherfall/$asset.png',
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(height / 3),
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small animated observatory-window portrait above the playfield: Ilyra,
/// Warden of the Skyfire, whose expression follows the round. Falls back to a
/// mood-tinted painted glyph if the artwork is missing from the bundle — the
/// same graceful-fallback pattern as [SymbolTile].
class _HeroPortrait extends StatelessWidget {
  const _HeroPortrait({required this.mood});
  final String mood;

  @override
  Widget build(BuildContext context) {
    final color = switch (mood) {
      'win' => _mint,
      'bonus' => _ember,
      _ => _cyan,
    };
    final icon = switch (mood) {
      'win' => Icons.auto_awesome_rounded,
      'bonus' => Icons.local_fire_department_rounded,
      _ => Icons.person_outline_rounded,
    };
    final asset = switch (mood) {
      'win' => 'hero_portrait_win',
      'bonus' => 'hero_portrait_bonus',
      _ => 'hero_portrait_idle',
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.06)]),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.6),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 14)],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/aetherfall/$asset.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Icon(icon, color: color, size: 26),
        ),
      ),
    );
  }
}

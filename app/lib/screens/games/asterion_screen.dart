import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/asterion_repository.dart';
import 'asterion_art.dart';
import 'asterion_board.dart';
import 'asterion_celebration.dart';
import 'asterion_fairness.dart';
import 'asterion_help.dart';
import 'asterion_sfx.dart';
import 'asterion_trial.dart';

const _betSteps = [20, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 20000];

/// أستيريون — Citadel of Asterion.
///
/// Original fictional pay-anywhere / tumbling game — see
/// ASTERION_ARTWORK_BRIEF.md at the repo root for the creative-distinction
/// notes and every art prompt.
///
/// Everything that decides a symbol, a tumble, a Storm Orb value or a payout is
/// server-side (backend/src/services/asterion.service.ts). This screen requests
/// one fully-resolved spin per tap and replays its frames — it never decides an
/// outcome, and the totals it shows are the server's, not a re-computation.
class AsterionScreen extends StatefulWidget {
  const AsterionScreen({super.key});

  @override
  State<AsterionScreen> createState() => _AsterionScreenState();
}

class _AsterionScreenState extends State<AsterionScreen> with TickerProviderStateMixin {
  final _repo = AsterionRepository();
  final _sfx = AsterionSfx();

  late final AnimationController _sky = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  AsterionLayout? _layout;
  AsterionFairness? _fairness;
  int _balance = 0;
  int _bet = 100;

  bool _loading = true;
  bool _busy = false;
  String? _notice;

  bool _muted = false;
  double _volume = 0.8;
  bool _reducedMotion = false;
  bool _highContrast = false;
  bool _turbo = false;

  bool _auto = false;
  bool _stopRequested = false;

  /// Spins played this visit. Drives the session reminder, which is a nudge to
  /// take a break, not a limit — it never blocks play.
  int _spinsThisSession = 0;
  int _lastReminderAt = 0;
  static const _reminderEvery = 50;

  static const _prefsMuted = 'asterion_muted';
  static const _prefsVolume = 'asterion_volume';
  static const _prefsMotion = 'asterion_reduced_motion';
  static const _prefsContrast = 'asterion_high_contrast';
  static const _prefsTurbo = 'asterion_turbo';
  static const _prefsBet = 'asterion_bet';

  // ── Board state ──────────────────────────────────────────────────────────
  List<String?> _grid = List<String?>.filled(30, null);
  Map<int, int> _orbs = {};
  Set<int> _highlighted = {};
  Set<int> _clearing = {};
  bool _orbsCollected = false;

  // ── HUD state ────────────────────────────────────────────────────────────
  double _sequenceWin = 0;
  int _sequenceMultiplier = 0;
  int _tumbles = 0;
  int _lastPaid = 0;

  bool _inTrial = false;
  int _trialSpinsLeft = 0;
  int _trialSpinNumber = 0;
  int _trialMeter = 0;

  /// Recent results, newest first — seeded from the server and extended
  /// locally as spins settle, so the strip is honest without a second request.
  List<AsterionSpinRecord> _history = const [];

  GuardianMood _mood = GuardianMood.calm;
  double _charge = 0;
  String? _banner;

  // ── Overlays ─────────────────────────────────────────────────────────────
  bool _showTrialTransition = false;
  int _transitionCrests = 4;
  Completer<void>? _transitionCompleter;

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
    _sky.dispose();
    _sfx.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _restoreSettings();
    try {
      final state = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _layout = state.layout;
        _balance = state.balance;
        _fairness = state.fairness;
        _history = state.history;
        _bet = _bet.clamp(state.layout.minBet, state.layout.maxBet);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notice = e is AsterionException ? e.message : 'تعذر تحميل اللعبة';
      });
    }
  }

  Future<void> _restoreSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _muted = prefs.getBool(_prefsMuted) ?? false;
        _volume = prefs.getDouble(_prefsVolume) ?? 0.8;
        _reducedMotion = prefs.getBool(_prefsMotion) ?? false;
        _highContrast = prefs.getBool(_prefsContrast) ?? false;
        _turbo = prefs.getBool(_prefsTurbo) ?? false;
        _bet = prefs.getInt(_prefsBet) ?? 100;
        _sfx.enabled = !_muted;
        _sfx.volume = _volume;
      });
    } catch (_) {
      // Settings are a convenience; play must never depend on them loading.
    }
  }

  Future<void> _persist(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) await prefs.setBool(key, value);
      if (value is double) await prefs.setDouble(key, value);
      if (value is int) await prefs.setInt(key, value);
    } catch (_) {}
  }

  // ── Betting ──────────────────────────────────────────────────────────────

  void _stepBet(int direction) {
    if (_busy) return;
    final min = _layout?.minBet ?? 20;
    final max = _layout?.maxBet ?? 20000;
    final steps = _betSteps.where((s) => s >= min && s <= max).toList();
    var i = steps.indexOf(_bet);
    if (i < 0) {
      i = steps.indexWhere((s) => s >= _bet);
      if (i < 0) i = steps.length - 1;
    }
    final next = (i + direction).clamp(0, steps.length - 1);
    if (steps[next] == _bet) return;
    _sfx.click();
    setState(() => _bet = steps[next]);
    _persist(_prefsBet, _bet);
  }

  // ── Spinning ─────────────────────────────────────────────────────────────

  Future<void> _spin() async {
    if (_busy || _loading || _layout == null) return;
    if (_bet > _balance) {
      _sfx.error();
      setState(() {
        _notice = 'رصيدك لا يكفي';
        _auto = false;
      });
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
      _sequenceWin = 0;
      _sequenceMultiplier = 0;
      _tumbles = 0;
      _lastPaid = 0;
      _highlighted = {};
      _clearing = {};
      _orbs = {};
      _orbsCollected = false;
      _mood = GuardianMood.attentive;
      _charge = 0;
    });
    _sfx.spin();

    AsterionSpinResponse response;
    try {
      response = await _repo.spin(amount: _bet);
    } catch (e) {
      _sfx.error();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _auto = false;
        _mood = GuardianMood.calm;
        _notice = e is AsterionException ? e.message : 'تعذر تنفيذ الجولة';
      });
      return;
    }

    // The balance already reflects the settled spin; showing it before the
    // replay would spoil the result, so it is applied when the replay ends.
    await _playSpin(response.spin);
    if (!mounted) return;

    setState(() {
      _balance = response.balance;
      _fairness = response.fairness;
      _busy = false;
      _spinsThisSession++;
      _mood = GuardianMood.calm;
      _charge = 0;
      _history = [
        AsterionSpinRecord(
          nonce: response.fairness.nonce - 1,
          bet: response.spin.bet,
          grandTotal: response.spin.grandTotal,
          trialTriggered: response.spin.trialTriggered,
          tier: response.spin.tier,
          at: DateTime.now().millisecondsSinceEpoch,
        ),
        ..._history.take(19),
      ];
    });

    if (_spinsThisSession - _lastReminderAt >= _reminderEvery) {
      _lastReminderAt = _spinsThisSession;
      setState(() => _notice = 'لعبت $_spinsThisSession جولة في هذه الجلسة');
    }

    if (_auto && !_stopRequested && mounted) {
      if (_bet > _balance) {
        setState(() {
          _auto = false;
          _notice = 'تم إيقاف اللعب التلقائي — الرصيد غير كافٍ';
        });
        return;
      }
      await _wait(420);
      if (mounted && _auto && !_stopRequested) unawaited(_spin());
    } else {
      _stopRequested = false;
    }
  }

  void _stopAuto() {
    _sfx.click();
    setState(() {
      _auto = false;
      _stopRequested = true;
    });
  }

  /// Replays a spin the server has already resolved. Nothing here computes a
  /// payout: every number shown comes off the frame it is drawn from.
  Future<void> _playSpin(AsterionSpin spin) async {
    setState(() {
      _grid = List<String?>.from(spin.initialGrid);
      _orbs = {for (final o in spin.initialOrbs) o.index: o.value};
      _orbsCollected = false;
    });
    _sfx.deal();
    if (spin.initialOrbs.isNotEmpty) _sfx.orbLand();
    await _wait(400);

    if (spin.crestsInitial >= 2 && !spin.trialTriggered) {
      // A near miss is worth a beat of attention — but only a beat.
      setState(() => _mood = GuardianMood.attentive);
    }

    var transitionShown = false;
    var step = 0;

    for (final frame in spin.frames) {
      if (frame.phase == 'trial' && frame.spinNumber == 1 && !transitionShown) {
        transitionShown = true;
        _sfx.trialStart();
        await _enterTrial(spin.crestsInitial, spin.trialSpins);
      }

      if (frame.spinNumber != null) {
        // A new free spin: the board and the sequence counters start over, the
        // meter does not.
        setState(() {
          _inTrial = true;
          _trialSpinNumber = frame.spinNumber!;
          _trialSpinsLeft = frame.spinsLeftAfter ?? _trialSpinsLeft;
          _sequenceWin = 0;
          _sequenceMultiplier = 0;
        });
        step = 0;
        if ((frame.retriggerAdded ?? 0) > 0) {
          _sfx.crest();
          await _flashBanner('+${frame.retriggerAdded} لفّات');
        }
      }

      setState(() {
        _grid = List<String?>.from(frame.grid);
        _orbs = {for (final o in frame.orbCells) o.index: o.value};
        _highlighted = {};
        _clearing = {};
        _orbsCollected = false;
      });
      await _wait(170);

      if (frame.hadWin) {
        final amount = frame.wins.fold<double>(0, (a, w) => a + w.amount);
        setState(() {
          _highlighted = frame.winningCells.toSet();
          _sequenceWin += amount;
          _tumbles++;
          _mood = GuardianMood.exultant;
        });
        _sfx.tumble(step++);
        await _wait(620);

        setState(() => _clearing = frame.winningCells.toSet());
        _sfx.burst();
        await _wait(230);

        setState(() {
          final next = List<String?>.from(_grid);
          for (final i in frame.winningCells) {
            next[i] = null;
          }
          _grid = next;
          _highlighted = {};
          _clearing = {};
        });
        _sfx.refill();
        await _wait(200);
        continue;
      }

      // A frame with no win closes the sequence — this is where the orbs are
      // collected and the sequence is actually paid.
      if (frame.endsSequence) {
        final multiplier = frame.sequenceMultiplier ?? 0;
        final won = (frame.sequenceWin ?? 0) > 0;

        if (won && frame.orbCells.isNotEmpty) {
          setState(() {
            _mood = GuardianMood.strike;
            _charge = 1;
          });
          _sfx.orbCollect();
          await _wait(420);
          setState(() => _orbsCollected = true);
          await _wait(260);
        }

        setState(() {
          _sequenceMultiplier = multiplier;
          if (frame.phase == 'trial') {
            _trialMeter = frame.trialMultiplierAfter ?? _trialMeter;
          }
          _charge = 0;
          if ((frame.sequenceTotal ?? 0) > 0) _lastPaid = frame.sequenceTotal!;
        });

        // Never hide the arithmetic: raw win × the multiplier that applied.
        if (won && multiplier > 0) {
          await _flashBanner(
            '${(frame.sequenceWin ?? 0).round()} × ${multiplier}x = ${frame.sequenceTotal ?? 0}',
          );
        } else if (won) {
          await _wait(260);
        }

        // The meter has been showing the raw symbol win; once the multiplier
        // has been applied it must show what was actually paid, or a 35x
        // sequence settles displaying a thirty-fifth of its own payout.
        if (won) {
          setState(() => _sequenceWin = (frame.sequenceTotal ?? 0).toDouble());
        }

        setState(() => _mood = won ? GuardianMood.exultant : GuardianMood.calm);
      }
    }

    if (spin.trialTriggered) {
      setState(() => _mood = GuardianMood.trial);
      _sfx.trialEnd();
      await _showTrialSummary(spin);
      setState(() {
        _inTrial = false;
        _trialSpinsLeft = 0;
        _trialSpinNumber = 0;
        _trialMeter = 0;
      });
    }

    if (spin.capped) {
      await _flashBanner('بلغت الجولة سقف ${_layout?.maxWinMultiple ?? 5000}x');
    }

    if (spin.tier != null) {
      _sfx.celebration(spin.tier!);
      await _showCelebration(spin.tier!, spin.grandTotal, spin.bet);
    }
  }

  Future<void> _wait(int ms) {
    var scaled = ms;
    if (_turbo) scaled = (scaled * 0.45).round();
    if (_reducedMotion) scaled = (scaled * 0.5).round();
    return Future.delayed(Duration(milliseconds: scaled));
  }

  Future<void> _flashBanner(String text) async {
    setState(() => _banner = text);
    await _wait(1000);
    if (mounted) setState(() => _banner = null);
  }

  Future<void> _enterTrial(int crests, int spins) {
    final completer = Completer<void>();
    _transitionCompleter = completer;
    setState(() {
      _transitionCrests = crests;
      _trialSpinsLeft = spins;
      _showTrialTransition = true;
    });
    return completer.future;
  }

  void _onTransitionDone() {
    final c = _transitionCompleter;
    if (c == null || c.isCompleted) return;
    setState(() => _showTrialTransition = false);
    c.complete();
  }

  Future<void> _showCelebration(String tier, int amount, int bet) {
    final completer = Completer<void>();
    _celebrationCompleter = completer;
    setState(() {
      _celebrationTier = tier;
      _celebrationAmount = amount;
    });
    return completer.future;
  }

  void _onCelebrationDone() {
    final c = _celebrationCompleter;
    if (c == null || c.isCompleted) return;
    setState(() => _celebrationTier = null);
    c.complete();
  }

  Future<void> _showTrialSummary(AsterionSpin spin) {
    if (!mounted) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => TrialSummarySheet(
        totalCoins: spin.trialTotal,
        spins: spin.trialSpins,
        retriggers: spin.trialRetriggers,
        finalMultiplier: spin.trialMultiplier,
      ),
    );
  }

  // ── Sheets ───────────────────────────────────────────────────────────────

  void _openHelp() {
    final layout = _layout;
    if (layout == null) return;
    _sfx.click();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AsterionHelpSheet(layout: layout),
    );
  }

  void _openFairness() {
    final fair = _fairness;
    if (fair == null) return;
    _sfx.click();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AsterionFairnessSheet(repo: _repo, fairness: fair),
    );
  }

  void _openSettings() {
    _sfx.click();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF16204A), Color(0xFF070A1B)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'الإعدادات',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.volume_up_rounded, color: AsterionPalette.cyan, size: 18),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        activeColor: AsterionPalette.cyan,
                        onChanged: (v) {
                          setSheet(() => _volume = v);
                          setState(() {
                            _volume = v;
                            _sfx.volume = v;
                          });
                          _persist(_prefsVolume, v);
                        },
                      ),
                    ),
                  ],
                ),
                _toggle('كتم الصوت', 'يوقف كل المؤثرات فورًا', _muted, (v) {
                  setSheet(() => _muted = v);
                  setState(() {
                    _muted = v;
                    _sfx.enabled = !v;
                  });
                  _persist(_prefsMuted, v);
                }),
                _toggle('حركة أقل', 'يقصّر الأنيميشن ويوقف الجسيمات', _reducedMotion, (v) {
                  setSheet(() => _reducedMotion = v);
                  setState(() => _reducedMotion = v);
                  _persist(_prefsMotion, v);
                }),
                _toggle('تباين عالٍ', 'خلفية أغمق وحدود أوضح للرموز', _highContrast, (v) {
                  setSheet(() => _highContrast = v);
                  setState(() => _highContrast = v);
                  _persist(_prefsContrast, v);
                }),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_rounded, color: AsterionPalette.cyan),
                  title: const Text('العدالة المُثبتة', style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'تحقق من بذور الجولات',
                    style: TextStyle(color: AsterionPalette.muted, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openFairness();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AsterionPalette.cyan,
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AsterionPalette.muted, fontSize: 11.5),
        ),
      );

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AsterionPalette.nightDeep,
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sky,
                builder: (_, __) => CitadelBackdrop(
                  drift: _reducedMotion ? 0.2 : _sky.value,
                  stormy: _inTrial,
                ),
              ),
            ),
            SafeArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AsterionPalette.cyan))
                  : Column(
                      children: [
                        _topBar(),
                        if (_notice != null) _noticeBar(),
                        Expanded(child: _playfield()),
                        _bottomBar(),
                      ],
                    ),
            ),
            if (_banner != null) _bannerOverlay(),
            if (_showTrialTransition)
              Positioned.fill(
                child: TrialTransition(
                  spins: _layout?.trialSpins ?? 15,
                  crests: _transitionCrests,
                  reducedMotion: _reducedMotion,
                  onDone: _onTransitionDone,
                ),
              ),
            if (_celebrationTier != null)
              Positioned.fill(
                child: AsterionCelebration(
                  tier: _celebrationTier!,
                  amount: _celebrationAmount,
                  bet: _bet,
                  reducedMotion: _reducedMotion,
                  onDone: _onCelebrationDone,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white70),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Text(
              'أستيريون',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            _coinBadge(),
            IconButton(
              visualDensity: VisualDensity.compact,
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
                _persist(_prefsMuted, _muted);
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.help_outline_rounded, color: Colors.white70, size: 20),
              onPressed: _openHelp,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.settings_rounded, color: Colors.white70, size: 20),
              onPressed: _openSettings,
            ),
          ],
        ),
      );

  Widget _coinBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.black.withValues(alpha: 0.4),
          border: Border.all(color: AsterionPalette.amber.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on_rounded, color: AsterionPalette.amber, size: 15),
            const SizedBox(width: 5),
            Text(
              '$_balance',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  Widget _noticeBar() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AsterionPalette.magenta.withValues(alpha: 0.18),
          border: Border.all(color: AsterionPalette.magenta.withValues(alpha: 0.55)),
        ),
        child: Text(
          _notice!,
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
        ),
      );

  Widget _playfield() {
    final cols = _layout?.cols ?? 6;
    final rows = _layout?.rows ?? 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: LayoutBuilder(
        builder: (context, box) {
          // The guardian keeps the right-hand stage in landscape, where there is
          // width to spare, and moves beside the meters in portrait so he never
          // steals height from the board.
          final wide = box.maxWidth > box.maxHeight * 1.25;
          final board = Center(
            child: AsterionBoard(
              cols: cols,
              rows: rows,
              grid: _grid,
              orbs: _orbs,
              highlighted: _highlighted,
              clearing: _clearing,
              collectedOrbs: _orbsCollected,
              highContrast: _highContrast,
              reducedMotion: _reducedMotion,
            ),
          );

          if (wide) {
            return Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [_meters(), const SizedBox(height: 6), board],
                  ),
                ),
                Expanded(
                  child: Guardian(mood: _mood, charge: _charge),
                ),
              ],
            );
          }

          // The board is fixed by its 6:5 aspect, so on a tall phone the slack
          // goes to the guardian rather than leaving a dead band under the
          // grid — which is exactly what the first layout did.
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _meters()),
                    SizedBox(
                      width: box.maxWidth * 0.42,
                      child: Guardian(mood: _mood, charge: _charge),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              board,
              if (_inTrial) _trialHud(),
              if (!_inTrial && _history.isNotEmpty) _historyStrip(),
            ],
          );
        },
      ),
    );
  }

  Widget _meters() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stat(
            'ربح الجولة',
            _sequenceWin > 0 ? '${_sequenceWin.round()}' : (_lastPaid > 0 ? '$_lastPaid' : '—'),
            AsterionPalette.cyanPale,
          ),
          const SizedBox(height: 6),
          _stat(
            _inTrial ? 'مضاعف التجارب' : 'المضاعف',
            _inTrial
                ? '${_trialMeter}x'
                : (_sequenceMultiplier > 0 ? '${_sequenceMultiplier}x' : '—'),
            AsterionPalette.magenta,
          ),
          const SizedBox(height: 6),
          _stat('التساقطات', '$_tumbles', AsterionPalette.muted),
        ],
      );

  Widget _stat(String label, String value, Color colour) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.8),
          ),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: colour,
              fontSize: 20,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );

  Widget _trialHud() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AsterionPalette.cyan.withValues(alpha: 0.12),
          border: Border.all(color: AsterionPalette.cyan.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'تجارب السماء',
              style: TextStyle(
                color: AsterionPalette.cyanPale,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'لفة $_trialSpinNumber · باقٍ $_trialSpinsLeft',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            Text(
              '${_trialMeter}x',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: AsterionPalette.magenta,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );

  /// The last few results, newest at the leading edge. A losing spin shows as a
  /// dash rather than a zero: a column of zeroes reads like a fault.
  Widget _historyStrip() => Container(
        height: 34,
        margin: const EdgeInsets.only(top: 8),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _history.length > 12 ? 12 : _history.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final r = _history[i];
            final won = r.grandTotal > 0;
            final colour = r.trialTriggered
                ? AsterionPalette.magenta
                : (won ? AsterionPalette.tide : AsterionPalette.silverDeep);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: colour.withValues(alpha: 0.14),
                border: Border.all(color: colour.withValues(alpha: 0.6)),
              ),
              child: Text(
                won ? '${r.grandTotal}' : '—',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: won ? Colors.white : AsterionPalette.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
      );

  Widget _bannerOverlay() => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black.withValues(alpha: 0.72),
                border: Border.all(color: AsterionPalette.cyan.withValues(alpha: 0.7)),
              ),
              child: Text(
                _banner!,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: AsterionPalette.cyan, blurRadius: 14)],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _bottomBar() {
    final canPlay = !_busy && !_loading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          _betControl(canPlay),
          const Spacer(),
          _pill(
            'تسريع',
            _turbo,
            canPlay || _busy
                ? () {
                    _sfx.click();
                    setState(() => _turbo = !_turbo);
                    _persist(_prefsTurbo, _turbo);
                  }
                : null,
          ),
          const SizedBox(width: 6),
          _pill(
            'تلقائي',
            _auto,
            () {
              if (_auto) {
                _stopAuto();
                return;
              }
              _sfx.click();
              setState(() {
                _auto = true;
                _stopRequested = false;
              });
              if (!_busy) unawaited(_spin());
            },
          ),
          const SizedBox(width: 10),
          _spinButton(canPlay),
        ],
      ),
    );
  }

  Widget _betControl(bool enabled) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: AsterionPalette.silverDeep),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.remove_rounded, color: Colors.white70, size: 18),
              onPressed: enabled ? () => _stepBet(-1) : null,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('الرهان', style: TextStyle(color: Colors.white38, fontSize: 9)),
                Text(
                  '$_bet',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.add_rounded, color: Colors.white70, size: 18),
              onPressed: enabled ? () => _stepBet(1) : null,
            ),
          ],
        ),
      );

  Widget _pill(String label, bool active, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: active
                ? AsterionPalette.cyan.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.4),
            border: Border.all(
              color: active ? AsterionPalette.cyan : AsterionPalette.silverDeep,
              width: active ? 1.8 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AsterionPalette.cyanPale : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

  Widget _spinButton(bool enabled) => Semantics(
        button: true,
        label: enabled ? 'ابدأ الجولة' : 'الجولة قيد التنفيذ',
        child: GestureDetector(
          onTap: enabled ? _spin : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 76,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: enabled
                    ? [AsterionPalette.cyan, AsterionPalette.cyanDeep]
                    : [AsterionPalette.silverDeep, AsterionPalette.ink],
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AsterionPalette.cyan.withValues(alpha: 0.5),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text(
                      'ابدأ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ),
      );
}

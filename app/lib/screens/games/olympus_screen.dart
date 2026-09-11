import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/auth_provider.dart';
import '../../repositories/olympus_repository.dart';
import 'olympus_bonus.dart';
import 'olympus_celebration.dart';
import 'olympus_fairness.dart';
import 'olympus_grid.dart';
import 'olympus_help.dart';
import 'olympus_sfx.dart';
import 'olympus_strings.dart';
import 'olympus_symbols.dart';
import 'olympus_zeus.dart';

const _gold = Color(0xFFE3B84A);
const _boltBlue = Color(0xFF9FD8FF);
const _violetDeep = Color(0xFF12052B);
const _violetTop = Color(0xFF3A1A72);
const _panel = Color(0xCC1E0B44);

const _betSteps = [20, 50, 100, 200, 500, 1000, 2500, 5000, 10000, 20000];

/// بوابات أوليمبوس — Gates of Olympus.
///
/// A 6×5 pay-anywhere tumbling game above the clouds of Mount Olympus, with
/// Zeus at the right of the board, lightning multipliers that fall with gravity
/// and are collected only when the tumbles stop, and a 15-spin feature whose
/// multiplier meter never resets while it runs.
///
/// Everything that decides a symbol, a tumble, a multiplier, the feature or a
/// payout is server-side (backend/src/services/olympus.service.ts). This screen
/// asks for one fully-resolved spin per tap and replays the frames it is handed
/// — it never decides an outcome, and STOP only skips animation, never math.
///
/// Note on the name: "Gates of Olympus" is a Pragmatic Play trademark. Zeus,
/// Olympus and every mechanic here are free to use; the title is not ours. It
/// lives in exactly one place — [OlympusStrings.title] — so changing it is a
/// two-line edit rather than a hunt.
class OlympusScreen extends ConsumerStatefulWidget {
  const OlympusScreen({super.key, this.repository});

  /// Overrides the live backend. Only the dev harness passes this — it lets
  /// lib/dev/olympus_play.dart drive the real screen, the real replay loop and
  /// the real widgets from a recorded spin, with no server and no login.
  final OlympusRepository? repository;

  @override
  ConsumerState<OlympusScreen> createState() => _OlympusScreenState();
}

class _OlympusScreenState extends ConsumerState<OlympusScreen> {
  late final OlympusRepository _repo = widget.repository ?? OlympusRepository();
  final _sfx = OlympusSfx();

  OlympusLayout? _layout;
  OlympusArt? _art;
  OlympusFairness? _fairness;

  int _balance = 0;
  int _bet = 100;

  bool _loading = true;
  bool _busy = false;
  String? _notice;

  // ── Settings ─────────────────────────────────────────────────────────────
  bool _muted = false;
  double _volume = 0.8;
  bool _turbo = false;
  bool _reducedMotion = false;
  bool _reducedFlash = false;
  bool _highContrast = false;
  bool _leftHanded = false;

  static const _prefsMuted = 'olympus_muted';
  static const _prefsVolume = 'olympus_volume';
  static const _prefsTurbo = 'olympus_turbo';
  static const _prefsMotion = 'olympus_reduced_motion';
  static const _prefsFlash = 'olympus_reduced_flash';
  static const _prefsContrast = 'olympus_high_contrast';
  static const _prefsLeftHanded = 'olympus_left_handed';

  /// Rounds played this visit. Drives the break reminder, which is a nudge and
  /// never a limit — it does not block play.
  int _spinsThisSession = 0;
  int _lastReminderAt = 0;
  static const _reminderEvery = 50;

  bool _auto = false;
  bool _stopRequested = false;

  /// Set while STOP is settling the current round: every wait returns at once
  /// and the celebration does not dwell. The result is untouched.
  bool _skipping = false;

  // ── Board state ──────────────────────────────────────────────────────────
  List<String?> _displayGrid = List<String?>.filled(30, null);
  Set<int> _highlighted = {};
  Set<int> _clearing = {};
  Map<int, int> _multValues = {};

  // ── HUD state ────────────────────────────────────────────────────────────
  double _sequenceWin = 0;
  int _roundWin = 0;
  int _tumbleCount = 0;
  int _pendingMultiplier = 0;
  ZeusMood _mood = ZeusMood.idle;

  bool _inBonus = false;
  int _bonusSpinsLeft = 0;
  int _bonusMeter = 0;

  String? _banner;

  // ── Overlays ─────────────────────────────────────────────────────────────
  String? _celebrationTier;
  int _celebrationAmount = 0;
  bool _celebrationCapped = false;
  /// The stake the celebrated round was dealt at. Same as [_bet] in normal
  /// play, but the two can differ when a recorded round is replayed.
  int _celebrationBet = 0;
  Completer<void>? _celebrationCompleter;

  bool _bonusIntroVisible = false;
  int _bonusIntroSpins = 0;
  int _bonusIntroScatters = 0;
  Completer<void>? _bonusIntroCompleter;

  /// Lightning currently in flight, as (target cell, 0→1 progress).
  int? _strikeTarget;
  double _strikeProgress = 0;

  @override
  void initState() {
    super.initState();
    // The brief asks for landscape-first play. The rest of the app is portrait,
    // so the preference is set on entry and released on exit rather than
    // globally — a player who leaves the game gets their normal app back.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],);
    _boot();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _sfx.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _restoreSettings();
    // Artwork is optional: a missing file leaves a painted fallback, so a slow
    // or failed load must not hold the game up.
    unawaited(OlympusArt.load().then((art) {
      if (mounted) setState(() => _art = art);
    },),);
    await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      final state = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _layout = state.layout;
        _balance = state.balance;
        _fairness = state.fairness;
        _bet = _clampBet(_bet, state.layout);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notice = e is OlympusException ? e.message : '$e';
      });
    }
  }

  int _clampBet(int bet, OlympusLayout layout) {
    final steps = _betSteps.where((s) => s >= layout.minBet && s <= layout.maxBet).toList();
    if (steps.isEmpty) return layout.minBet;
    return steps.reduce((a, b) => (a - bet).abs() <= (b - bet).abs() ? a : b);
  }

  Future<void> _restoreSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _muted = prefs.getBool(_prefsMuted) ?? false;
        _volume = prefs.getDouble(_prefsVolume) ?? 0.8;
        _turbo = prefs.getBool(_prefsTurbo) ?? false;
        _reducedMotion = prefs.getBool(_prefsMotion) ?? false;
        _reducedFlash = prefs.getBool(_prefsFlash) ?? false;
        _highContrast = prefs.getBool(_prefsContrast) ?? false;
        _leftHanded = prefs.getBool(_prefsLeftHanded) ?? false;
        _sfx.enabled = !_muted;
        _sfx.volume = _volume;
      });
    } catch (_) {
      // Defaults are fine if storage is unavailable.
    }
  }

  Future<void> _persist(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) await prefs.setBool(key, value);
      if (value is double) await prefs.setDouble(key, value);
    } catch (_) {}
  }

  // ── Bet ──────────────────────────────────────────────────────────────────

  void _stepBet(int direction) {
    final layout = _layout;
    if (layout == null || _busy) return;
    final steps =
        _betSteps.where((s) => s >= layout.minBet && s <= layout.maxBet).toList();
    if (steps.isEmpty) return;
    var i = steps.indexOf(_bet);
    if (i < 0) i = 0;
    final next = (i + direction).clamp(0, steps.length - 1);
    if (steps[next] == _bet) return;
    setState(() => _bet = steps[next]);
    _sfx.click();
  }

  // ── Spin orchestration ───────────────────────────────────────────────────

  Future<void> _spin() async {
    if (_busy || _loading || _layout == null) return;
    final s = OlympusStrings.of(context);
    if (_bet > _balance) {
      setState(() => _notice = s.notEnoughCoins);
      _sfx.error();
      return;
    }

    setState(() {
      _busy = true;
      _skipping = false;
      _notice = null;
      _sequenceWin = 0;
      _roundWin = 0;
      _tumbleCount = 0;
      _pendingMultiplier = 0;
      _highlighted = {};
      _clearing = {};
      _mood = ZeusMood.watching;
      // Charge locally so the balance moves on the tap rather than after the
      // round trip; the authoritative figure replaces it when the spin lands.
      _balance -= _bet;
    });
    _sfx.spin();

    OlympusSpinResponse response;
    try {
      response = await _repo.spin(amount: _bet);
    } catch (e) {
      _sfx.error();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _balance += _bet; // The server refused, so nothing was staked.
        _mood = ZeusMood.idle;
        _notice = e is OlympusException ? e.message : s.spinFailed;
        _auto = false;
      });
      return;
    }

    await _playSpin(response.spin);
    if (!mounted) return;

    setState(() {
      _balance = response.balance;
      _fairness = response.fairness;
      _busy = false;
      _skipping = false;
      _spinsThisSession++;
    });

    if (_spinsThisSession - _lastReminderAt >= _reminderEvery) {
      _lastReminderAt = _spinsThisSession;
      if (mounted) setState(() => _notice = s.sessionReminder(_spinsThisSession));
    }

    if (_auto && !_stopRequested && mounted) {
      if (_bet > _balance) {
        setState(() {
          _auto = false;
          _notice = s.autoStoppedLowBalance;
        });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 420));
      if (mounted && _auto && !_stopRequested) unawaited(_spin());
    } else {
      _stopRequested = false;
    }
  }

  /// STOP: settle the round now.
  ///
  /// Only skips animation — the spin was fully resolved by the server before
  /// the first frame was drawn, so there is no outcome left to change here.
  void _stop() {
    if (_auto) {
      setState(() {
        _auto = false;
        _stopRequested = true;
      });
    }
    if (_busy) {
      setState(() => _skipping = true);
      _onCelebrationDone();
      _onBonusIntroDone();
    }
    _sfx.click();
  }

  /// Replays one fully-resolved spin, frame by frame.
  Future<void> _playSpin(OlympusSpin spin) async {
    // Captured before the first await: every banner below lands after one.
    final s = OlympusStrings.of(context);
    setState(() {
      _displayGrid = List<String?>.from(spin.initialGrid);
      _multValues = {for (final m in spin.initialMults) m.index: m.value};
    });
    _sfx.deal();

    if (spin.initialMults.isNotEmpty) _sfx.orbLanding();
    if (spin.scattersInitial > 0) _sfx.scatter();
    await _wait(420);

    var bonusIntroShown = false;
    var running = 0;

    for (final frame in spin.frames) {
      final isFree = frame.phase == 'free';

      // The feature opens on the first free frame, after base play resolved.
      if (isFree && !bonusIntroShown) {
        bonusIntroShown = true;
        setState(() {
          _mood = ZeusMood.bonus;
          _inBonus = true;
          _bonusMeter = 0;
          _bonusSpinsLeft = spin.freeSpins;
        });
        _sfx.bonusTransition();
        await _showBonusIntro(
          spins: _layout?.freeSpins ?? 15,
          scatters: spin.scattersInitial,
        );
      }

      // First frame of a free spin: update the counter, announce a retrigger.
      if (isFree && frame.spinNumber != null) {
        setState(() {
          _bonusSpinsLeft = frame.spinsLeftAfter ?? _bonusSpinsLeft;
          _sequenceWin = 0;
        });
        if ((frame.retriggerAdded ?? 0) > 0) {
          _sfx.retrigger();
          await _flashBanner(s.retriggerAdded(frame.retriggerAdded!));
        }
      }

      setState(() {
        _displayGrid = List<String?>.from(frame.grid);
        _multValues = {for (final m in frame.multCells) m.index: m.value};
        _highlighted = {};
        _clearing = {};
      });
      await _wait(180);

      if (frame.hadWin) {
        final amount = frame.wins.fold<double>(0, (a, w) => a + w.amount);
        setState(() {
          _highlighted = frame.winningCells.toSet();
          _tumbleCount++;
          _sequenceWin += amount;
          _mood = ZeusMood.reacting;
        });
        _sfx.win();
        await _wait(620);

        setState(() => _clearing = frame.winningCells.toSet());
        _sfx.burst();
        await _wait(240);

        setState(() {
          final cleared = List<String?>.from(_displayGrid);
          for (final i in frame.winningCells) {
            cleared[i] = null;
          }
          _displayGrid = cleared;
          _highlighted = {};
          _clearing = {};
        });
        _sfx.tumble();
        await _wait(200);
      }

      // End of a cascade. Multipliers are collected here and nowhere else —
      // this is the moment the game's one confusing rule becomes visible, so it
      // gets its own beat even in turbo.
      if (frame.sequenceTotal != null) {
        final mults = frame.multCells;
        final paid = (frame.sequenceWin ?? 0) > 0;

        // Base play collects only on a winning cascade; inside the feature the
        // meter grows even on a dead board, which is what makes a long bonus
        // escalate.
        if (mults.isNotEmpty && (paid || isFree)) {
          await _collectMultipliers(mults, isFree: isFree);
        }

        if (isFree) {
          setState(() => _bonusMeter = frame.freeMultiplierAfter ?? _bonusMeter);
        }

        final total = frame.sequenceTotal ?? 0;
        if (total > 0) {
          running += total;
          setState(() {
            _roundWin = running;
            _mood = ZeusMood.reacting;
          });
          await _wait(360);
        }
        setState(() => _pendingMultiplier = 0);
      }
    }

    if (spin.freeTriggered) {
      setState(() => _mood = ZeusMood.bonus);
      _sfx.bonusSummary();
      await _showBonusSummary(spin, s);
      setState(() {
        _inBonus = false;
        _bonusSpinsLeft = 0;
      });
    }

    setState(() => _roundWin = spin.grandTotal);

    if (spin.tier != null) {
      setState(() => _mood = ZeusMood.reacting);
      _sfx.celebration(spin.tier!);
      await _showCelebration(spin.tier!, spin.grandTotal, spin.capped, spin.bet);
    }

    if (mounted) setState(() => _mood = ZeusMood.idle);
  }

  /// Zeus strikes each orb in turn, then the values are shown adding up.
  ///
  /// The count is deliberately *additive* on screen — the running total ticks
  /// 3 → 8 → 33 as each bolt lands — because "they add, they don't multiply" is
  /// the rule players most often get wrong, and watching it is more convincing
  /// than reading it in the help sheet.
  Future<void> _collectMultipliers(
    List<OlympusMultCell> mults, {
    required bool isFree,
  }) async {
    setState(() => _mood = ZeusMood.charging);
    await _wait(280);

    var running = 0;
    for (final m in mults) {
      running += m.value;
      setState(() {
        _mood = ZeusMood.striking;
        _strikeTarget = m.index;
      });
      _sfx.strike();

      // The bolt draws itself in over a handful of frames. Turbo shortens it,
      // reduced-motion collapses it to a single flash.
      if (!_reducedMotion && !_skipping) {
        const steps = 6;
        for (var i = 1; i <= steps; i++) {
          setState(() => _strikeProgress = i / steps);
          await _wait(38);
        }
      }

      setState(() {
        _strikeProgress = 0;
        _strikeTarget = null;
        _pendingMultiplier = running;
      });
      await _wait(200);
    }

    _sfx.collect();
    setState(() => _mood = ZeusMood.reacting);
    await _wait(340);
  }

  /// Every animation delay in the game goes through here, so turbo, reduced
  /// motion and STOP each have exactly one place to take effect.
  Future<void> _wait(int ms) {
    if (_skipping) return Future.value();
    var scale = 1.0;
    if (_turbo) scale *= 0.55;
    if (_reducedMotion) scale *= 0.4;
    return Future.delayed(Duration(milliseconds: (ms * scale).round()));
  }

  Future<void> _flashBanner(String text) async {
    setState(() => _banner = text);
    await _wait(1000);
    if (mounted) setState(() => _banner = null);
  }

  Future<void> _showBonusIntro({required int spins, required int scatters}) {
    if (_skipping) return Future.value();
    final completer = Completer<void>();
    _bonusIntroCompleter = completer;
    setState(() {
      _bonusIntroSpins = spins;
      _bonusIntroScatters = scatters;
      _bonusIntroVisible = true;
    });
    return completer.future;
  }

  void _onBonusIntroDone() {
    final c = _bonusIntroCompleter;
    if (c == null || c.isCompleted) return;
    setState(() => _bonusIntroVisible = false);
    c.complete();
  }

  Future<void> _showCelebration(String tier, int amount, bool capped, int bet) {
    if (_skipping) return Future.value();
    final completer = Completer<void>();
    _celebrationCompleter = completer;
    setState(() {
      _celebrationTier = tier;
      _celebrationAmount = amount;
      _celebrationCapped = capped;
      _celebrationBet = bet;
    });
    return completer.future;
  }

  void _onCelebrationDone() {
    final c = _celebrationCompleter;
    if (c == null || c.isCompleted) return;
    setState(() => _celebrationTier = null);
    c.complete();
  }

  Future<void> _showBonusSummary(OlympusSpin spin, OlympusStrings s) {
    if (!mounted || _skipping) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => OlympusBonusSummary(
        totalCoins: spin.freeTotal,
        spinsPlayed: spin.freeSpins,
        finalMultiplier: spin.freeMultiplier,
        retriggers: spin.freeRetriggers,
        strings: s,
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
      builder: (_) => OlympusHelpSheet(
        layout: layout,
        strings: OlympusStrings.of(context),
        art: _art,
      ),
    );
  }

  void _openFairness() {
    final fairness = _fairness;
    if (fairness == null) return;
    _sfx.click();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OlympusFairnessSheet(
        repo: _repo,
        fairness: fairness,
        strings: OlympusStrings.of(context),
      ),
    );
  }

  void _openSettings() {
    _sfx.click();
    final s = OlympusStrings.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Directionality(
          textDirection: s.direction,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A1258), _violetDeep],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: _gold, width: 1.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  s.settings,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                _volumeRow(s, setSheet),
                _toggle(s.turbo, '×1.5', _turbo, (v) {
                  setState(() => _turbo = v);
                  setSheet(() {});
                  _persist(_prefsTurbo, v);
                }),
                _toggle(s.reducedMotion, s.reducedMotionNote, _reducedMotion, (v) {
                  setState(() => _reducedMotion = v);
                  setSheet(() {});
                  _persist(_prefsMotion, v);
                }),
                _toggle(s.reducedFlash, s.reducedFlashNote, _reducedFlash, (v) {
                  setState(() => _reducedFlash = v);
                  setSheet(() {});
                  _persist(_prefsFlash, v);
                }),
                _toggle(s.highContrast, s.highContrastNote, _highContrast, (v) {
                  setState(() => _highContrast = v);
                  setSheet(() {});
                  _persist(_prefsContrast, v);
                }),
                _toggle(s.leftHanded, s.leftHandedNote, _leftHanded, (v) {
                  setState(() => _leftHanded = v);
                  setSheet(() {});
                  _persist(_prefsLeftHanded, v);
                }),
                const Divider(color: Colors.white12, height: 26),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_outlined, color: _boltBlue),
                  title: Text(
                    s.fairness,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openFairness();
                  },
                ),
                if (kDebugMode)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.science_outlined, color: Colors.orangeAccent),
                    title: const Text(
                      'QA scenarios',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Replays fixed seeds through the real math',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _openScenarios();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _volumeRow(OlympusStrings s, StateSetter setSheet) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white70,
              ),
              onPressed: () {
                setState(() {
                  _muted = !_muted;
                  _sfx.enabled = !_muted;
                });
                setSheet(() {});
                _persist(_prefsMuted, _muted);
              },
            ),
            Expanded(
              child: Slider(
                value: _volume,
                activeColor: _gold,
                onChanged: (v) {
                  setState(() {
                    _volume = v;
                    _sfx.volume = v;
                  });
                  setSheet(() {});
                },
                onChangeEnd: (v) => _persist(_prefsVolume, v),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                s.volume,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          ],
        ),
      );

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeThumbColor: _gold,
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );

  // ── Debug scenarios ──────────────────────────────────────────────────────

  /// Named deterministic scenarios, straight from `npm run sim:olympus`.
  ///
  /// These are real nonces on a fixed seed pair, replayed through the server's
  /// own `verifySpin` — so every one exercises the true math and the true
  /// animation path, and none of them touches a balance.
  static const _qaServerSeed =
      'olympus-qa-server-seed000000000000000000000000000000000000000000';
  static const _qaClientSeed = 'qa';
  static const _qaBet = 20;
  static const _scenarios = <String, int>{
    'A plain loss': 0,
    'One 8-symbol win': 20,
    'Two symbols paying at once': 120,
    'A 3+ tumble cascade': 9,
    'Three multipliers adding up': 236,
    'Four-scatter bonus trigger': 276,
    'Bonus retrigger (+5 spins)': 2598,
    'NICE_WIN': 9,
    'BIG_WIN': 543,
    'MEGA_WIN': 1525,
    'EPIC_WIN': 948,
  };

  void _openScenarios() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
        decoration: const BoxDecoration(
          color: _violetDeep,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: Colors.orangeAccent, width: 1.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'QA scenarios',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Fixed seeds, replayed through the server. No balance is charged '
              'or paid, and every one is skippable with STOP.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in _scenarios.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        entry.key,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      trailing: Text(
                        'nonce ${entry.value}',
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_runScenario(entry.value));
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runScenario(int nonce) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _skipping = false;
      _notice = null;
      _sequenceWin = 0;
      _roundWin = 0;
      _tumbleCount = 0;
      _pendingMultiplier = 0;
      _mood = ZeusMood.watching;
    });
    try {
      final spin = await _repo.verifySpin(
        serverSeed: _qaServerSeed,
        clientSeed: _qaClientSeed,
        nonce: nonce,
        bet: _qaBet,
      );
      await _playSpin(spin);
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _skipping = false;
          _mood = ZeusMood.idle;
        });
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = OlympusStrings.of(context);
    return Directionality(
      textDirection: s.direction,
      child: Scaffold(
        backgroundColor: _violetDeep,
        body: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_violetTop, _violetDeep],
            ),
            image: DecorationImage(
              image: AssetImage(
                _inBonus
                    ? 'assets/images/olympus/bg_olympus_bonus.png'
                    : 'assets/images/olympus/bg_olympus.png',
              ),
              fit: BoxFit.cover,
              opacity: 0.6,
              onError: (_, __) {},
            ),
          ),
          child: SafeArea(
            child: _loading
                ? _loadingState()
                : _layout == null
                    ? _errorState(s)
                    : Stack(
                        children: [
                          if (!_reducedMotion) _cloudLayer(),
                          Column(
                            children: [
                              _topBar(s),
                              if (_notice != null) _noticeBar(),
                              Expanded(child: _playfield(s)),
                              _bottomBar(s),
                            ],
                          ),
                          if (_banner != null) _bannerOverlay(),
                          if (_bonusIntroVisible)
                            Positioned.fill(
                              child: OlympusFreeSpinsIntro(
                                spins: _bonusIntroSpins,
                                scatters: _bonusIntroScatters,
                                strings: s,
                                reducedMotion: _reducedMotion,
                                reducedFlash: _reducedFlash,
                                art: _art,
                                onDone: _onBonusIntroDone,
                              ),
                            ),
                          if (_celebrationTier != null)
                            Positioned.fill(
                              child: OlympusCelebration(
                                tier: _celebrationTier!,
                                amount: _celebrationAmount,
                                bet: _celebrationBet,
                                capped: _celebrationCapped,
                                strings: s,
                                reducedMotion: _reducedMotion,
                                art: _art,
                                onDone: _onCelebrationDone,
                              ),
                            ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  /// The logo, once it is delivered, over the spinner.
  Widget _loadingState() {
    final logo = _art?.forScene('logo');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null)
            SizedBox(
              width: 260,
              height: 130,
              child: RawImage(image: logo, fit: BoxFit.contain),
            ),
          const SizedBox(height: 18),
          const CircularProgressIndicator(color: _gold),
        ],
      ),
    );
  }

  /// Two cloud layers drifting at different speeds behind the board. Both are
  /// optional art — with neither delivered this draws nothing at all.
  Widget _cloudLayer() {
    final near = _art?.forScene('cloud_near');
    final far = _art?.forScene('cloud_far');
    if (near == null && far == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(child: _CloudLayer(near: near, far: far)),
    );
  }

  Widget _errorState(OlympusStrings s) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _notice ?? s.loadFailed,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _gold),
              onPressed: _reload,
              child: Text(
                s.retry,
                style: const TextStyle(color: Color(0xFF2B1206)),
              ),
            ),
          ],
        ),
      );

  // ── Top bar ──────────────────────────────────────────────────────────────

  /// Compact icon button for the top bar.
  ///
  /// A default IconButton reserves a 48px tap target; six of them plus two
  /// chips overflow a 420px-wide portrait screen and clip the back arrow. 36px
  /// still clears the minimum touch target with the padding around it.
  Widget _barIcon(IconData icon, String tooltip, VoidCallback onPressed) => IconButton(
        icon: Icon(icon, color: Colors.white70, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );

  Widget _topBar(OlympusStrings s) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Row(
          children: [
            _barIcon(
              Icons.arrow_back_rounded,
              s.back,
              () => Navigator.of(context).maybePop(),
            ),
            _chip(Icons.monetization_on_rounded, '$_balance', _gold, s.balance),
            const SizedBox(width: 6),
            // The brief's top bar also lists a gems/secondary-currency counter.
            // This app has exactly one currency, so that slot shows the
            // player's real level rather than a second number with nothing
            // behind it. Add the chip back if a gem balance ever ships.
            _chip(
              Icons.military_tech_rounded,
              s.levelShort(ref.watch(authStateProvider).user?.userLevel ?? 1),
              _boltBlue,
              s.level,
            ),
            const Spacer(),
            // Turbo is a control, not just a readout: it is the setting players
            // reach for most, and burying it in the settings sheet would put a
            // modal between them and it on every change of mind.
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _turbo = !_turbo);
                  _persist(_prefsTurbo, _turbo);
                  _sfx.click();
                },
                child: _chip(
                  Icons.fast_forward_rounded,
                  '×1.5',
                  _turbo ? Colors.orangeAccent : Colors.white24,
                  s.turbo,
                  dim: !_turbo,
                ),
              ),
            ),
            _barIcon(
              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              s.sound,
              () {
                setState(() {
                  _muted = !_muted;
                  _sfx.enabled = !_muted;
                });
                _persist(_prefsMuted, _muted);
                _sfx.click();
              },
            ),
            _barIcon(Icons.fullscreen_rounded, s.fullscreen, _toggleFullscreen),
            _barIcon(Icons.settings_outlined, s.settings, _openSettings),
            _barIcon(Icons.help_outline_rounded, s.help, _openHelp),
          ],
        ),
      );

  bool _fullscreen = false;

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    SystemChrome.setEnabledSystemUIMode(
      _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _sfx.click();
  }

  Widget _chip(
    IconData icon,
    String value,
    Color color,
    String semantic, {
    bool dim = false,
  }) =>
      Semantics(
        label: '$semantic $value',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Text(
                value,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: dim ? Colors.white38 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _noticeBar() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withValues(alpha: 0.5)),
        ),
        child: Text(
          _notice!,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      );

  // ── Playfield ────────────────────────────────────────────────────────────

  /// Landscape is the target composition from the brief: ornament left, board
  /// centre, Zeus right. Portrait keeps the same reading order by stacking Zeus
  /// beside a narrower board rather than on top of it — he must never cover the
  /// grid, in either orientation.
  ///
  /// Pinned to LTR regardless of language. The chrome above and below mirrors
  /// for Arabic, but the playfield must not: the composition *is* Zeus on the
  /// right of the board, and letting RTL flip it moves him to the left and
  /// mirrors the board with him.
  Widget _playfield(OlympusStrings s) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _playfieldBody(s),
    );
  }

  Widget _playfieldBody(OlympusStrings s) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight * 1.25;
        final board = _board(s);

        if (!landscape) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: constraints.maxHeight * 0.26,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: Center(child: _statRail(s, compact: false))),
                      SizedBox(
                        width: constraints.maxWidth * 0.40,
                        child: _zeus(constraints.maxHeight * 0.26),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: Center(child: board)),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left ornament rail: the sequence stats and, in the feature, the
              // meter. Stands in for the golden owl panel until that art lands.
              SizedBox(
                width: math.min(140, constraints.maxWidth * 0.17),
                child: Center(child: _statRail(s, compact: true)),
              ),
              Expanded(child: Center(child: board)),
              SizedBox(
                width: math.min(300, constraints.maxWidth * 0.30),
                child: _zeus(constraints.maxHeight),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Zeus, drawn larger than the column he sits in.
  ///
  /// The reference composition has him roughly the height of the whole
  /// playfield, not a figure tucked into a side panel. [OverflowBox] lets him
  /// exceed the slot's height while staying anchored to its foot, so he grows
  /// upward past the board's top edge instead of being scaled down to fit. He
  /// still never covers the grid: the column itself is beside it, and the
  /// lightning that does cross the board is a separate transparent layer.
  Widget _zeus(double slotHeight) => OverflowBox(
        alignment: Alignment.bottomCenter,
        maxHeight: slotHeight * 1.28,
        child: ZeusStage(
          mood: _mood,
          reducedMotion: _reducedMotion,
          reducedFlash: _reducedFlash,
          art: _art,
        ),
      );

  /// The board, with the lightning layer sized to exactly the same box so a
  /// bolt can be aimed at a cell by its row and column alone.
  Widget _board(OlympusStrings s) {
    final layout = _layout!;
    return Stack(
      alignment: Alignment.center,
      children: [
        OlympusGrid(
          cols: layout.cols,
          rows: layout.rows,
          grid: _displayGrid,
          nameOf: s.symbol,
          scatterBadge: s.scatterBadge,
          highlighted: _highlighted,
          clearing: _clearing,
          multValues: _multValues,
          reducedMotion: _reducedMotion,
          highContrast: _highContrast,
          art: _art,
        ),
        if (_strikeTarget != null)
          Positioned.fill(
            child: LightningStrike(
              // Zeus stands off the right edge of the board.
              from: const Alignment(1.6, -0.75),
              to: _cellAlignment(_strikeTarget!, layout),
              progress: _strikeProgress,
              reducedFlash: _reducedFlash,
            ),
          ),
      ],
    );
  }

  Alignment _cellAlignment(int index, OlympusLayout layout) {
    final col = index % layout.cols;
    final row = index ~/ layout.cols;
    return Alignment(
      (col + 0.5) / layout.cols * 2 - 1,
      (row + 0.5) / layout.rows * 2 - 1,
    );
  }

  /// Sequence win, tumble count and the multiplier the current cascade has
  /// gathered — or the feature HUD while free spins run.
  Widget _statRail(OlympusStrings s, {required bool compact}) {
    if (_inBonus) {
      return OlympusBonusHud(
        spinsLeft: _bonusSpinsLeft,
        meter: _bonusMeter,
        strings: s,
        compact: compact,
      );
    }

    final children = [
      _railStat(s.sequenceWin, _sequenceWin.round().toString(), Colors.white),
      _railStat(s.tumbles, '$_tumbleCount', Colors.white54),
      if (_pendingMultiplier > 0)
        _railStat(s.multiplier, '×$_pendingMultiplier', _gold, big: true),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: 8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  children[i],
                ],
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  children[i],
                ],
              ],
            ),
    );
  }

  Widget _railStat(String label, String value, Color color, {bool big = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              letterSpacing: 0.8,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              color: color,
              fontSize: big ? 22 : 17,
              fontWeight: FontWeight.w900,
              shadows: big ? const [Shadow(color: Color(0x99E3B84A), blurRadius: 14)] : null,
            ),
            child: Text(value, textDirection: TextDirection.ltr),
          ),
        ],
      );

  Widget _bannerOverlay() => Positioned(
        top: 70,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x88E3B84A), blurRadius: 18)],
              ),
              child: Text(
                _banner!,
                style: const TextStyle(
                  color: Color(0xFF2B1206),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );

  // ── Bottom bar ───────────────────────────────────────────────────────────

  Widget _bottomBar(OlympusStrings s) {
    final canPlay = !_busy && !_loading && _layout != null;
    final children = [
      _betControl(s, canPlay),
      const SizedBox(width: 10),
      _winReadout(s),
      const SizedBox(width: 10),
      _autoButton(s, canPlay),
      const SizedBox(width: 10),
      Expanded(child: _spinButton(s, canPlay)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        // Left-handed play mirrors the row so SPIN falls under the other thumb.
        textDirection: _leftHanded ? TextDirection.rtl : TextDirection.ltr,
        children: children,
      ),
    );
  }

  Widget _betControl(OlympusStrings s, bool enabled) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 20),
              tooltip: s.decreaseBet,
              onPressed: enabled ? () => _stepBet(-1) : null,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.totalBet,
                  style: const TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 0.5),
                ),
                Text(
                  '$_bet',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 20),
              tooltip: s.increaseBet,
              onPressed: enabled ? () => _stepBet(1) : null,
            ),
          ],
        ),
      );

  Widget _winReadout(OlympusStrings s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _boltBlue.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.totalWin,
              style: const TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 0.5),
            ),
            Text(
              '$_roundWin',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: _roundWin > 0 ? _gold : Colors.white54,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );

  Widget _autoButton(OlympusStrings s, bool canPlay) => SizedBox(
        width: 74,
        height: 46,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: BorderSide(color: _gold.withValues(alpha: _auto ? 1 : 0.4)),
            // Never transparent: the backdrop behind it is a bright peach sky,
            // and gold-on-peach is unreadable. The panel fill is what every
            // other control on this bar sits on.
            backgroundColor: _auto ? _gold.withValues(alpha: 0.25) : _panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _auto
              ? _stop
              : (canPlay
                  ? () {
                      setState(() {
                        _auto = true;
                        _stopRequested = false;
                      });
                      _sfx.click();
                      unawaited(_spin());
                    }
                  : null),
          child: Text(
            _auto ? s.stop : s.auto,
            style: TextStyle(
              color: _auto ? Colors.redAccent : _gold,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      );

  /// One button that is SPIN when idle and STOP while a round resolves, which
  /// is what stops a double-tap from ever queueing a second spin.
  Widget _spinButton(OlympusStrings s, bool canPlay) {
    final resolving = _busy;
    return Semantics(
      button: true,
      label: resolving ? s.stop : s.spin,
      child: SizedBox(
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: resolving ? const Color(0xFF6B2B7A) : const Color(0xFF7B27C7),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: const BorderSide(color: _gold, width: 1.4),
          ),
          onPressed: resolving ? _stop : (canPlay ? _spin : null),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                resolving ? Icons.stop_rounded : Icons.bolt_rounded,
                color: _gold,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                resolving ? s.stop : s.spin,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two cloud bands drifting across the sky at different speeds, which is what
/// gives the backdrop depth without a second background image.
///
/// Both layers are optional: whichever texture is missing is simply not drawn.
class _CloudLayer extends StatefulWidget {
  const _CloudLayer({required this.near, required this.far});

  final ui.Image? near, far;

  @override
  State<_CloudLayer> createState() => _CloudLayerState();
}

class _CloudLayerState extends State<_CloudLayer> with SingleTickerProviderStateMixin {
  // Slow enough to read as weather rather than motion. One full pass a minute.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _drift,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _CloudPainter(
            t: _drift.value,
            near: widget.near,
            far: widget.far,
          ),
        ),
      );
}

class _CloudPainter extends CustomPainter {
  const _CloudPainter({required this.t, this.near, this.far});

  final double t;
  final ui.Image? near, far;

  /// Draws one band twice, offset by a full width, so it wraps seamlessly.
  void _band(
    Canvas canvas,
    Size size,
    ui.Image img,
    double phase,
    double top,
    double heightFactor,
    double opacity,
  ) {
    final h = size.height * heightFactor;
    final w = size.width * 1.6;
    final x = -((phase % 1.0) * w);
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..color = Colors.white.withValues(alpha: opacity);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    for (var i = 0; i < 2; i++) {
      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(x + i * w, size.height * top, w, h),
        paint,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The far band moves at a third of the near one's speed.
    if (far != null) _band(canvas, size, far!, t * 0.33, 0.10, 0.34, 0.30);
    if (near != null) _band(canvas, size, near!, t, 0.46, 0.42, 0.42);
  }

  @override
  bool shouldRepaint(covariant _CloudPainter old) => old.t != t;
}

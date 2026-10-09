import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/fruit_jackpot_repository.dart';
import '../../services/device_tier.dart';
import 'fruit_jackpot_engine.dart';
import 'fruit_jackpot_preferences.dart';
import 'fruit_jackpot_strings.dart';
import 'fruit_jackpot_sfx.dart';
import 'fruit_jackpot_symbols.dart';
import 'fruit_jackpot_grid.dart';
import 'fruit_jackpot_bonus.dart';
import 'fruit_jackpot_celebration.dart';
import 'fruit_jackpot_fairness.dart';
import 'fruit_jackpot_help.dart';

class FruitJackpotScreen extends ConsumerStatefulWidget {
  final FruitJackpotRepository? repository;
  const FruitJackpotScreen({super.key, this.repository});
  @override
  ConsumerState<FruitJackpotScreen> createState() => _FruitJackpotScreenState();
}

class _FruitJackpotScreenState extends ConsumerState<FruitJackpotScreen>
    with SingleTickerProviderStateMixin {
  late final repo = widget.repository ?? FruitJackpotRepository();
  final sfx = FruitJackpotSfx();
  late final AnimationController ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );
  FruitJackpotPreferences? prefs;
  Map<String, dynamic>? layout, pending;
  Map<String, dynamic> stats = {};
  List<FruitJackpotRound> history = [];
  FruitJackpotRound? last;
  List<String> grid = List.of(fruitJackpotSymbolIds);
  bool loading = true,
      busy = false,
      arabic = true,
      motion = true,
      sound = true,
      power = true;
  int bet = 100, revealed = 9, roundCount = 0;
  String? notice;
  Completer<void>? stop;
  Timer? timer;
  int get balance => ref.read(authStateProvider).user?.coinsBalance ?? 0;
  bool get locked => busy || pending != null;
  bool get reduced =>
      !motion ||
      !power ||
      DeviceTier.lite ||
      MediaQuery.disableAnimationsOf(context);
  FruitJackpotStrings get strings => FruitJackpotStrings(arabic);
  String tr(String ar, String en) => arabic ? ar : en;
  @override
  void initState() {
    super.initState();
    boot();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    if (stop?.isCompleted == false) stop!.complete();
    ambient.dispose();
    sfx.dispose();
    super.dispose();
  }

  void syncMotion() {
    if (reduced) {
      ambient.stop();
    } else if (!ambient.isAnimating) {
      ambient.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotion();
  }

  void applyStats(Map<String, dynamic> data) {
    stats = data;
    roundCount = (data['roundCount'] as num?)?.toInt() ?? roundCount;
  }

  Future<void> boot() async {
    try {
      final storage = await SharedPreferences.getInstance();
      if (!mounted) return;
      prefs = FruitJackpotPreferences(
        storage,
        ref.read(authStateProvider).user?.id.toString() ?? 'guest',
      );
      arabic = prefs!.arabic;
      motion = prefs!.motion;
      sound = prefs!.sound;
      sfx.enabled = sound;
      pending = prefs!.pending;
      history = prefs!.history;
      final state = await repo.fetchState();
      if (!mounted) return;
      ref
          .read(authStateProvider.notifier)
          .updateCoinsBalance((state['balance'] as num).toInt());
      layout = Map<String, dynamic>.from(state['layout'] as Map);
      applyStats(state);
      history = prefs!.visible(
        (state['history'] as List)
            .map(
              (e) => FruitJackpotRound.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
      last = history.firstOrNull;
      grid = last?.grid ?? grid;
      if (pending != null) {
        bet = pending!['betPerLine'] as int;
      } else {
        bet = fruitJackpotBets.firstWhere(allowed, orElse: () => 100);
      }
      await prefs!.saveHistory(history);
      if (!mounted) return;
      syncMotion();
    } catch (_) {
      notice = strings.text('error');
    }
    if (mounted) setState(() => loading = false);
  }

  bool allowed(int b) =>
      b >= (layout?['minBet'] as num? ?? 100) &&
      b <= (layout?['maxBet'] as num? ?? 100000);
  Future<void> delay(int ms) async {
    if (reduced || stop?.isCompleted == true) return;
    await Future.any([
      Future<void>.delayed(Duration(milliseconds: ms)),
      stop!.future,
    ]);
  }

  Future<void> spin() async {
    if (busy || loading || layout == null) return;
    if (pending == null && (!allowed(bet) || layout!['enabled'] == false)) {
      setState(() => notice = strings.text('disabled'));
      return;
    }
    if (pending == null && balance < bet) {
      setState(() => notice = tr('الرصيد غير كافٍ', 'Insufficient balance'));
      return;
    }
    setState(() {
      busy = true;
      notice = null;
      revealed = 0;
    });
    stop = Completer<void>();
    sfx.spin();
    try {
      pending ??= {
        'requestId': const Uuid().v4(),
        'betPerLine': bet,
        'activeLines': 8,
      };
      await prefs!.savePending(pending);
      final result = await repo.spin(
        pending!['betPerLine'] as int,
        8,
        requestId: pending!['requestId'] as String,
      );
      if (!mounted) return;
      // The server is the only source of balance and result. STOP only shortens replay.
      setState(() {
        last = result;
        grid = result.grid;
      });
      await delay(850);
      for (var i = 1; i <= 9; i++) {
        if (!mounted) return;
        setState(() => revealed = i);
        if (power) HapticFeedback.selectionClick();
        await delay(120);
      }
      await delay(300);
      if (!mounted) return;
      ref.read(authStateProvider.notifier).updateCoinsBalance(result.balance);
      roundCount = result.roundNumber;
      history = prefs!.visible([
        result,
        ...history.where((r) => r.id != result.id),
      ]);
      await prefs!.saveHistory(history);
      await prefs!.savePending(null);
      pending = null;
      if (!mounted) return;
      setState(
        () => notice = result.capped
            ? strings.text('capped')
            : result.totalPrize > 0
                ? '${strings.text('prize')}: ${result.totalPrize}'
                : strings.text('noWin'),
      );
      if (result.totalPrize > 0) {
        if (power) HapticFeedback.mediumImpact();
        result.jackpotTriggered ? sfx.jackpot() : sfx.win();
      }
      if (result.bonusTriggered) {
        await showDialog<void>(
          context: context,
          builder: (_) => FruitJackpotBonus(
            multiplier: result.bonusMultiplier,
            arabic: arabic,
          ),
        );
      }
      if (!mounted) return;
      if (result.totalPrize > 0) {
        await showDialog<void>(
          context: context,
          builder: (_) => FruitJackpotCelebration(
            prize: result.totalPrize,
            jackpot: result.jackpotTriggered,
            motion: !reduced,
            arabic: arabic,
          ),
        );
      }
      try {
        final rank = await repo.request('rank');
        if (mounted) setState(() => applyStats(rank));
      } catch (_) {}
    } on FruitJackpotException catch (e) {
      // Keep ambiguous failures durable so retry always uses the SAME key.
      if ([
        'INSUFFICIENT',
        'BAD_BET',
        'BET_TOO_HIGH',
        'BET_TOO_LOW',
        'GAME_DISABLED',
        'PRIZE_POOL_LOW',
        'DAILY_WIN_CAP',
      ].contains(e.code)) {
        await prefs?.savePending(null);
        pending = null;
      }
      if (mounted) {
        setState(
          () => notice = e.code == 'INSUFFICIENT'
              ? tr('الرصيد غير كافٍ', 'Insufficient balance')
              : strings.text('error'),
        );
      }
    } catch (_) {
      if (mounted) setState(() => notice = strings.text('error'));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          revealed = 9;
        });
      }
    }
  }

  Future<void> panel(String title, Widget child) => showDialog<void>(
        context: context,
        builder: (_) => Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            backgroundColor: const Color(0xff35134e),
            title: Text(title),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(child: child),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(strings.text('close')),
              ),
            ],
          ),
        ),
      );
  void settings() => panel(
        strings.text('settings'),
        StatefulBuilder(
          builder: (_, update) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in ['language', 'sound', 'motion'])
                SwitchListTile(
                  title: Text(strings.text(key)),
                  value: key == 'language'
                      ? arabic
                      : key == 'sound'
                          ? sound
                          : motion,
                  onChanged: (v) async {
                    setState(() {
                      if (key == 'language') arabic = v;
                      if (key == 'sound') sound = v;
                      if (key == 'motion') motion = v;
                      sfx.enabled = sound && power;
                    });
                    update(() {});
                    syncMotion();
                    await prefs?.setSetting(
                        key == 'language' ? 'arabic' : key, v,);
                  },
                ),
              TextButton(
                onPressed: () async {
                  await prefs?.clearHistory();
                  if (mounted) {
                    setState(() => history = []);
                    update(() {});
                  }
                },
                child: Text(strings.text('clear')),
              ),
            ],
          ),
        ),
      );
  void showHistory() => panel(
        strings.text('history'),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: history.isEmpty
              ? [Text(strings.text('empty'))]
              : history
                  .map(
                    (r) => ListTile(
                      title: Text(
                        '#${r.roundNumber} • ${r.totalBet} → ${r.totalPrize}',
                      ),
                      subtitle: Text(
                        '${r.at.toLocal()}\n${strings.text('balance')}: ${r.balance}\n${r.grid.map((s) => fruitJackpotEmoji[s]).join(' ')}\n${r.jackpotTriggered ? 'JACKPOT' : r.bonusTriggered ? 'BONUS' : r.totalPrize > 0 ? strings.text('win') : strings.text('loss')}',
                      ),
                    ),
                  )
                  .toList(),
        ),
      );
  Widget box(Widget child, {Color border = const Color(0xffbd80e5)}) =>
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff6a3b9d), Color(0xff35134e)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider);
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        textTheme: Theme.of(
          context,
        ).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      child: Directionality(
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: const Color(0xff190d35),
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/games/fruit_jackpot/background.png',
                  fit: BoxFit.cover,
                  cacheWidth: 1080,
                  errorBuilder: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff3b176b), Color(0xff190d35)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                      child: LayoutBuilder(builder: (_, box) => stage(box)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One screen, no scrolling. Fixed rows around the machine; the machine
  /// takes the height left and the logo only shows when there is room.
  Widget stage(BoxConstraints box) {
    const top = 46.0, plate = 62.0, results = 40.0, chips = 66.0;
    const action = 58.0, gaps = 40.0, frame = 74.0;
    final room = box.maxHeight - top - plate - results - chips - action - gaps;
    // The grid is 1.08:1 inside an 8 px frame on each side.
    final gridW = min(box.maxWidth - 16, (room - frame) * 1.08);
    final machineH = gridW / 1.08 + frame;
    final logo = (room - machineH).clamp(0.0, 120.0);
    return Stack(
      children: [
        Column(
          children: [
            SizedBox(height: top, child: topBar()),
            if (logo >= 44)
              SizedBox(
                height: logo,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: ambient,
                    builder: (_, child) => Transform.scale(
                      scale: reduced
                          ? 1
                          : 1 + .025 * sin(ambient.value * 2 * pi * 8),
                      child: child,
                    ),
                    child: fruitJackpotArt('logo_jackpot'),
                  ),
                ),
              ),
            SizedBox(height: plate, child: jackpotPlate()),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: SizedBox(width: gridW + 16, child: machine()),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(height: results, child: resultsRow()),
            const SizedBox(height: 8),
            SizedBox(height: chips, child: chipRow()),
            const SizedBox(height: 8),
            SizedBox(height: action, child: actionRow()),
            if (loading) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
        if (notice != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: chips + action + results + 34,
            child: IgnorePointer(
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xee2a0f4a),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xffffd52b)),
                    ),
                    child: Text(
                      notice!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xfffff1b8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget roundIcon(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
        message: tip,
        child: Semantics(
          button: true,
          label: tip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xff8e55d6), Color(0xff4a1c86)],
                ),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0x99ffd52b), width: 1.2),
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
          ),
        ),
      );

  Widget topBar() => Row(
        children: [
          roundIcon(
            arabic ? Icons.arrow_forward : Icons.arrow_back,
            strings.text('back'),
            () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                strings.text('title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xffffd52b),
                  shadows: [Shadow(color: Color(0xff8a2be2), blurRadius: 8)],
                ),
              ),
            ),
          ),
          // Today's rank.
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: const Color(0xcc2a0f4a),
              border: Border.all(color: const Color(0x99ffd52b)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events,
                    color: Color(0xffffd52b), size: 16,),
                const SizedBox(width: 4),
                Text(
                  stats['rank'] == null ? '—' : '#${stats['rank']}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          roundIcon(Icons.tune, strings.text('settings'), settings),
          const SizedBox(width: 6),
          roundIcon(
            Icons.info_outline,
            strings.text('help'),
            () => panel(
              strings.text('help'),
              FruitJackpotHelp(arabic: arabic, layout: layout),
            ),
          ),
        ],
      );

  String grouped(int v) => v.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );

  Widget jackpotPlate() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff7b3fc0), Color(0xff4a1c86), Color(0xff2a0f4a)],
          ),
          border: Border.all(color: const Color(0xffffd52b), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x66ffd52b), blurRadius: 14),
          ],
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                tr('جائزة الجاكبوت عند رهانك', 'Jackpot at your bet'),
                maxLines: 2,
                style: const TextStyle(fontSize: 12, color: Color(0xffe8d7ff)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: bet * 1000.0),
                  duration: Duration(milliseconds: reduced ? 0 : 600),
                  builder: (_, v, __) => ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xfffffbd0),
                        Color(0xffffd52b),
                        Color(0xffff9a25),
                      ],
                    ).createShader(b),
                    child: Text(
                      grouped(v.round()),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  /// Gold cabinet: the three row multipliers as medallions, then the reels.
  Widget machine() {
    final won = last != null && last!.totalPrize > 0 && revealed == 9;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xfffff0a8),
            Color(0xffffc93c),
            Color(0xffd98b12),
            Color(0xff8a4f08),
          ],
        ),
        boxShadow: [
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
          if (won) const BoxShadow(color: Color(0xaaffd52b), blurRadius: 26),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff4b1a7a), Color(0xff22093f)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: List.generate(3, (i) {
                  final m = last?.rowMultipliers[i] ?? 2;
                  final lit = won && m > 1;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: lit
                              ? const [
                                  Color(0xfffffbd0),
                                  Color(0xffffd52b),
                                  Color(0xffff9a25),
                                ]
                              : const [Color(0xffb88a3a), Color(0xff7a5420)],
                        ),
                        border: Border.all(
                          color: lit ? Colors.white : const Color(0x99fff0a8),
                          width: 1.5,
                        ),
                        boxShadow: [
                          if (lit)
                            const BoxShadow(
                              color: Color(0xccffd52b),
                              blurRadius: 12,
                            ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '×$m',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: lit
                                ? const Color(0xff5a1d00)
                                : const Color(0xfffff0c8),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            FruitJackpotGrid(
              grid: grid,
              round: last,
              revealed: revealed,
              motion: !reduced,
              arabic: arabic,
            ),
          ],
        ),
      ),
    );
  }

  /// Balance, the last results as fruit, history and fairness.
  Widget resultsRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xcc2a0f4a),
          border: Border.all(color: const Color(0x55ffd52b)),
        ),
        child: Row(
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                '${strings.text('balance')}: $balance 🪙',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: showHistory,
                child: Row(
                  children: [
                    for (final (i, r) in history.take(6).indexed)
                      Expanded(
                        child: Opacity(
                          opacity: i == 0 ? 1 : .7,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 22,
                                child: fruitJackpotArt(r.grid.first),
                              ),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${r.totalPrize}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: r.totalPrize > 0
                                          ? const Color(0xffffd52b)
                                          : Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: strings.text('fairness'),
              visualDensity: VisualDensity.compact,
              onPressed: locked
                  ? null
                  : () => panel(
                        strings.text('fairness'),
                        FruitJackpotFairness(
                          repository: repo,
                          strings: strings,
                          round: last,
                        ),
                      ),
              icon: const Icon(Icons.verified_user_outlined, size: 20),
            ),
          ],
        ),
      );

  Widget chipRow() => Row(
        children: List.generate(4, (i) {
          final b = fruitJackpotBets[i];
          final enabled = !locked && allowed(b) && balance >= b;
          final selected = bet == b;
          return Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              enabled: enabled,
              label: '${strings.text('bet')} $b',
              child: GestureDetector(
                onTap: enabled
                    ? () {
                        setState(() => bet = b);
                        sfx.click();
                      }
                    : null,
                child: Opacity(
                  opacity: enabled || selected ? 1 : .45,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 160),
                    offset: Offset(0, selected ? -.08 : 0),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 160),
                      scale: selected ? 1.1 : 1,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            if (selected)
                              const BoxShadow(
                                color: Color(0xccffd52b),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            fruitJackpotArt(
                              [
                                'chip_100',
                                'chip_1k',
                                'chip_10k',
                                'chip_100k',
                              ][i],
                            ),
                            Text(
                              ['100', '1K', '10K', '100K'][i],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      );

  Widget actionRow() {
    final label = busy
        ? tr('جارٍ الدوران…', 'Spinning…')
        : pending != null
            ? strings.text('retry')
            : strings.text('spin');
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            enabled: !(busy || loading),
            label: label,
            child: GestureDetector(
              key: const Key('fruit-spin'),
              onTap: busy || loading ? null : spin,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: busy || loading ? .6 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(29),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xffff7a6b),
                        Color(0xffe92335),
                        Color(0xff9e0f22),
                      ],
                    ),
                    border:
                        Border.all(color: const Color(0xffffd52b), width: 2.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99e92335),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Color(0x88000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          enabled: busy,
          label: strings.text('stop'),
          child: GestureDetector(
            key: const Key('fruit-stop'),
            onTap: busy
                ? () {
                    if (stop?.isCompleted == false) stop!.complete();
                  }
                : null,
            child: Opacity(
              opacity: busy ? 1 : .45,
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xff8e55d6), Color(0xff4a1c86)],
                  ),
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0xffffd52b), width: 2),
                  ),
                ),
                child: const Icon(Icons.stop_rounded,
                    color: Colors.white, size: 30,),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

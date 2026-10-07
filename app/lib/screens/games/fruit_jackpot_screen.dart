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
  Duration clockOffset = Duration.zero;
  final roundClock = Stopwatch();
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
    final server = DateTime.tryParse(data['serverTime']?.toString() ?? '');
    if (server != null) clockOffset = server.difference(DateTime.now());
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
    roundClock
      ..reset()
      ..start();
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
      roundClock.stop();
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
      roundClock.stop();
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
                await prefs?.setSetting(key == 'language' ? 'arabic' : key, v);
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
                      '${r.at.toLocal()}\n${strings.text('balance')}: ${r.balance}\n${r.grid.map((s) => fruitJackpotEmoji[s]).join(' ')}\n${r.jackpotTriggered
                          ? 'JACKPOT'
                          : r.bonusTriggered
                          ? 'BONUS'
                          : r.totalPrize > 0
                          ? strings.text('win')
                          : strings.text('loss')}',
                    ),
                  ),
                )
                .toList(),
    ),
  );
  String get resetText {
    final reset = DateTime.tryParse(stats['resetAt']?.toString() ?? '');
    if (reset == null) return '—';
    final seconds = reset
        .difference(DateTime.now().add(clockOffset))
        .inSeconds
        .clamp(0, 100000);
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

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
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: strings.text('back'),
                                  onPressed: () => Navigator.maybePop(context),
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                Expanded(
                                  child: Text(
                                    strings.text('title'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: strings.text('settings'),
                                  onPressed: settings,
                                  icon: const Icon(Icons.tune),
                                ),
                                IconButton(
                                  tooltip: strings.text('help'),
                                  onPressed: () => panel(
                                    strings.text('help'),
                                    FruitJackpotHelp(
                                      arabic: arabic,
                                      layout: layout,
                                    ),
                                  ),
                                  icon: const Icon(Icons.info_outline),
                                ),
                              ],
                            ),
                            Text(
                              '${tr('الجولة', 'Round')} $roundCount • ID ${last == null ? '—' : last!.id.substring(0, last!.id.length.clamp(0, 8))} • ${(roundClock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Color(0xffe8d7ff),
                                fontSize: 12,
                              ),
                            ),
                            AnimatedBuilder(
                              animation: ambient,
                              builder: (_, child) => ShaderMask(
                                blendMode: BlendMode.srcATop,
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: const [
                                    Colors.transparent,
                                    Color(0x88ffffff),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, .5, 1],
                                  transform: GradientRotation(
                                    ambient.value * 8 * 3.14159,
                                  ),
                                ).createShader(bounds),
                                child: child,
                              ),
                              child: SizedBox(
                                height: 115,
                                child: fruitJackpotArt('logo_jackpot'),
                              ),
                            ),
                            box(
                              Column(
                                children: [
                                  Text(
                                    tr(
                                      'جائزة الجاكبوت عند رهانك',
                                      'Jackpot at your bet',
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(end: bet * 1000.0),
                                    duration: Duration(
                                      milliseconds: reduced ? 0 : 600,
                                    ),
                                    builder: (_, v, __) => Text(
                                      v.round().toString().replaceAllMapped(
                                        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                                        (m) => '${m[1]},',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xffffd52b),
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              border: const Color(0xffffd52b),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    IconButton(
                                      tooltip: tr(
                                        'تشغيل المؤثرات',
                                        'Power effects',
                                      ),
                                      onPressed: () {
                                        setState(() => power = !power);
                                        sfx.enabled = sound && power;
                                        syncMotion();
                                      },
                                      icon: Icon(
                                        Icons.power_settings_new,
                                        color: power
                                            ? Colors.cyan
                                            : Colors.white54,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: strings.text('sound'),
                                      onPressed: () async {
                                        setState(() => sound = !sound);
                                        sfx.enabled = sound && power;
                                        await prefs?.setSetting('sound', sound);
                                      },
                                      icon: Icon(
                                        sound
                                            ? Icons.volume_up
                                            : Icons.volume_off,
                                      ),
                                    ),
                                    Text(
                                      repo.lastPingMs == null
                                          ? '—'
                                          : '${repo.lastPingMs} ms',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: (repo.lastPingMs ?? 0) <= 100
                                            ? Colors.greenAccent
                                            : Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: box(
                                    Column(
                                      children: [
                                        Row(
                                          children: List.generate(
                                            3,
                                            (i) => Expanded(
                                              child: AnimatedBuilder(
                                                animation: ambient,
                                                builder: (_, __) => Container(
                                                  margin: const EdgeInsets.all(
                                                    3,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xffe8deef,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    boxShadow: [
                                                      if (last != null &&
                                                          last!.totalPrize >
                                                              0 &&
                                                          revealed == 9 &&
                                                          (ambient.value * 12)
                                                                      .floor() %
                                                                  3 ==
                                                              i)
                                                        const BoxShadow(
                                                          color: Colors.amber,
                                                          blurRadius: 12,
                                                        ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    '×${last?.rowMultipliers[i] ?? 2}',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Color(0xff662b92),
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 22,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        FruitJackpotGrid(
                                          grid: grid,
                                          round: last,
                                          revealed: revealed,
                                          motion: !reduced,
                                          arabic: arabic,
                                        ),
                                        AnimatedBuilder(
                                          animation: ambient,
                                          builder: (_, __) => Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceAround,
                                            children: List.generate(
                                              12,
                                              (i) => Container(
                                                width: 5,
                                                height: 5,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color:
                                                      last != null &&
                                                          last!.totalPrize >
                                                              0 &&
                                                          revealed == 9 &&
                                                          (ambient.value * 32)
                                                                      .floor() %
                                                                  3 ==
                                                              i % 3
                                                      ? Colors.cyanAccent
                                                      : Colors.amber,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 45,
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.stars,
                                        color: Colors.amber,
                                      ),
                                      Text(
                                        stats['rank'] == null
                                            ? '—'
                                            : '#${stats['rank']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        tr('اليوم', 'Today'),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      FittedBox(
                                        child: Text(
                                          resetText,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRect(
                              child: SizedBox(
                                height: 30,
                                child: AnimatedBuilder(
                                  animation: ambient,
                                  builder: (_, __) => Transform.translate(
                                    offset: Offset(
                                      reduced ? 0 : -ambient.value * 40,
                                      0,
                                    ),
                                    child: Text(
                                      history.isEmpty
                                          ? tr('النتائج', 'Results')
                                          : history
                                                .take(12)
                                                .map(
                                                  (r) =>
                                                      '${r == history.first ? 'NEW ' : ''}${fruitJackpotEmoji[r.grid.first]} ${r.totalPrize}',
                                                )
                                                .join('    '),
                                      maxLines: 1,
                                      overflow: TextOverflow.fade,
                                      softWrap: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                '${strings.text('balance')}: $balance 🪙',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: List.generate(4, (i) {
                                final b = fruitJackpotBets[i];
                                final enabled =
                                    !locked && allowed(b) && balance >= b;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Semantics(
                                      selected: bet == b,
                                      button: true,
                                      enabled: enabled,
                                      label: '${strings.text('bet')} $b',
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          minimumSize: const Size(44, 72),
                                          side: BorderSide(
                                            color: bet == b
                                                ? Colors.amber
                                                : Colors.purpleAccent,
                                            width: bet == b ? 2 : 1,
                                          ),
                                          backgroundColor: [
                                            const Color(0xff9d332a),
                                            const Color(0xff56369b),
                                            const Color(0xff1657a2),
                                            const Color(0xff43318e),
                                          ][i],
                                        ),
                                        onPressed: enabled
                                            ? () {
                                                setState(() => bet = b);
                                                sfx.click();
                                              }
                                            : null,
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              height: 30,
                                              child: fruitJackpotArt(
                                                [
                                                  'chip_100',
                                                  'chip_1k',
                                                  'chip_10k',
                                                  'chip_100k',
                                                ][i],
                                              ),
                                            ),
                                            Text(
                                              ['100', '1K', '10K', '100K'][i],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    key: const Key('fruit-spin'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xffe92335),
                                      minimumSize: const Size(44, 56),
                                    ),
                                    onPressed: busy || loading ? null : spin,
                                    child: Text(
                                      busy
                                          ? tr('جارٍ الدوران…', 'Spinning…')
                                          : pending != null
                                          ? strings.text('retry')
                                          : strings.text('spin'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 22,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  key: const Key('fruit-stop'),
                                  onPressed: busy
                                      ? () {
                                          if (stop?.isCompleted == false) {
                                            stop!.complete();
                                          }
                                        }
                                      : null,
                                  child: Text(strings.text('stop')),
                                ),
                              ],
                            ),
                            if (loading) const LinearProgressIndicator(),
                            if (notice != null)
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    notice!,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: showHistory,
                                  child: Text(strings.text('history')),
                                ),
                                TextButton(
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
                                  child: Text(strings.text('fairness')),
                                ),
                                if (layout == null && !loading)
                                  TextButton(
                                    onPressed: () {
                                      setState(() => loading = true);
                                      boot();
                                    },
                                    child: Text(strings.text('retry')),
                                  ),
                              ],
                            ),
                            Text(
                              strings.footer,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xffe8d7ff),
                              ),
                            ),
                          ],
                        ),
                      ),
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
}

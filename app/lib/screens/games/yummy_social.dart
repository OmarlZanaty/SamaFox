import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../repositories/yummy_repository.dart';
import '../../services/socket_service.dart';
import 'yummy_fx.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

/// The social side of YUMMY: the big-win ticker (fed by the server's global
/// `game_win_broadcast`), the weekly leaderboard, daily missions and the
/// autoplay setup sheet.

class YummyWin {
  final String game, name;
  final int userId, prize;
  final double x;
  final String tier;
  final String? avatar;
  const YummyWin({
    required this.game,
    required this.name,
    required this.userId,
    required this.prize,
    required this.x,
    required this.tier,
    this.avatar,
  });
  static YummyWin? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final prize = raw['prize'];
    if (prize is! num) return null;
    return YummyWin(
      game: raw['game']?.toString() ?? 'yummy',
      name: raw['name']?.toString() ?? '',
      userId: (raw['userId'] as num?)?.toInt() ?? 0,
      prize: prize.toInt(),
      x: (raw['x'] as num?)?.toDouble() ?? 0,
      tier: raw['tier']?.toString() ?? 'big',
      avatar: raw['avatar']?.toString(),
    );
  }
}

/// Latest big wins, newest first. One app-wide listener on the socket; the
/// YUMMY screen also seeds it from GET /games/yummy/feed when it opens.
class YummyWinFeed extends ChangeNotifier {
  YummyWinFeed._();
  static final YummyWinFeed instance = YummyWinFeed._();
  final List<YummyWin> wins = [];
  bool _listening = false;

  void listen() {
    if (_listening) return;
    _listening = true;
    try {
      SocketService().on('game_win_broadcast', (data) => add(data));
    } catch (e) {
      debugPrint('[YUMMY] win feed unavailable: $e');
    }
  }

  void add(Object? raw) {
    final win = YummyWin.tryParse(raw);
    if (win == null) return;
    wins.insert(0, win);
    if (wins.length > 12) wins.removeRange(12, wins.length);
    notifyListeners();
  }

  /// Merges a fetched feed without duplicating what the socket already gave.
  void seed(List<Map<String, dynamic>> rows) {
    if (wins.isNotEmpty) return;
    for (final row in rows.reversed) {
      final win = YummyWin.tryParse(row);
      if (win != null) wins.insert(0, win);
    }
    if (wins.length > 12) wins.removeRange(12, wins.length);
    notifyListeners();
  }
}

/// A one-line marquee of recent big wins. Scrolls with the ambient [clock];
/// shows the newest one still when there is no clock (lite / reduced motion).
class YummyWinTicker extends StatelessWidget {
  final YummyClock? clock;
  final YummyStrings strings;
  final bool dark;
  const YummyWinTicker({
    super.key,
    required this.clock,
    required this.strings,
    this.dark = true,
  });

  String _line(YummyWin win) =>
      '👑 ${win.name} ${strings.text('justWon')} ${win.prize} (×${win.x.toStringAsFixed(win.x >= 100 ? 0 : 1)}) · YUMMY';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: YummyWinFeed.instance,
        builder: (context, _) {
          final wins = YummyWinFeed.instance.wins;
          if (wins.isEmpty) return const SizedBox.shrink();
          final text = wins.take(6).map(_line).join('      ✦      ');
          const style = TextStyle(
            color: yummyGold,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          );
          return Semantics(
            liveRegion: true,
            label: _line(wins.first),
            child: ExcludeSemantics(
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xCC1A0B3D) : yummyDeep,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0x66FFD529)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final painter = TextPainter(
                          text: TextSpan(text: text, style: style),
                          textDirection: strings.ar
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          maxLines: 1,
                        )..layout();
                        final clock = this.clock;
                        final label = Text(
                          text,
                          style: style,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                        );
                        if (clock == null ||
                            painter.width <= constraints.maxWidth) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                _line(wins.first),
                                style: style,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        }
                        final span = painter.width + 60;
                        return AnimatedBuilder(
                          animation: clock,
                          builder: (context, _) {
                            final shift = (clock.value * 45) % span;
                            return Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                for (final start in [0.0, span])
                                  Positioned(
                                    left: constraints.maxWidth -
                                        shift +
                                        start -
                                        span +
                                        20,
                                    top: 6,
                                    child: label,
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

Widget _avatar(String? url, String name, double size) {
  final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
  final fallback = CircleAvatar(
    radius: size / 2,
    backgroundColor: yummyDeep,
    child: Text(initial, style: const TextStyle(color: Colors.white)),
  );
  if (url == null || !url.startsWith('http')) return fallback;
  return ClipOval(
    child: Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      errorBuilder: (_, __, ___) => fallback,
    ),
  );
}

/// Top 20 coin winners this week, and where the player stands.
class YummyLeaderboard extends StatelessWidget {
  final YummyRepository repository;
  final YummyStrings strings;
  final int? userId;
  const YummyLeaderboard({
    super.key,
    required this.repository,
    required this.strings,
    this.userId,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: repository.leaderboard(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(strings.text('error'));
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data!;
          final entries = (data['entries'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final me = Map<String, dynamic>.from(data['me'] as Map? ?? {});
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1C7BE8), yummyDeep],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events, color: yummyGold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        me['rank'] == null
                            ? strings.text('unranked')
                            : '${strings.text('myRank')}: #${me['rank']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${me['won'] ?? 0}',
                      style: const TextStyle(
                        color: yummyGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty) Text(strings.text('empty')),
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  selected: entry['userId'] == userId,
                  leading: SizedBox(
                    width: 76,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            switch (entry['rank']) {
                              1 => '🥇',
                              2 => '🥈',
                              3 => '🥉',
                              _ => '#${entry['rank']}',
                            },
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _avatar(
                          entry['avatar']?.toString(),
                          entry['name']?.toString() ?? '',
                          40,
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    entry['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '${entry['won']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: yummyDeep,
                      fontSize: 16,
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

/// Today's missions with progress bars and claim buttons.
class YummyMissions extends StatefulWidget {
  final YummyRepository repository;
  final YummyStrings strings;
  const YummyMissions({
    super.key,
    required this.repository,
    required this.strings,
  });

  @override
  State<YummyMissions> createState() => _YummyMissionsState();
}

class _YummyMissionsState extends State<YummyMissions> {
  late Future<Map<String, dynamic>> _future = widget.repository.missions();
  String? _claiming, _notice;

  Future<void> _claim(String key) async {
    setState(() {
      _claiming = key;
      _notice = null;
    });
    try {
      final result = await widget.repository.claimMission(key);
      if (!mounted) return;
      setState(() {
        _future = Future.value(result);
        _notice = '+${result['xp']} ${widget.strings.text('xp')}';
      });
    } catch (_) {
      if (mounted) setState(() => _notice = widget.strings.text('error'));
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(strings.text('error'));
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final missions = (snapshot.data!['missions'] as List? ?? const [])
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _notice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: yummyDeep,
                  ),
                ),
              ),
            for (final mission in missions)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.text('mission_${mission['key']}'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                minHeight: 8,
                                value: math.min(
                                  1,
                                  ((mission['progress'] as num?) ?? 0) /
                                      math.max(
                                        1,
                                        (mission['target'] as num?) ?? 1,
                                      ),
                                ),
                                color: yummyGold,
                                backgroundColor: const Color(0x22000000),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${mission['progress']} / ${mission['target']}  ·  +${mission['xp']} ${strings.text('xp')}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      mission['claimed'] == true
                          ? Chip(label: Text(strings.text('claimed')))
                          : FilledButton(
                              onPressed: _claiming == null &&
                                      ((mission['progress'] as num?) ?? 0) >=
                                          ((mission['target'] as num?) ?? 1)
                                  ? () => _claim(mission['key'].toString())
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: yummyGold,
                                foregroundColor: yummyInk,
                              ),
                              child: Text(strings.text('claim')),
                            ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// What the player chose for autoplay. Limits are multiples of the total bet.
class YummyAutoSettings {
  final int spins;
  final int? lossLimitX, winLimitX;
  final bool stopOnFreeSpins;
  const YummyAutoSettings({
    required this.spins,
    this.lossLimitX,
    this.winLimitX,
    this.stopOnFreeSpins = true,
  });
}

/// The autoplay sheet body. Pops with a [YummyAutoSettings] on start.
class YummyAutoplaySheet extends StatefulWidget {
  final YummyStrings strings;
  final int totalBet;
  const YummyAutoplaySheet({
    super.key,
    required this.strings,
    required this.totalBet,
  });

  @override
  State<YummyAutoplaySheet> createState() => _YummyAutoplaySheetState();
}

class _YummyAutoplaySheetState extends State<YummyAutoplaySheet> {
  int _spins = 10;
  int? _loss = 25, _win;
  bool _stopOnFree = true;

  Widget _chips<T>(
    String title,
    List<T> values,
    T selected,
    String Function(T) label,
    void Function(T) pick,
  ) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final value in values)
                  ChoiceChip(
                    label: Text(label(value)),
                    selected: value == selected,
                    onSelected: (_) => setState(() => pick(value)),
                  ),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    String limit(int? x) =>
        x == null ? strings.text('none') : '${x * widget.totalBet}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chips<int>(
          strings.text('autoSpins'),
          const [10, 25, 50, 100],
          _spins,
          (v) => '$v',
          (v) => _spins = v,
        ),
        _chips<int?>(
          strings.text('lossLimit'),
          const [null, 10, 25, 50, 100],
          _loss,
          limit,
          (v) => _loss = v,
        ),
        _chips<int?>(
          strings.text('winLimit'),
          const [null, 10, 50, 100],
          _win,
          limit,
          (v) => _win = v,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.text('stopOnFree')),
          value: _stopOnFree,
          onChanged: (v) => setState(() => _stopOnFree = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            YummyAutoSettings(
              spins: _spins,
              lossLimitX: _loss,
              winLimitX: _win,
              stopOnFreeSpins: _stopOnFree,
            ),
          ),
          icon: const Icon(Icons.autorenew),
          label: Text(strings.text('startAuto')),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            backgroundColor: yummyDeep,
          ),
        ),
        const SizedBox(height: 8),
        Text(strings.text('autoHelp'), style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

/// Autoplay bookkeeping, kept apart from the widget so it can be tested.
class YummyAutoplay {
  final YummyAutoSettings settings;
  final int startBalance;
  int left;
  String? stoppedBy;
  YummyAutoplay(this.settings, this.startBalance) : left = settings.spins;

  /// Call after each settled round. Returns true to keep going.
  bool next({
    required int balance,
    required int totalBet,
    required int prize,
    required bool freeSpins,
  }) {
    left--;
    final loss = startBalance - balance;
    final lossLimit = settings.lossLimitX;
    final winLimit = settings.winLimitX;
    if (settings.stopOnFreeSpins && freeSpins) {
      stoppedBy = 'freeSpins';
    } else if (winLimit != null && prize >= winLimit * totalBet) {
      stoppedBy = 'win';
    } else if (lossLimit != null && loss >= lossLimit * totalBet) {
      stoppedBy = 'loss';
    } else if (balance < totalBet) {
      stoppedBy = 'balance';
    } else if (left <= 0) {
      stoppedBy = 'done';
    }
    return stoppedBy == null;
  }
}

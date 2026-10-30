import 'package:flutter/material.dart';
import 'dart:async';
import 'fruit_wheel_art.dart';
import 'fruit_wheel_engine.dart';
import 'fruit_wheel_strings.dart';

/// Bottom sheets and the timed winners popup for FRUIT WHEEL. Material sheets give
/// focus containment, Escape/back to close and one-at-a-time stacking.
Future<T?> fruitSheet<T>(
  BuildContext context,
  FruitWheelStrings strings,
  String title,
  Widget body,
) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: fwPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: fwGold, width: 1.5),
      ),
      builder: (context) => Directionality(
        textDirection: strings.ar ? TextDirection.rtl : TextDirection.ltr,
        child: DefaultTextStyle.merge(
          style:
              const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: fwGold,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: strings.text('close'),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

class FruitHelp extends StatelessWidget {
  final FruitWheelStrings strings;
  final Map<String, dynamic> layout;
  final FruitWheelState? state;
  const FruitHelp({
    super.key,
    required this.strings,
    required this.layout,
    this.state,
  });
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final key in [
            'rules',
            'odds',
            'poolHelp',
            'repeatHelp',
            'fairHelp',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(strings.text(key)),
            ),
          Text(
            '${strings.text('limits')}: 100 – ${layout['maxPerKey'] ?? 1000000}',
          ),
          if (state != null) ...[
            const SizedBox(height: 12),
            Text(
              '${strings.text('seedHash')}:',
              style: const TextStyle(color: fwGold),
            ),
            SelectableText(state!.seedHash),
            if (state!.seed != null) ...[
              Text(
                '${strings.text('revealed')}:',
                style: const TextStyle(color: fwGold),
              ),
              SelectableText(state!.seed!),
            ],
          ],
          const SizedBox(height: 12),
          Text(strings.footer, style: const TextStyle(color: fwMuted)),
        ],
      );
}

class FruitHistory extends StatelessWidget {
  final FruitWheelStrings strings;
  final List<Map<String, dynamic>> rounds;
  const FruitHistory({super.key, required this.strings, required this.rounds});
  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (rounds.isEmpty) Text(strings.text('emptyHistory')),
          for (final r in rounds)
            ListTile(
              leading: r['result'] == null
                  ? const SizedBox.square(
                      dimension: 40,
                      child: Icon(Icons.remove, color: fwMuted),
                    )
                  : fruitHistoryOutcomes(r).isEmpty
                      ? FruitArt(r['result'].toString(), size: 40)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final card in fruitHistoryOutcomes(r))
                              FruitArt(card, size: 28),
                          ],
                        ),
              title: Text(
                strings.round((r['round'] as num?)?.toInt() ?? 0),
                style: const TextStyle(color: fwCream),
              ),
              subtitle: Text(
                '${strings.text('bet')}: ${r['bet']} • ${r['at']}',
                style: const TextStyle(color: fwMuted),
              ),
              trailing: Text(
                '${strings.text('prize')}: ${r['prize']}',
                style: const TextStyle(color: fwGold),
              ),
            ),
        ],
      );
}

class FruitWinners extends StatefulWidget {
  final FruitWheelStrings strings;
  final List<Map<String, dynamic>> winners;
  final int staked, payout;
  final List<String> results;
  final Map<String, double> multipliers;
  final Duration duration;
  const FruitWinners({
    super.key,
    required this.strings,
    required this.winners,
    required this.staked,
    required this.payout,
    this.results = const [],
    this.multipliers = fruitMultipliers,
    required this.duration,
  });
  @override
  State<FruitWinners> createState() => _FruitWinnersState();
}

class _FruitWinnersState extends State<FruitWinners> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (mounted) {
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Directionality(
      textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: fwPurpleDeep,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: fwGold, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.text('goodLuck'),
                style: const TextStyle(
                  color: fwGold,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final card in widget.results)
                Text(
                  '${s.text(card)} ${fruitMultiplierLabel(widget.multipliers[card] ?? fruitMultipliers[card]!)}',
                  style: const TextStyle(color: fwCream, fontSize: 18),
                ),
              for (final w in widget.winners.take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: fruitAvatar(
                    w['avatarUrl']?.toString(),
                    w['name']?.toString() ?? '',
                    40,
                  ),
                  title: Text(
                    w['name']?.toString() ?? '',
                    style: const TextStyle(color: fwCream),
                  ),
                  subtitle: Text(
                    '${s.text('bet')}: ${w['staked']}   ${s.text('win')}: ${w['payout']}',
                    style: const TextStyle(color: fwGold),
                  ),
                ),
              const Divider(color: fwGold),
              Text(
                '${s.text('yourBet')}: ${widget.staked}   ${s.text('win')}: ${widget.payout}',
                style: const TextStyle(color: fwCream),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.text('close')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FruitSettings extends StatefulWidget {
  final FruitWheelStrings strings;
  final bool sound, motion;
  final ValueChanged<bool> onArabic, onSound, onMotion;
  const FruitSettings({
    super.key,
    required this.strings,
    required this.sound,
    required this.motion,
    required this.onArabic,
    required this.onSound,
    required this.onMotion,
  });
  @override
  State<FruitSettings> createState() => _FruitSettingsState();
}

class _FruitSettingsState extends State<FruitSettings> {
  late bool _sound = widget.sound, _motion = widget.motion;
  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.text('language'), style: const TextStyle(color: fwMuted)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(s.text('arabic'))),
            ButtonSegment(value: false, label: Text(s.text('english'))),
          ],
          selected: {s.ar},
          onSelectionChanged: (v) {
            widget.onArabic(v.first);
            Navigator.pop(context);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: fwGold,
          title: Text(
            s.text('sound'),
            style: const TextStyle(color: Colors.white),
          ),
          value: _sound,
          onChanged: (v) {
            setState(() => _sound = v);
            widget.onSound(v);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: fwGold,
          title: Text(
            s.text('motion'),
            style: const TextStyle(color: Colors.white),
          ),
          value: _motion,
          onChanged: (v) {
            setState(() => _motion = v);
            widget.onMotion(v);
          },
        ),
      ],
    );
  }
}

/// Daily net winners.
class FruitLeaders extends StatelessWidget {
  final FruitWheelStrings strings;
  final List<Map<String, dynamic>> entries;
  final int? myRank;
  final int myWon;
  final Duration? resetsIn;
  const FruitLeaders({
    super.key,
    required this.strings,
    required this.entries,
    required this.myRank,
    required this.myWon,
    this.resetsIn,
  });

  String? get _resets {
    final d = resetsIn;
    if (d == null) return null;
    final safe = d.isNegative ? Duration.zero : d;
    String two(int v) => v.toString().padLeft(2, '0');
    return safe.inDays > 0
        ? '${safe.inDays}d ${two(safe.inHours % 24)}:${two(safe.inMinutes % 60)}'
        : '${two(safe.inHours)}:${two(safe.inMinutes % 60)}';
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child:
                  Text(strings.text('emptyBoard'), textAlign: TextAlign.center),
            ),
          for (final e in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 72,
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${e['rank']}',
                        style: const TextStyle(
                          color: fwGold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    fruitAvatar(
                      e['avatarUrl']?.toString(),
                      e['name']?.toString() ?? '',
                      40,
                    ),
                  ],
                ),
              ),
              title: Text(
                e['name']?.toString() ?? '',
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                fruitCompact((e['net'] as num?)?.toInt() ?? 0),
                style:
                    const TextStyle(color: fwGold, fontWeight: FontWeight.w800),
              ),
            ),
          const Divider(color: fwPurpleLight),
          Text(
            '${strings.text('weekRank')}: ${strings.rank(myRank)} · ${fruitCompact(myWon)}',
            style: const TextStyle(color: fwCream),
          ),
          if (_resets != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${strings.text('resetsIn')} $_resets',
                style: const TextStyle(color: fwMuted, fontSize: 12),
              ),
            ),
        ],
      );
}

Widget fruitAvatar(String? url, String name, double size) {
  final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
  final fallback = CircleAvatar(
    radius: size / 2,
    backgroundColor: fwPurple,
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

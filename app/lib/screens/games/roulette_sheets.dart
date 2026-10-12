import 'package:flutter/material.dart';
import 'roulette_art.dart';
import 'roulette_engine.dart';
import 'roulette_strings.dart';

/// Bottom sheets for الروليت. Material sheets give focus containment,
/// Escape/back to close and one-at-a-time stacking.
Future<T?> rouletteSheet<T>(
        BuildContext context, RouletteStrings s, String title, Widget body,) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: rlNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: rlGold, width: 1.5),
      ),
      builder: (context) => Directionality(
        textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
        child: DefaultTextStyle.merge(
          style:
              const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .85,),
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
                                color: rlGold,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,),
                          ),
                        ),
                        IconButton(
                          tooltip: s.text('close'),
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

/// A small coloured ball with a number on it.
Widget rouletteBall(int n, {double size = 26, bool ring = false}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: roulettePaint(n),
        border: Border.all(
            color: ring ? rlGold : Colors.white24, width: ring ? 2.5 : 1,),
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800,),),
        ),
      ),
    );

class RouletteHelp extends StatelessWidget {
  final RouletteStrings strings;
  final String seedHash;
  final String? seed;
  final List<int> history;
  const RouletteHelp(
      {super.key,
      required this.strings,
      required this.seedHash,
      this.seed,
      this.history = const [],});

  @override
  Widget build(BuildContext context) {
    final s = strings;
    const rows = [
      ('straight', 'n:17', 1),
      ('split', 'split:17-20', 2),
      ('street', 'street:16', 3),
      ('corner', 'corner:16-17-19-20', 4),
      ('firstFour', 'ff', 4),
      ('sixLine', 'six:16', 6),
      ('dozen1', 'dozen1', 12),
      ('column1', 'column1', 12),
      ('red', 'red', 18),
    ];
    Widget cell(String t, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            t,
            style: TextStyle(
                color: head ? rlGold : Colors.white,
                fontWeight: head ? FontWeight.w800 : FontWeight.w500,),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.text('rules')),
        const SizedBox(height: 10),
        Text(s.text('rulesZero')),
        const SizedBox(height: 10),
        Text(s.text('rulesPay')),
        const SizedBox(height: 12),
        Text(s.text('paytable'),
            style: const TextStyle(
                color: rlGold, fontWeight: FontWeight.w800, fontSize: 16,),),
        Table(
          border: const TableBorder.symmetric(
              inside: BorderSide(color: Colors.white12),),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.3),
          },
          children: [
            TableRow(children: [
              cell('', head: true),
              cell(s.text('covers'), head: true),
              cell(s.text('payout'), head: true),
            ],),
            for (final (name, key, covers) in rows)
              TableRow(
                children: [
                  cell(
                    name == 'dozen1'
                        ? '${s.text('dozen1')} / ${s.text('dozen2')} / ${s.text('dozen3')}'
                        : name == 'column1'
                            ? (s.ar ? 'عمود (2:1)' : 'Column (2:1)')
                            : name == 'red'
                                ? '${s.text('red')} · ${s.text('black')} · ${s.text('odd')} · ${s.text('even')} · 1–18 · 19–36'
                                : s.text(name),
                  ),
                  cell('$covers'),
                  cell('×${rouletteBet(key)!.multiplier}'),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(s.text('rulesFair')),
        const SizedBox(height: 6),
        Text(s.text('seedHash'), style: const TextStyle(color: rlMuted)),
        SelectableText(seedHash,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),),
        if (seed != null) ...[
          Text(s.text('seed'), style: const TextStyle(color: rlMuted)),
          SelectableText(seed!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(s.text('lastResults'),
              style:
                  const TextStyle(color: rlGold, fontWeight: FontWeight.w800),),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final n in history.reversed) rouletteBall(n, size: 28),
          ],),
          const SizedBox(height: 6),
          Text(s.text('statsNote'), style: const TextStyle(color: rlMuted)),
        ],
        const SizedBox(height: 14),
        Text(s.footer, style: const TextStyle(color: rlMuted)),
      ],
    );
  }
}

class RouletteHistoryView extends StatelessWidget {
  final RouletteStrings strings;
  final List<Map<String, dynamic>> rounds;
  const RouletteHistoryView(
      {super.key, required this.strings, required this.rounds,});
  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(24),
          child:
              Text(strings.text('emptyHistory'), textAlign: TextAlign.center),);
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return Column(
      children: [
        for (final r in rounds)
          Builder(
            builder: (_) {
              final at =
                  DateTime.tryParse(r['at']?.toString() ?? '')?.toLocal();
              final prize = (r['prize'] as num?)?.toInt() ?? 0;
              final stakes =
                  Map<String, dynamic>.from(r['stakes'] as Map? ?? const {});
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(12),),
                child: Row(
                  children: [
                    rouletteBall((r['result'] as num?)?.toInt() ?? 0, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${strings.round((r['round'] as num?)?.toInt() ?? 0)}${at == null ? '' : ' · ${two(at.hour)}:${two(at.minute)}'}',
                            style:
                                const TextStyle(color: rlMuted, fontSize: 13),
                          ),
                          Text(
                            stakes.entries
                                .map((e) => '${strings.bet(e.key)} ${e.value}')
                                .join('، '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      prize > 0 ? '+$prize' : '0',
                      style: TextStyle(
                          color: prize > 0 ? rlFeltBorder : rlMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

Widget rouletteAvatar(String? url, String name, double size) {
  final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
  final fallback = CircleAvatar(
    radius: size / 2,
    backgroundColor: rlPurple,
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

/// Ranked rows: avatar, name, a number on the end.
class RouletteBoard extends StatelessWidget {
  final RouletteStrings strings;
  final List<Map<String, dynamic>> rows;
  final String valueKey, empty;
  final Widget? footer;
  const RouletteBoard({
    super.key,
    required this.strings,
    required this.rows,
    required this.valueKey,
    required this.empty,
    this.footer,
  });
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Padding(
                padding: const EdgeInsets.all(20),
                child: Text(strings.text(empty), textAlign: TextAlign.center),),
          for (final (i, e) in rows.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 76,
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text('${e['rank'] ?? i + 1}',
                          style: const TextStyle(
                              color: rlGold, fontWeight: FontWeight.w900,),),
                    ),
                    rouletteAvatar(e['avatarUrl']?.toString(),
                        e['name']?.toString() ?? '', 40,),
                  ],
                ),
              ),
              title: Text(e['name']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,),
              trailing: Text(
                rouletteCompact((e[valueKey] as num?)?.toInt() ?? 0),
                style:
                    const TextStyle(color: rlGold, fontWeight: FontWeight.w800),
              ),
            ),
          if (footer != null) ...[
            const Divider(color: Colors.white24),
            footer!,
          ],
        ],
      );
}

class RouletteSettings extends StatefulWidget {
  final RouletteStrings strings;
  final bool sound, motion;
  final ValueChanged<bool> onArabic, onSound, onMotion;
  const RouletteSettings({
    super.key,
    required this.strings,
    required this.sound,
    required this.motion,
    required this.onArabic,
    required this.onSound,
    required this.onMotion,
  });
  @override
  State<RouletteSettings> createState() => _RouletteSettingsState();
}

class _RouletteSettingsState extends State<RouletteSettings> {
  late bool _sound = widget.sound, _motion = widget.motion;
  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.text('language'), style: const TextStyle(color: rlMuted)),
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
          activeThumbColor: rlGold,
          title: Text(s.text('sound'),
              style: const TextStyle(color: Colors.white),),
          value: _sound,
          onChanged: (v) {
            setState(() => _sound = v);
            widget.onSound(v);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: rlGold,
          title: Text(s.text('motion'),
              style: const TextStyle(color: Colors.white),),
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

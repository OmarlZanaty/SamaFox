import 'package:flutter/material.dart';
import 'car_wheel_art.dart';
import 'car_wheel_engine.dart';
import 'car_wheel_strings.dart';

/// Bottom sheets for عجلة السيارات. Material sheets give focus containment,
/// Escape/back to close and one-at-a-time stacking.
Future<T?> carWheelSheet<T>(
  BuildContext context,
  CarWheelStrings s,
  String title,
  Widget body,
) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cwNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: cwGold, width: 1.5),
      ),
      builder: (context) => Directionality(
        textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
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
                              color: cwGold,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
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

/// The same emblem is used in the wheel, history and paytable.
Widget carWheelBadge(String key, {double size = 30}) => Tooltip(
    message: carWheelBet(key)?.name ?? key,
    child: CarWheelEmblem(segment: key, size: size),);

class CarWheelHelp extends StatelessWidget {
  final CarWheelStrings strings;
  final String seedHash;
  final String? seed;
  final List<String> history;
  final bool paytable;
  const CarWheelHelp(
      {super.key,
      required this.strings,
      required this.seedHash,
      this.seed,
      this.history = const [],
      this.paytable = false,});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!paytable) ...[
          Text(strings.text('rules')),
          const SizedBox(height: 10),
          Text(strings.text('rulesZero')),
          const SizedBox(height: 10),
        ],
        Text(strings.text('rulesPay')),
        const SizedBox(height: 12),
        for (final b in carWheelSegments)
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: carWheelBadge(b.key),
              title: Text(b.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                  '${strings.text('chance')}: ${(b.chance * 100).toStringAsFixed(2)}%',
                  style: const TextStyle(color: cwMuted),),
              trailing: Text('×${b.multiplier}',
                  style: const TextStyle(color: cwGold, fontSize: 20),),),
        Text(strings.text('rulesFair')),
        const SizedBox(height: 10),
        Text(strings.text('seedHash'), style: const TextStyle(color: cwMuted)),
        SelectableText(seedHash,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),),
        if (seed != null) ...[
          Text(strings.text('seed'), style: const TextStyle(color: cwMuted)),
          SelectableText(seed!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),),
        ],
        const SizedBox(height: 12),
        Wrap(
            spacing: 5,
            children: [for (final key in history.reversed) carWheelBadge(key)],),
        Text(strings.text('statsNote'), style: const TextStyle(color: cwMuted)),
        const SizedBox(height: 12),
        Text(strings.footer, style: const TextStyle(color: cwMuted)),
      ],);
}

class CarWheelHistoryView extends StatelessWidget {
  final CarWheelStrings strings;
  final List<Map<String, dynamic>> rounds;
  const CarWheelHistoryView({
    super.key,
    required this.strings,
    required this.rounds,
  });
  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(strings.text('emptyHistory'), textAlign: TextAlign.center),
      );
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    carWheelBadge(r['result']?.toString() ?? '', size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${strings.round((r['round'] as num?)?.toInt() ?? 0)} · ${strings.bet(r['result']?.toString() ?? '')}${at == null ? '' : ' · ${two(at.hour)}:${two(at.minute)}'}',
                            style:
                                const TextStyle(color: cwMuted, fontSize: 13),
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
                        color: prize > 0 ? cwGold : cwMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
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

Widget carWheelAvatar(String? url, String name, double size) {
  final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
  final fallback = CircleAvatar(
    radius: size / 2,
    backgroundColor: cwPurple,
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
class CarWheelBoard extends StatelessWidget {
  final CarWheelStrings strings;
  final List<Map<String, dynamic>> rows;
  final String valueKey, empty;
  final Widget? footer;
  const CarWheelBoard({
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
              child: Text(strings.text(empty), textAlign: TextAlign.center),
            ),
          for (final (i, e) in rows.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 76,
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${e['rank'] ?? i + 1}',
                        style: const TextStyle(
                          color: cwGold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    carWheelAvatar(
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
                carWheelCompact((e[valueKey] as num?)?.toInt() ?? 0),
                style:
                    const TextStyle(color: cwGold, fontWeight: FontWeight.w800),
              ),
            ),
          if (footer != null) ...[
            const Divider(color: Colors.white24),
            footer!,
          ],
        ],
      );
}

class CarWheelSettings extends StatefulWidget {
  final CarWheelStrings strings;
  final bool sound, motion;
  final ValueChanged<bool> onArabic, onSound, onMotion;
  const CarWheelSettings({
    super.key,
    required this.strings,
    required this.sound,
    required this.motion,
    required this.onArabic,
    required this.onSound,
    required this.onMotion,
  });
  @override
  State<CarWheelSettings> createState() => _CarWheelSettingsState();
}

class _CarWheelSettingsState extends State<CarWheelSettings> {
  late bool _sound = widget.sound, _motion = widget.motion;
  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.text('language'), style: const TextStyle(color: cwMuted)),
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
          activeThumbColor: cwGold,
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
          activeThumbColor: cwGold,
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

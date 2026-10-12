import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../repositories/fruit_wheel_repository.dart';
import 'fruit_wheel_art.dart';
import 'fruit_wheel_engine.dart';
import 'fruit_wheel_sfx.dart';
import 'fruit_wheel_strings.dart';

/// Bottom sheets and the bonus dialog for FRUIT WHEEL. Material sheets give
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
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
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

class FruitHelp extends StatefulWidget {
  final FruitWheelStrings strings;
  final Map<String, dynamic> layout;
  final FruitWheelRepository repository;
  const FruitHelp({
    super.key,
    required this.strings,
    required this.layout,
    required this.repository,
  });
  @override
  State<FruitHelp> createState() => _FruitHelpState();
}

class _FruitHelpState extends State<FruitHelp> {
  Map<String, dynamic>? _fair;
  String? _revealed;
  bool _busy = false;
  FruitWheelStrings get s => widget.strings;

  @override
  void initState() {
    super.initState();
    widget.repository.fairness().then((r) {
      if (mounted) setState(() => _fair = Map.from(r['fairness'] as Map));
    }).catchError((Object _) {});
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      final r = await widget.repository.rotateSeed();
      final fair = await widget.repository.fairness();
      if (!mounted) return;
      setState(() {
        _revealed = (r['revealed'] as Map?)?['serverSeed']?.toString();
        _fair = Map.from(fair['fairness'] as Map);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final rtp = ((layout['mathRtp'] as num?)?.toDouble() ?? .694) * 100;
    Widget card(String key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              FruitArt(key, size: 40),
              const SizedBox(width: 10),
              Expanded(child: Text(s.text(key))),
              Text(
                '×${fruitMultipliers[key]}',
                style: const TextStyle(
                  color: fwGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        );
    Widget seedRow(String label, String? value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: fwMuted)),
              SelectableText(
                value ?? '…',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.text('rules')),
        const SizedBox(height: 10),
        for (final c in fruitCards) card(c),
        card2(),
        const SizedBox(height: 10),
        for (final key in ['odds', 'bonusHelp', 'repeatHelp', 'stopHelp'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(s.text(key)),
          ),
        Text('${s.text('rtp')}: ${rtp.toStringAsFixed(1)}%'),
        Text(
          '${s.text('limits')}: ${layout['minBet']} – ${layout['maxBet']}',
        ),
        Text(
          '${s.text('dailyCap')}: ${layout['dailyMaxWinPerUser'] ?? s.text('unlimited')}',
        ),
        const Divider(color: fwPurpleLight, height: 28),
        Text(
          s.text('fairness'),
          style: const TextStyle(color: fwGold, fontWeight: FontWeight.w800),
        ),
        Text(s.text('fairHelp')),
        seedRow(s.text('seedHash'), _fair?['serverSeedHash']?.toString()),
        seedRow(s.text('clientSeed'), _fair?['clientSeed']?.toString()),
        seedRow(s.text('nonce'), _fair?['nonce']?.toString()),
        if (_revealed != null) seedRow(s.text('revealed'), _revealed),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _busy ? null : _rotate,
          style: OutlinedButton.styleFrom(
            foregroundColor: fwGold,
            side: const BorderSide(color: fwGold),
          ),
          child: Text(s.text('rotate')),
        ),
        const SizedBox(height: 14),
        Text(s.footer, style: const TextStyle(color: fwMuted)),
      ],
    );
  }

  Widget card2() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const FruitArt('bonus', size: 40),
            const SizedBox(width: 10),
            Expanded(child: Text(s.text('bonus'))),
            const Text(
              '×2 / ×3 / ×5',
              textDirection: TextDirection.ltr,
              style: TextStyle(color: fwGold, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
}

class FruitHistory extends StatelessWidget {
  final FruitWheelStrings strings;
  final List<FruitRound> rounds;
  const FruitHistory({super.key, required this.strings, required this.rounds});
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
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                FruitArt(r.outcome, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${strings.round(r.round)} · ${two(r.at.toLocal().hour)}:${two(r.at.toLocal().minute)}',
                        style: const TextStyle(color: fwMuted, fontSize: 13),
                      ),
                      Text('${strings.text('bet')}: ${r.totalBet}'),
                    ],
                  ),
                ),
                Text(
                  r.totalPrize > 0 ? '+${r.totalPrize}' : '0',
                  style: TextStyle(
                    color: r.totalPrize > 0 ? fwGreen : fwMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class FruitSettings extends StatefulWidget {
  final FruitWheelStrings strings;
  final bool sound, motion;
  final ValueChanged<bool> onArabic, onSound, onMotion;
  final VoidCallback onClearHistory;
  const FruitSettings({
    super.key,
    required this.strings,
    required this.sound,
    required this.motion,
    required this.onArabic,
    required this.onSound,
    required this.onMotion,
    required this.onClearHistory,
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
          title: Text(s.text('sound'), style: const TextStyle(color: Colors.white)),
          value: _sound,
          onChanged: (v) {
            setState(() => _sound = v);
            widget.onSound(v);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: fwGold,
          title: Text(s.text('motion'), style: const TextStyle(color: Colors.white)),
          value: _motion,
          onChanged: (v) {
            setState(() => _motion = v);
            widget.onMotion(v);
          },
        ),
        TextButton.icon(
          onPressed: () {
            widget.onClearHistory();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_sweep, color: fwPink),
          label: Text(s.text('clearHistory'), style: const TextStyle(color: fwPink)),
        ),
      ],
    );
  }
}

/// Weekly top winners.
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
              child: Text(strings.text('emptyBoard'), textAlign: TextAlign.center),
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
                        style: const TextStyle(color: fwGold, fontWeight: FontWeight.w900),
                      ),
                    ),
                    fruitAvatar(e['avatar']?.toString(), e['name']?.toString() ?? '', 40),
                  ],
                ),
              ),
              title: Text(
                e['name']?.toString() ?? '',
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                fruitCompact((e['won'] as num?)?.toInt() ?? 0),
                style: const TextStyle(color: fwGold, fontWeight: FontWeight.w800),
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

/// BONUS: three orbs; the tapped one reveals the value the server already
/// decided ([orbs] first), the other two show what they would have held.
class FruitBonusDialog extends StatefulWidget {
  final FruitWheelStrings strings;
  final List<int> orbs;
  final int prize;
  final FruitWheelSfx sfx;
  const FruitBonusDialog({
    super.key,
    required this.strings,
    required this.orbs,
    required this.prize,
    required this.sfx,
  });
  @override
  State<FruitBonusDialog> createState() => _FruitBonusDialogState();
}

class _FruitBonusDialogState extends State<FruitBonusDialog> {
  int? _picked;

  int _valueAt(int i) {
    final picked = _picked!;
    if (i == picked) return widget.orbs[0];
    final rest = widget.orbs.sublist(1);
    return rest[i < picked ? i : i - 1];
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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.text('bonusTitle'),
                style: const TextStyle(
                  color: fwGold,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _picked == null ? s.text('bonusPick') : '${s.text('bonusPrize')}: ${widget.prize}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < 3; i++)
                    Semantics(
                      button: true,
                      label: '${s.text('bonusPick')} ${i + 1}',
                      child: GestureDetector(
                        onTap: _picked != null
                            ? null
                            : () {
                                widget.sfx.orb();
                                HapticFeedback.mediumImpact();
                                setState(() => _picked = i);
                              },
                        child: AnimatedScale(
                          scale: _picked == i ? 1.15 : _picked == null ? 1 : .85,
                          duration: const Duration(milliseconds: 250),
                          child: Opacity(
                            opacity: _picked == null || _picked == i ? 1 : .5,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const FruitArt('orb', size: 74),
                                if (_picked != null)
                                  Text(
                                    s.orbValue(_valueAt(i)),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      shadows: [Shadow(blurRadius: 6)],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: fwPink,
                  minimumSize: const Size(160, 46),
                ),
                onPressed: _picked == null ? null : () => Navigator.pop(context),
                child: Text(s.text('continue')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

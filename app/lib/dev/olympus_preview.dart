// Developer preview harness for بوابات أوليمبوس (Gates of Olympus).
//
// Not part of the shipped app — a separate entrypoint used to eyeball the
// composition and the delivered artwork in the real widgets without a backend,
// a login or a coin balance:
//
//   flutter run -d chrome -t lib/dev/olympus_preview.dart
//
// It deliberately imports only the presentation widgets, so it pulls in none of
// the networking, storage or audio plugins and builds for web.
//
// The board below is a fixed hand-built layout, not a spin: it is arranged to
// put every symbol family, a scatter and three multipliers on screen at once so
// the whole symbol set can be judged in one look.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../screens/games/olympus_bonus.dart';
import '../screens/games/olympus_celebration.dart';
import '../screens/games/olympus_grid.dart';
import '../screens/games/olympus_symbols.dart';
import '../screens/games/olympus_strings.dart';
import '../screens/games/olympus_zeus.dart';

const _gold = Color(0xFFE3B84A);
const _boltBlue = Color(0xFF9FD8FF);
const _violetDeep = Color(0xFF12052B);
const _violetTop = Color(0xFF3A1A72);
const _panel = Color(0xCC1E0B44);

/// Every family on the board at once, with the winning group (eight blue gems)
/// spread around it the way a real pay-anywhere win looks.
const _board = <String?>[
  'GEM_BLUE', 'CROWN', 'GEM_GREEN', 'MULT', 'GEM_RED', 'GEM_BLUE',
  'CHALICE', 'GEM_BLUE', 'SCATTER', 'GEM_YELLOW', 'GEM_BLUE', 'RING',
  'GEM_PURPLE', 'HOURGLASS', 'GEM_BLUE', 'GEM_RED', 'MULT', 'GEM_GREEN',
  'GEM_BLUE', 'GEM_YELLOW', 'RING', 'GEM_BLUE', 'CROWN', 'GEM_PURPLE',
  'SCATTER', 'GEM_GREEN', 'MULT', 'CHALICE', 'HOURGLASS', 'GEM_RED',
];

const _winningCells = {0, 5, 7, 10, 14, 18, 21};
const _mults = {3: 25, 16: 5, 26: 100};

/// The backdrop is optional art; a missing file must not throw.
void _ignoreMissingArt(Object error, StackTrace? stack) {}

void main() => runApp(const OlympusPreviewApp());

class OlympusPreviewApp extends StatelessWidget {
  const OlympusPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        // Arabic, matching AppConfig.defaultLanguage - without this the harness
        // falls back to en and tests a language no player sees.
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar', ''), Locale('en', '')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'ElMessiri'),
        ),
        home: const OlympusPreview(),
      );
}

class OlympusPreview extends StatefulWidget {
  const OlympusPreview({super.key});

  @override
  State<OlympusPreview> createState() => _OlympusPreviewState();
}

class _OlympusPreviewState extends State<OlympusPreview> {
  OlympusArt? _art;
  bool _arabic = true;
  bool _highContrast = false;
  bool _inBonus = false;
  ZeusMood _mood = ZeusMood.idle;
  String? _celebration;

  @override
  void initState() {
    super.initState();
    OlympusArt.load().then((art) {
      if (mounted) setState(() => _art = art);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = OlympusStrings(ar: _arabic);

    return Directionality(
      textDirection: s.direction,
      child: Scaffold(
        backgroundColor: _violetDeep,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_violetTop, _violetDeep],
            ),
            // Same treatment as the real screen, so the preview is a fair test
            // of how a delivered backdrop sits under the board.
            image: DecorationImage(
              image: AssetImage('assets/images/olympus/bg_olympus.png'),
              fit: BoxFit.cover,
              opacity: 0.6,
              onError: _ignoreMissingArt,
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _topBar(s),
                    Expanded(child: _playfield(s)),
                    _bottomBar(s),
                    _devBar(),
                  ],
                ),
                if (_celebration != null)
                  Positioned.fill(
                    child: OlympusCelebration(
                      tier: _celebration!,
                      amount: 24680,
                      bet: 100,
                      strings: s,
                      art: _art,
                      onDone: () => setState(() => _celebration = null),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(OlympusStrings s) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: Row(
          children: [
            const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            _chip(Icons.monetization_on_rounded, '128,400', _gold),
            const SizedBox(width: 6),
            _chip(Icons.diamond_rounded, '1,284', _boltBlue),
            const Spacer(),
            _chip(Icons.fast_forward_rounded, '×1.5', Colors.orangeAccent),
            const SizedBox(width: 6),
            const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 20),
            const SizedBox(width: 10),
            const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
            const SizedBox(width: 10),
            const Icon(Icons.help_outline_rounded, color: Colors.white70, size: 20),
          ],
        ),
      );

  Widget _chip(IconData icon, String value, Color color) => Container(
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );

  // Pinned to LTR to match the real screen: the composition is Zeus on the
  // right, and RTL must not flip it.
  Widget _playfield(OlympusStrings s) => Directionality(
        textDirection: TextDirection.ltr,
        child: _playfieldBody(s),
      );

  Widget _playfieldBody(OlympusStrings s) => LayoutBuilder(
        builder: (context, constraints) {
          final landscape = constraints.maxWidth > constraints.maxHeight * 1.25;
          final board = OlympusGrid(
            cols: 6,
            rows: 5,
            grid: _board,
            nameOf: s.symbol,
            scatterBadge: s.scatterBadge,
            highlighted: _winningCells,
            multValues: _mults,
            highContrast: _highContrast,
            art: _art,
          );

          if (!landscape) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: constraints.maxHeight * 0.20,
                    child: Row(
                      children: [
                        Expanded(child: _rail(s, compact: false)),
                        SizedBox(
                          width: constraints.maxWidth * 0.32,
                          child: ZeusStage(mood: _mood, art: _art),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
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
                SizedBox(
                  width: 140,
                  child: Center(child: _rail(s, compact: true)),
                ),
                Expanded(child: Center(child: board)),
                SizedBox(
                  width: 220,
                  child: ZeusStage(mood: _mood, art: _art),
                ),
              ],
            ),
          );
        },
      );

  Widget _rail(OlympusStrings s, {required bool compact}) {
    if (_inBonus) {
      return OlympusBonusHud(spinsLeft: 11, meter: 83, strings: s, compact: compact);
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: 8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat(s.sequenceWin, '1,240', Colors.white),
          const SizedBox(height: 12),
          _stat(s.tumbles, '3', Colors.white54),
          const SizedBox(height: 12),
          _stat(s.multiplier, '×130', _gold, big: true),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, {bool big = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 9, height: 1.2),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: color,
              fontSize: big ? 22 : 17,
              fontWeight: FontWeight.w900,
              shadows: big ? const [Shadow(color: Color(0x99E3B84A), blurRadius: 14)] : null,
            ),
          ),
        ],
      );

  Widget _bottomBar(OlympusStrings s) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(
          children: [
            _betControl(s),
            const SizedBox(width: 10),
            _readout(s.totalWin, '24,680', _gold),
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              height: 46,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: _gold.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {},
                child: Text(
                  s.auto,
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7B27C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: const BorderSide(color: _gold, width: 1.4),
                  ),
                  onPressed: () {},
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_rounded, color: _gold, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        s.spin,
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
            ),
          ],
        ),
      );

  Widget _betControl(OlympusStrings s) => Container(
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
            const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.totalBet,
                  style: const TextStyle(color: Colors.white38, fontSize: 8),
                ),
                const Text(
                  '100',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.add_circle_outline, color: Colors.white70, size: 20),
          ],
        ),
      );

  Widget _readout(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _boltBlue.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8)),
            Text(
              value,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );

  /// Preview-only controls. Never shipped — this file is its own entrypoint.
  Widget _devBar() => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _devButton(_arabic ? 'EN' : 'AR', () => setState(() => _arabic = !_arabic)),
                _devButton('contrast', () => setState(() => _highContrast = !_highContrast)),
                _devButton('bonus', () => setState(() => _inBonus = !_inBonus)),
                for (final m in ZeusMood.values)
                  _devButton(m.name, () => setState(() => _mood = m)),
                for (final tier in ['NICE_WIN', 'BIG_WIN', 'MEGA_WIN', 'EPIC_WIN'])
                  _devButton(tier, () => setState(() => _celebration = tier)),
              ],
            ),
          ),
        ),
      );

  Widget _devButton(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onTap,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      );
}

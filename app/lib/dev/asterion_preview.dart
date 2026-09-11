// Developer preview harness for the أستيريون artwork.
//
// Not part of the shipped app — a separate entrypoint used to eyeball the
// painted symbols, the guardian and the board in the real widgets without a
// backend, a login or a coin balance:
//
//   flutter run -d chrome -t lib/dev/asterion_preview.dart
//
// It deliberately imports only the presentation widgets, so it pulls in none of
// the networking or audio plugins and builds for web. test/asterion_render_test
// drives the same harness headlessly and writes PNGs.

import 'package:flutter/material.dart';

import '../screens/games/asterion_art.dart';
import '../screens/games/asterion_board.dart';
import '../screens/games/asterion_celebration.dart';
import '../screens/games/asterion_trial.dart';

void main() => runApp(const AsterionPreviewApp());

/// Which slice of the game to draw.
enum PreviewScene {
  /// The board mid-cascade, with a win highlighted and two orbs pinned.
  board,

  /// Every symbol at review size, on the dark ground they sit on in play.
  symbols,

  /// The free-spin entry.
  trial,

  /// The top celebration tier.
  celebration,
}

class AsterionPreviewApp extends StatelessWidget {
  const AsterionPreviewApp({
    super.key,
    this.scene = PreviewScene.board,
    this.highContrast = false,
  });

  final PreviewScene scene;

  /// Renders with the High Contrast accessibility option on.
  final bool highContrast;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'ElMessiri'),
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AsterionPreview(scene: scene, highContrast: highContrast),
        ),
      );
}

class AsterionPreview extends StatefulWidget {
  const AsterionPreview({super.key, this.scene = PreviewScene.board, this.highContrast = false});

  final PreviewScene scene;
  final bool highContrast;

  @override
  State<AsterionPreview> createState() => _AsterionPreviewState();
}

class _AsterionPreviewState extends State<AsterionPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _sky = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  // A board frozen at an interesting moment: eight prism shards lit, two Storm
  // Orbs pinned, one crest showing.
  static const _grid = <String?>[
    'L1', 'H2', 'L1', 'ORB', 'L3', 'H1', //
    'L1', 'L4', 'H3', 'L2', 'L1', 'CREST',
    'H4', 'L1', 'L2', 'L1', 'H2', 'L3',
    'L1', 'ORB', 'L4', 'H1', 'L1', 'L2',
    'L2', 'H3', 'L1', 'L3', 'H4', 'L4',
  ];

  static const _orbs = {3: 25, 19: 10};

  static const _wins = {0, 2, 6, 10, 13, 15, 18, 22, 26};

  @override
  void dispose() {
    _sky.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsterionPalette.nightDeep,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _sky,
              builder: (_, __) => CitadelBackdrop(
                drift: _sky.value,
                stormy: widget.scene == PreviewScene.trial,
              ),
            ),
          ),
          SafeArea(child: _scene()),
          if (widget.scene == PreviewScene.trial)
            Positioned.fill(
              child: TrialTransition(spins: 15, crests: 4, onDone: () {}),
            ),
          if (widget.scene == PreviewScene.celebration)
            Positioned.fill(
              child: AsterionCelebration(
                tier: 'DIVINE_SURGE',
                amount: 48250,
                bet: 100,
                onDone: () {},
              ),
            ),
        ],
      ),
    );
  }

  Widget _scene() {
    if (widget.scene == PreviewScene.symbols) return _symbolSheet();
    // Mirrors AsterionScreen's portrait layout: the guardian takes the slack
    // the fixed-aspect board leaves, and the results strip closes the bottom.
    return Column(
      children: [
        const Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(child: _Meters()),
                SizedBox(
                  width: 150,
                  child: Guardian(mood: GuardianMood.strike, charge: 0.8),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AsterionBoard(
            cols: 6,
            rows: 5,
            grid: _grid,
            orbs: _orbs,
            highlighted: _wins,
            highContrast: widget.highContrast,
          ),
        ),
        const _FakeHistory(),
        const _FakeControls(),
      ],
    );
  }

  Widget _symbolSheet() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'رموز أستيريون',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                children: [
                  for (final id in [...kPayingSymbols, 'CREST'])
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SymbolIcon(id, size: 62),
                        const SizedBox(height: 4),
                        Text(
                          kAsterionSymbols[id]?.name ?? id,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  for (final v in [2, 25, 250])
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        StormOrb(value: v, size: 62),
                        const SizedBox(height: 4),
                        const Text(
                          'كرة العاصفة',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  for (final mood in GuardianMood.values)
                    Expanded(child: Guardian(mood: mood)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Meters extends StatelessWidget {
  const _Meters();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Stat('ربح الجولة', '1,420', AsterionPalette.cyanPale),
          SizedBox(height: 6),
          _Stat('المضاعف', '35x', AsterionPalette.magenta),
          SizedBox(height: 6),
          _Stat('التساقطات', '3', AsterionPalette.muted),
        ],
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.colour);
  final String label, value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
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
}

class _FakeHistory extends StatelessWidget {
  const _FakeHistory();

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Row(
          children: [
            for (final entry in const [
              ['1420', 'win'],
              ['—', 'loss'],
              ['48250', 'trial'],
              ['180', 'win'],
              ['—', 'loss'],
              ['640', 'win'],
            ])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: _colourFor(entry[1]).withValues(alpha: 0.14),
                    border: Border.all(color: _colourFor(entry[1]).withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    entry[0],
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: entry[1] == 'loss' ? AsterionPalette.muted : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  static Color _colourFor(String kind) => switch (kind) {
        'trial' => AsterionPalette.magenta,
        'win' => AsterionPalette.tide,
        _ => AsterionPalette.silverDeep,
      };
}

class _FakeControls extends StatelessWidget {
  const _FakeControls();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.black.withValues(alpha: 0.45),
                border: Border.all(color: AsterionPalette.silverDeep),
              ),
              child: const Text('الرهان 100', style: TextStyle(color: Colors.white)),
            ),
            const Spacer(),
            Container(
              width: 76,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [AsterionPalette.cyan, AsterionPalette.cyanDeep],
                ),
              ),
              child: const Center(
                child: Text(
                  'ابدأ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

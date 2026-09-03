// Developer preview harness for the أثيرفول artwork.
//
// Not part of the shipped app — a separate entrypoint used to eyeball the
// delivered assets in the real widgets without a backend, a login or a coin
// balance:
//
//   flutter run -d chrome -t lib/dev/aetherfall_preview.dart
//
// It deliberately imports only the presentation widgets, so it pulls in none of
// the networking or audio plugins and builds for web.

import 'package:flutter/material.dart';

import '../screens/games/aetherfall_bonus.dart';
import '../screens/games/aetherfall_celebration.dart';
import '../screens/games/aetherfall_symbols.dart';

const _bgTop = Color(0xFF0F1638);
const _bgBottom = Color(0xFF07030F);
const _cyan = Color(0xFF4DD8E6);
const _ember = Color(0xFFFF8A3D);
const _copper = Color(0xFFC98A4B);

void main() => runApp(const AetherfallPreviewApp());

class AetherfallPreviewApp extends StatelessWidget {
  const AetherfallPreviewApp({super.key, this.bonus = false, this.celebrate = false});

  final bool bonus;
  final bool celebrate;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'ElMessiri'),
        ),
        home: AetherfallPreview(bonus: bonus, celebrate: celebrate),
      );
}

class AetherfallPreview extends StatefulWidget {
  const AetherfallPreview({super.key, this.bonus = false, this.celebrate = false});

  final bool bonus;
  final bool celebrate;

  @override
  State<AetherfallPreview> createState() => _PreviewState();
}

class _PreviewState extends State<AetherfallPreview> {
  AetherfallArt? _art;
  late bool _bonus = widget.bonus;
  late bool _celebrate = widget.celebrate;
  bool _transition = false;

  static const _grid = [
    'L1', 'H4', 'L3', 'WILD', 'L2', 'H1',
    'L2', 'L1', 'KEY', 'L4', 'H2', 'L3',
    'CHARGE', 'L3', 'L1', 'H3', 'L1', 'L2',
    'H1', 'L4', 'L2', 'L1', 'KEY', 'H4',
    'L3', 'L1', 'H2', 'L2', 'L4', 'WILD',
  ];

  // The cells that would be lit by a winning L1 count.
  static const _highlighted = {0, 3, 7, 14, 16, 21, 25, 29, 12};

  @override
  void initState() {
    super.initState();
    AetherfallArt.load().then((a) {
      if (mounted) setState(() => _art = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBottom,
      body: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
          image: DecorationImage(
            image: AssetImage(
              _bonus
                  ? 'assets/images/aetherfall/bg_bonus_vault.png'
                  : 'assets/images/aetherfall/bg_observatory.png',
            ),
            fit: BoxFit.cover,
            opacity: 0.55,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: 380,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    children: [
                      _topBar(),
                      const SizedBox(height: 10),
                      Center(child: _heroPortrait()),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _chargeMeter(48),
                          const Spacer(),
                          _stat('SEQUENCE\nWIN', '4820', _cyan),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _board(),
                      const SizedBox(height: 12),
                      if (_bonus)
                        Center(
                          child: BonusHud(
                            tumblesLeft: 9,
                            chargeBank: 48,
                            locks: 2,
                            lockTarget: 3,
                            art: _art,
                          ),
                        ),
                      const SizedBox(height: 12),
                      _controls(),
                      const SizedBox(height: 16),
                      _toggles(),
                    ],
                  ),
                ),
              ),
              if (_transition)
                Positioned.fill(
                  child: SkyfireVaultTransition(
                    tumbles: 12,
                    art: _art,
                    onDone: () => setState(() => _transition = false),
                  ),
                ),
              if (_celebrate)
                Positioned.fill(
                  child: CelebrationOverlay(
                    tier: 'AETHERFALL',
                    amount: 48200,
                    art: _art,
                    onDone: () => setState(() => _celebrate = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Row(
        children: [
          const Text(
            'AETHERFALL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _copper.withValues(alpha: 0.6)),
            ),
            child: const Text('182,400', style: TextStyle(color: Colors.white)),
          ),
        ],
      );

  Widget _heroPortrait() {
    final asset = _bonus ? 'hero_portrait_bonus' : 'hero_portrait_idle';
    final color = _bonus ? _ember : _cyan;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.6),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 14)],
      ),
      child: ClipOval(
        child: Image.asset('assets/images/aetherfall/$asset.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _chargeMeter(int charge) => SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SKYFIRE\nCHARGE',
              style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1, height: 1.2),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                    child: LayoutBuilder(
                      builder: (context, c) => Container(
                        width: c.maxWidth * 0.55,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_ember, Color(0xFFFFD08A)]),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(color: _ember.withValues(alpha: 0.55), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/aetherfall/meter_frame.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Text(
                        '+$charge%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: _bgBottom, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _stat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1, height: 1.2),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _board() => AspectRatio(
        aspectRatio: 6 / 5,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemCount: 30,
          itemBuilder: (context, i) {
            final sym = _grid[i];
            return SymbolTile(
              symbol: sym,
              art: _art?.forSymbol(sym),
              chargeValue: sym == 'CHARGE' ? 12 : null,
              highlighted: _highlighted.contains(i),
            );
          },
        ),
      );

  Widget _controls() => Row(
        children: [
          Expanded(child: _skinned('btn_ignite', 'IGNITE', 52, _bgBottom)),
          const SizedBox(width: 10),
          SizedBox(width: 130, child: _skinned('btn_auto', 'AUTO', 52, Colors.white)),
        ],
      );

  Widget _skinned(String asset, String label, double h, Color textColor) => SizedBox(
        height: h,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Image.asset('assets/images/aetherfall/$asset.png', fit: BoxFit.fill),
            ),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _toggles() => Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: [
          OutlinedButton(
            onPressed: () => setState(() => _bonus = !_bonus),
            child: Text(_bonus ? 'base play' : 'bonus'),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _celebrate = true),
            child: const Text('celebration'),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _transition = true),
            child: const Text('vault transition'),
          ),
        ],
      );
}

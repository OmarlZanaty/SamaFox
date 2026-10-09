import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'games/aetherfall_screen.dart';
import 'games/asterion_screen.dart';
import 'games/crash_game_screen.dart';
import 'games/crazy_wheel_screen.dart';
import 'games/fruit_jackpot_screen.dart';
import 'games/fruit_wheel_screen.dart';
import 'games/neon_fortune_screen.dart';
import 'games/yummy_screen.dart';
import 'games/yummy_social.dart';
import 'games/yummy_strings.dart';
import 'games/olympus_screen.dart';
import 'games/greedy_cat_screen.dart';
import 'games/plinko_screen.dart';
import 'games/roulette_screen.dart';
import 'games/car_wheel_screen.dart';
// G3(a) — these four shipped but were parked out of the hub; they are back.

/// A grid of game tiles, three per row: the artwork cropped around its subject
/// and the name drawn on it. Titles stay in code rather than baked into the
/// artwork so they remain translatable and crisp at any density.
///
/// Every game's server side is live, so every card shows. A build can still
/// hide one with --dart-define=<FLAG>=false.
const bool _fruitJackpotEnabled =
    bool.fromEnvironment('FRUIT_JACKPOT', defaultValue: true);
const bool _yummyEnabled = bool.fromEnvironment('YUMMY', defaultValue: true);
const bool _fruitWheelEnabled =
    bool.fromEnvironment('FRUIT_WHEEL', defaultValue: true);
const bool _rouletteEnabled =
    bool.fromEnvironment('ROULETTE', defaultValue: true);
const bool _carWheelEnabled =
    bool.fromEnvironment('CAR_WHEEL', defaultValue: true);

const List<_GameEntry> _games = [
  if (_fruitJackpotEnabled)
  _GameEntry(
    title: 'جاكبوت الفواكه',
    tagline: 'اختر رهانك وأدر الفواكه',
    emoji: '🍒',
    accent: Color(0xFFFFD52B),
    gradient: [Color(0xFF3B176B), Color(0xFF190D35)],
    art: 'assets/images/cards/card_fruit_jackpot.png',
  ),
  _GameEntry(
    title: 'بلينكو',
    tagline: 'أسقط الكرة',
    emoji: '🎱',
    accent: Color(0xFF9C6BFF),
    gradient: [Color(0xFF1B0B3A), Color(0xFF4A148C)],
    art: 'assets/images/cards/card_plinko.png',
    focus: Alignment(0.45, 0),
  ),
  _GameEntry(
    title: 'عجلة الحظ',
    tagline: 'أدر واربح',
    emoji: '🎡',
    accent: Color(0xFFFFC107),
    gradient: [Color(0xFF6A0F0F), Color(0xFFC62828)],
    art: 'assets/images/cards/card_crazy.png',
    focus: Alignment(0.45, 0),
  ),
  _GameEntry(
    title: 'طيّار',
    tagline: 'اسحب قبل الانفجار',
    emoji: '✈️',
    accent: Color(0xFFFF9800),
    gradient: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)],
    art: 'assets/images/cards/card_crash.png',
    focus: Alignment(0.7, 0),
  ),
  _GameEntry(
    title: 'أثيرفول',
    tagline: 'افتح خزائن السماء',
    emoji: '⚡',
    accent: Color(0xFF4DD8E6),
    gradient: [Color(0xFF0F1638), Color(0xFF07030F)],
    art: 'assets/images/cards/card_aetherfall.png',
  ),
  _GameEntry(
    title: 'بوابات أوليمبوس',
    tagline: 'اجمع صواعق زيوس',
    emoji: '⚡',
    accent: Color(0xFFE3B84A),
    gradient: [Color(0xFF3A1A72), Color(0xFF12052B)],
    art: 'assets/images/cards/card_olympus.png',
    focus: Alignment(0.75, 0),
  ),
  _GameEntry(
    title: 'القط الجشع',
    tagline: 'اختر طعامك واربح',
    emoji: '🐱',
    accent: Color(0xFFFFD83D),
    gradient: [Color(0xFF1599D0), Color(0xFF20BCEB)],
    art: 'assets/images/cards/card_greedy.png',
    focus: Alignment(0.75, 0),
  ),
  _GameEntry(
    title: 'أستيريون',
    tagline: 'اجمع كرات العاصفة',
    emoji: '⛈️',
    accent: Color(0xFF5EE0F5),
    gradient: [Color(0xFF141A47), Color(0xFF06071A)],
    art: 'assets/images/cards/card_asterion.png',
    focus: Alignment(-0.1, 0),
  ),
  _GameEntry(
    title: 'نيون فورتشن',
    tagline: 'أدر واجمع الجاكبوت',
    emoji: '🐯',
    accent: Color(0xFFEA35D7),
    gradient: [Color(0xFF250A46), Color(0xFF17062E)],
    art: 'assets/images/cards/card_neon.png',
    focus: Alignment(-0.7, 0),
  ),
  if (_yummyEnabled)
  _GameEntry(
    title: 'يمي',
    tagline: 'اجمع الفواكه واربح العملات',
    emoji: '🍓',
    accent: Color(0xFFFFD529),
    gradient: [Color(0xFF08B9F2), Color(0xFF0753BD)],
    art: 'assets/images/cards/card_yummy.png',
  ),
  if (_fruitWheelEnabled)
  _GameEntry(
    title: 'عجلة الفواكه',
    tagline: 'بطيخ ×2 · 777 ×3 · برقوق ×2',
    emoji: '🍉',
    accent: Color(0xFFFFD332),
    gradient: [Color(0xFF16072E), Color(0xFF5724A0)],
    art: 'assets/images/cards/card_fruit_wheel.png',
  ),
  if (_rouletteEnabled)
  _GameEntry(
    title: 'الروليت',
    tagline: 'طاولة واحدة للجميع — راهن قبل انتهاء الوقت',
    emoji: '🎡',
    accent: Color(0xFFF5BD45),
    gradient: [Color(0xFF111634), Color(0xFF260C4C)],
    art: 'assets/images/cards/card_roulette.png',
    focus: Alignment(-0.5, 0),
  ),
  if (_carWheelEnabled)
  _GameEntry(
    title: 'عجلة السيارات',
    tagline: 'طاولة واحدة للجميع — راهن قبل انتهاء الوقت',
    emoji: '🎡',
    accent: Color(0xFFF5BD45),
    gradient: [Color(0xFF361265), Color(0xFFA7133B)],
    art: 'assets/images/cards/card_car_wheel.png',
  ),
];

/// Big wins announced by the server ride above the cards while YUMMY is on.
class _WithWinTicker extends StatelessWidget {
  final Widget child;
  const _WithWinTicker({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!_yummyEnabled) return child;
    YummyWinFeed.instance.listen();
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: YummyWinTicker(clock: null, strings: YummyStrings(true)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class GamesHubScreen extends ConsumerWidget {
  const GamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF07030F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ألعاب',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF120A26), Color(0xFF07030F)],
          ),
        ),
        child: SafeArea(
          child: _WithWinTicker(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: .78,
              ),
              itemCount: _games.length,
              itemBuilder: (_, i) =>
                  _GameCard(entry: _games[i], onTap: () => _open(context, i)),
            ),
          ),
        ),
      ),
    );
  }

  /// Dispatch on the entry's title, not its position.
  ///
  /// This used to switch on the list index, which meant inserting a game
  /// silently repointed every card after it — and two games in flight at once
  /// had already collided on `case 4`. The title is stable, so a new entry can
  /// go anywhere in [_games] without touching anything below.
  void _open(BuildContext context, int index) {
    final Widget screen;
    switch (_games[index].title) {
      case 'بلينكو':
        screen = const PlinkoScreen();
        break;
      case 'عجلة الحظ':
        screen = const CrazyWheelScreen();
        break;
      case 'طيّار':
        screen = const CrashGameScreen();
        break;
      case 'أثيرفول':
        screen = const AetherfallScreen();
        break;
      case 'بوابات أوليمبوس':
        screen = const OlympusScreen();
        break;
      case 'القط الجشع':
        screen = const GreedyCatScreen();
        break;
      case 'أستيريون':
        screen = const AsterionScreen();
        break;
      case 'نيون فورتشن':
        screen = const NeonFortuneScreen();
        break;
      case 'جاكبوت الفواكه':
        screen = const FruitJackpotScreen();
        break;
      case 'يمي':
        screen = const YummyScreen();
        break;
      case 'عجلة الفواكه':
        screen = const FruitWheelScreen();
        break;
      case 'عجلة السيارات':
        screen = const CarWheelScreen();
        break;
      case 'الروليت':
        screen = const RouletteScreen();
        break;
      default:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _GameEntry {
  final String title, tagline, emoji;

  /// Drives the tile's border, glow and the name's glow.
  final Color accent;
  final List<Color> gradient;

  /// Optional key art; the gradient and emoji stand in when absent.
  final String? art;

  /// Where the 2:1 banner's subject sits; the tile crops around it.
  final Alignment focus;

  const _GameEntry({
    required this.title,
    required this.tagline,
    required this.emoji,
    required this.accent,
    required this.gradient,
    this.art,
    this.focus = Alignment.center,
  });
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.entry, required this.onTap});

  final _GameEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emoji =
        Center(child: Text(entry.emoji, style: const TextStyle(fontSize: 44)));
    return Semantics(
      button: true,
      label: entry.title,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: entry.accent.withValues(alpha: .55)),
            boxShadow: [
              BoxShadow(
                color: entry.accent.withValues(alpha: .25),
                blurRadius: 12,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: entry.gradient,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                if (entry.art != null)
                  Image.asset(
                    entry.art!,
                    fit: BoxFit.cover,
                    alignment: entry.focus,
                    // Decode near the tile's size, not the full banner.
                    cacheWidth: 360,
                    // Falls back to the gradient plus the game's emoji if the
                    // artwork is ever missing, so the tile never renders empty.
                    errorBuilder: (_, __, ___) => emoji,
                  )
                else
                  emoji,
                // Scrim under the name so it reads over any artwork.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0x0017062E),
                            Color(0xE617062E),
                          ],
                          stops: [0, .5, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 8,
                  child: Text(
                    entry.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: entry.accent, blurRadius: 12),
                        const Shadow(color: Colors.black87, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

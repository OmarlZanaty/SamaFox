import '../services/dio_client.dart';
import '../l10n/tr.dart';
import '../widgets/room/room_games_host.dart';
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

// i18n: titles are navigation keys below (see [_open]); shown via [_displayTitle].
const Map<String, String> _kGameTitlesEn = {
  'جاكبوت الفواكه': 'Fruit Jackpot',
  'بلينكو': 'Plinko',
  'عجلة الحظ': 'Wheel of Fortune',
  'طيّار': 'Pilot',
  'أثيرفول': 'Aetherfall',
  'بوابات أوليمبوس': 'Olympus Gates',
  'القط الجشع': 'Greedy Cat',
  'أستيريون': 'Asterion',
  'نيون فورتشن': 'Neon Fortune',
  'يمي': 'Yummy',
  'عجلة الفواكه': 'Fruit Wheel',
  'الروليت': 'Roulette',
  'عجلة السيارات': 'Car Wheel',
};

String _displayTitle(String key) => tr(key, _kGameTitlesEn[key] ?? key);

List<_GameEntry> get _games => [
  if (_fruitJackpotEnabled)
  _GameEntry(
    title: 'جاكبوت الفواكه',
    tagline: tr('اختر رهانك وأدر الفواكه', "Choose your bet and spin the fruit"),
    emoji: '🍒',
    accent: Color(0xFFFFD52B),
    gradient: [Color(0xFF3B176B), Color(0xFF190D35)],
    art: 'assets/images/cards/card_fruit_jackpot.png',
  ),
  _GameEntry(
    title: 'بلينكو',
    tagline: tr('أسقط الكرة', "Drop the ball"),
    emoji: '🎱',
    accent: Color(0xFF9C6BFF),
    gradient: [Color(0xFF1B0B3A), Color(0xFF4A148C)],
    art: 'assets/images/cards/card_plinko.png',
    focus: Alignment(0.45, 0),
  ),
  _GameEntry(
    title: 'عجلة الحظ',
    tagline: tr('أدر واربح', "Spin and win"),
    emoji: '🎡',
    accent: Color(0xFFFFC107),
    gradient: [Color(0xFF6A0F0F), Color(0xFFC62828)],
    art: 'assets/images/cards/card_crazy.png',
    focus: Alignment(0.45, 0),
  ),
  _GameEntry(
    title: 'طيّار',
    tagline: tr('اسحب قبل الانفجار', "Cash out before the crash"),
    emoji: '✈️',
    accent: Color(0xFFFF9800),
    gradient: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)],
    art: 'assets/images/cards/card_crash.png',
    focus: Alignment(0.7, 0),
  ),
  _GameEntry(
    title: 'أثيرفول',
    tagline: tr('افتح خزائن السماء', "Open the Sky Vaults"),
    emoji: '⚡',
    accent: Color(0xFF4DD8E6),
    gradient: [Color(0xFF0F1638), Color(0xFF07030F)],
    art: 'assets/images/cards/card_aetherfall.png',
  ),
  _GameEntry(
    title: 'بوابات أوليمبوس',
    tagline: tr('اجمع صواعق زيوس', "Collect Zeus's lightning bolts"),
    emoji: '⚡',
    accent: Color(0xFFE3B84A),
    gradient: [Color(0xFF3A1A72), Color(0xFF12052B)],
    art: 'assets/images/cards/card_olympus.png',
    focus: Alignment(0.75, 0),
  ),
  _GameEntry(
    title: 'القط الجشع',
    tagline: tr('اختر طعامك واربح', "Choose your food and win"),
    emoji: '🐱',
    accent: Color(0xFFFFD83D),
    gradient: [Color(0xFF1599D0), Color(0xFF20BCEB)],
    art: 'assets/images/cards/card_greedy.png',
    focus: Alignment(0.75, 0),
  ),
  _GameEntry(
    title: 'أستيريون',
    tagline: tr('اجمع كرات العاصفة', "Collect storm orbs"),
    emoji: '⛈️',
    accent: Color(0xFF5EE0F5),
    gradient: [Color(0xFF141A47), Color(0xFF06071A)],
    art: 'assets/images/cards/card_asterion.png',
    focus: Alignment(-0.1, 0),
  ),
  _GameEntry(
    title: 'نيون فورتشن',
    tagline: tr('أدر واجمع الجاكبوت', "Spin and collect the jackpot"),
    emoji: '🐯',
    accent: Color(0xFFEA35D7),
    gradient: [Color(0xFF250A46), Color(0xFF17062E)],
    art: 'assets/images/cards/card_neon.png',
    focus: Alignment(-0.7, 0),
  ),
  if (_yummyEnabled)
  _GameEntry(
    title: 'يمي',
    tagline: tr('اجمع الفواكه واربح العملات', "Collect fruit and win coins"),
    emoji: '🍓',
    accent: Color(0xFFFFD529),
    gradient: [Color(0xFF08B9F2), Color(0xFF0753BD)],
    art: 'assets/images/cards/card_yummy.png',
  ),
  if (_fruitWheelEnabled)
  _GameEntry(
    title: 'عجلة الفواكه',
    tagline: tr('بطيخ ×2 · 77 ×8 · برقوق ×2', "Watermelon ×2 · 77 ×8 · Plum ×2"),
    emoji: '🍉',
    accent: Color(0xFFFFD332),
    gradient: [Color(0xFF16072E), Color(0xFF5724A0)],
    art: 'assets/images/cards/card_fruit_wheel.png',
  ),
  if (_rouletteEnabled)
  _GameEntry(
    title: 'الروليت',
    tagline: tr('طاولة واحدة للجميع — راهن قبل انتهاء الوقت', "One table for everyone — bet before time runs out"),
    emoji: '🎡',
    accent: Color(0xFFF5BD45),
    gradient: [Color(0xFF111634), Color(0xFF260C4C)],
    art: 'assets/images/cards/card_roulette.png',
    focus: Alignment(-0.5, 0),
  ),
  if (_carWheelEnabled)
  _GameEntry(
    title: 'عجلة السيارات',
    tagline: tr('طاولة واحدة للجميع — راهن قبل انتهاء الوقت', "One table for everyone — bet before time runs out"),
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
  const GamesHubScreen({super.key, this.embedded = false});

  /// SPEC52 #11 — inside the room's games sheet: no app bar (the sheet has
  /// its own ← / ✕) and games open inside the sheet, scaled to it.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF07030F),
      appBar: embedded ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('ألعاب', 'Games'),
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
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _TopWagerers()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      childAspectRatio: .78,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _GameCard(entry: _games[i], onTap: () => _open(context, i)),
                      childCount: _games.length,
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
    Navigator.push(
      context,
      embedded ? roomGameRoute(screen) : MaterialPageRoute(builder: (_) => screen),
    );
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
      label: _displayTitle(entry.title),
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
                    _displayTitle(entry.title),
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

class _TopWagerers extends StatefulWidget {
  const _TopWagerers();
  @override
  State<_TopWagerers> createState() => _TopWagerersState();
}

class _TopWagerersState extends State<_TopWagerers> {
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await DioClient.dio.get<Map<String, dynamic>>('games/top-wagerers');
      final raw = response.data?['items'];
      if (mounted && raw is List) {
        setState(() => _items = raw.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)).take(3).toList());
      }
    } catch (_) {
      // The games remain available when the optional podium cannot be loaded.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(children: [
        Text(tr('أكثر اللاعبين رهانًا اليوم', 'Today’s top bettors'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [for (final rank in [2, 1, 3]) Expanded(child: _place(rank))],
          ),
        ),
      ]),
    );
  }

  Widget _place(int rank) {
    if (rank > _items.length) return const SizedBox.shrink();
    final item = _items[rank - 1];
    final color = [const Color(0xFFFFD54F), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)][rank - 1];
    final size = rank == 1 ? 64.0 : 48.0;
    final avatar = item['avatar']?.toString();
    final name = item['name']?.toString() ?? tr('لاعب', 'Player');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (rank == 1) const Text('👑', style: TextStyle(fontSize: 26)),
      Container(
        width: size, height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 3)),
        child: ClipOval(
          child: avatar == null || avatar.isEmpty
              ? const Icon(Icons.person, color: Colors.white)
              : Image.network(avatar, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white)),
        ),
      ),
      Text('#$rank', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
      Text(tr('${item['wagered'] ?? 0} عملة', '${item['wagered'] ?? 0} coins'),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 12)),
    ]);
  }
}

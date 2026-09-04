import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'games/aetherfall_screen.dart';
import 'games/crash_game_screen.dart';
import 'games/crazy_wheel_screen.dart';
import 'games/neon_fortune_screen.dart';
import 'games/plinko_screen.dart';
// Older games are hidden from the hub for now — see _hiddenGames below.
// import 'games/skill_wheel_screen.dart';
// import 'games/fish_shooter_screen.dart';
// import 'games/lion_tiger_screen.dart';
// import 'games/skill_dice_screen.dart';

/// Full-bleed stacked cards: one game per row, artwork filling the card, the
/// name drawn over it. Titles stay in code rather than baked into the artwork
/// so they remain translatable and crisp at any density.
const List<_GameEntry> _games = [
  _GameEntry(
    title: 'بلينكو',
    tagline: 'أسقط الكرة',
    emoji: '🎱',
    accent: Color(0xFF9C6BFF),
    gradient: [Color(0xFF1B0B3A), Color(0xFF4A148C)],
    art: 'assets/images/cards/card_plinko.png',
  ),
  _GameEntry(
    title: 'عجلة الحظ',
    tagline: 'أدر واربح',
    emoji: '🎡',
    accent: Color(0xFFFFC107),
    gradient: [Color(0xFF6A0F0F), Color(0xFFC62828)],
    art: 'assets/images/cards/card_crazy.png',
  ),
  _GameEntry(
    title: 'طيّار',
    tagline: 'اسحب قبل الانفجار',
    emoji: '✈️',
    accent: Color(0xFFFF9800),
    gradient: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)],
    art: 'assets/images/cards/card_crash.png',
  ),
  _GameEntry(
    title: 'أثيرفول',
    tagline: 'افتح خزائن السماء',
    emoji: '⚡',
    accent: Color(0xFF4DD8E6),
    gradient: [Color(0xFF0F1638), Color(0xFF07030F)],
    art: 'assets/images/cards/card_aetherfall.png',
  ),
    gradient: [Color(0xFF1599D0), Color(0xFF20BCEB)],
    art: 'assets/images/cards/card_greedy.png',
  ),
  _GameEntry(
    title: 'نيون فورتشن',
    tagline: 'أدر واجمع الجاكبوت',
    emoji: '🐯',
    accent: Color(0xFFEA35D7),
    gradient: [Color(0xFF250A46), Color(0xFF17062E)],
    art: 'assets/images/cards/card_neon.png',
    // Delivered without lettering, so the hub draws the name.
    drawTitle: true,
  ),
];

/// Kept so the older games can be put back in one move: add the entry to
/// [_games] and restore its case in [GamesHubScreen._open].
// ignore: unused_element
const List<_GameEntry> _hiddenGames = [
  _GameEntry(
    title: 'عجلة المهارة',
    tagline: 'أوقف العجلة',
    emoji: '🎯',
    accent: Color(0xFF6B21A8),
    gradient: [Color(0xFF1a0533), Color(0xFF6B21A8)],
  ),
  _GameEntry(
    title: 'صياد السمك',
    tagline: 'أطلق واربح',
    emoji: '🐠',
    accent: Color(0xFF0E7C9B),
    gradient: [Color(0xFF063E7A), Color(0xFF0E7C9B)],
  ),
  _GameEntry(
    title: 'حلبة الأسد والنمر',
    tagline: 'سدّد في الوقت المناسب',
    emoji: '🥊',
    accent: Color(0xFF7B1FA2),
    gradient: [Color(0xFF4A148C), Color(0xFF2B1055)],
  ),
  _GameEntry(
    title: 'نرد المهارة',
    tagline: 'أوقف النرد',
    emoji: '🎲',
    accent: Color(0xFF146A48),
    gradient: [Color(0xFF0B3B2A), Color(0xFF0E5138)],
  ),
];

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              const hPad = 14.0;
              const vPad = 10.0;
              final cardHeight = (constraints.maxWidth - hPad * 2) / 2.0;
              final needed = cardHeight * _games.length;
              final slack = constraints.maxHeight - vPad * 2 - needed;

              final cards = [
                for (var i = 0; i < _games.length; i++)
                  _GameCard(entry: _games[i], onTap: () => _open(context, i)),
              ];

              // Three 2:1 banners do not fill a tall phone, so spread the
              // leftover height between them rather than leaving a dead gap
              // under the last card. On short screens it scrolls instead.
              if (slack > 0) {
                final gap = (slack / (_games.length - 1)).clamp(12.0, 48.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: hPad,
                    vertical: vPad,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) SizedBox(height: gap),
                        cards[i],
                      ],
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: hPad,
                  vertical: vPad,
                ),
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) => cards[i],
              );
            },
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
      case 'نيون فورتشن':
        screen = const NeonFortuneScreen();
        break;
      // Hidden games — restore the _GameEntry to [_games] and these match by
      // title wherever it lands:
      // case 'عجلة المهارة': screen = const SkillWheelScreen(); break;
      // case 'صياد السمك': screen = const FishShooterScreen(); break;
      // case 'حلبة الأسد والنمر': screen = const LionTigerScreen(); break;
      // case 'نرد المهارة': screen = const SkillDiceScreen(); break;
      default:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _GameEntry {
  final String title, tagline, emoji;

  /// Drives the card's border, glow and the tagline colour.
  final Color accent;
  final List<Color> gradient;

  /// Optional key art; the gradient and emoji stand in when absent.
  final String? art;

  /// Draw [title] and [tagline] over the artwork.
  ///
  /// Most banners have their name lettered into the image, so text on top would
  /// double up. A banner delivered without lettering sets this instead, and gets
  /// its name from code — which also keeps that name translatable.
  final bool drawTitle;

  const _GameEntry({
    required this.title,
    required this.tagline,
    required this.emoji,
    required this.accent,
    required this.gradient,
    this.art,
    this.drawTitle = false,
  });
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.entry, required this.onTap});

  final _GameEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        // The banners are 2:1 and most carry their own frame, glow and title, so
        // the card is the artwork — text on top of those would double up. A
        // banner without lettering opts into `drawTitle` and gets its name here.
        aspectRatio: 2.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: entry.accent.withValues(alpha: 0.30),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
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
                    // Falls back to the gradient plus the game's emoji if the
                    // artwork is ever missing, so the row never renders empty.
                    errorBuilder: (_, __, ___) => Center(
                      child:
                          Text(entry.emoji, style: const TextStyle(fontSize: 84)),
                    ),
                  )
                else
                  Center(
                    child:
                        Text(entry.emoji, style: const TextStyle(fontSize: 84)),
                  ),
                if (entry.drawTitle) ..._titleOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Name and tagline over the artwork, for banners delivered without lettering.
  ///
  /// A scrim runs from the leading edge inward so the words hold their contrast
  /// whatever the art does behind them, and both it and the text follow the
  /// reading direction — the Arabic layout puts them on the right, an English one
  /// on the left. That is where reading starts, and where this banner leaves the
  /// art quiet.
  List<Widget> _titleOverlay() {
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [
                  const Color(0xFF17062E).withValues(alpha: 0.82),
                  const Color(0xFF17062E).withValues(alpha: 0.45),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.32, 0.62],
              ),
            ),
          ),
        ),
      ),
      PositionedDirectional(
        start: 20,
        top: 0,
        bottom: 0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title,
              textAlign: TextAlign.start,
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(color: entry.accent, blurRadius: 18),
                  const Shadow(color: Colors.black87, blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              entry.tagline,
              textAlign: TextAlign.start,
              style: TextStyle(
                color: entry.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

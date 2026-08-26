import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'games/aetherfall_screen.dart';
import 'games/crash_game_screen.dart';
import 'games/crazy_wheel_screen.dart';
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
        title: const Text('ألعاب',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
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
                      horizontal: hPad, vertical: vPad),
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
                    horizontal: hPad, vertical: vPad),
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

  void _open(BuildContext context, int index) {
    Widget screen;
    switch (index) {
      case 0:
        screen = const PlinkoScreen();
        break;
      case 1:
        screen = const CrazyWheelScreen();
        break;
      case 2:
        screen = const CrashGameScreen();
        break;
      case 3:
        screen = const AetherfallScreen();
        break;
      // Hidden games — indices follow whatever position they are restored to
      // in _games:
      // case 4: screen = const SkillWheelScreen(); break;
      // case 5: screen = const FishShooterScreen(); break;
      // case 6: screen = const LionTigerScreen(); break;
      // case 7: screen = const SkillDiceScreen(); break;
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

  const _GameEntry({
    required this.title,
    required this.tagline,
    required this.emoji,
    required this.accent,
    required this.gradient,
    this.art,
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
        // The banners are 2:1 and carry their own frame, glow and title, so the
        // card is the artwork — anything drawn on top would double up.
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
            child: Stack(fit: StackFit.expand, children: [
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
            ]),
          ),
        ),
      ),
    );
  }
}

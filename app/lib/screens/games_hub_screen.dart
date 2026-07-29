import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'games/crash_game_screen.dart';
import 'games/crazy_wheel_screen.dart';
import 'games/plinko_screen.dart';
// Older games are hidden from the hub for now — see _hiddenGames below.
// import 'games/skill_wheel_screen.dart';
// import 'games/fish_shooter_screen.dart';
// import 'games/lion_tiger_screen.dart';
// import 'games/skill_dice_screen.dart';

const List<_GameEntry> _games = [
  _GameEntry(
    title: 'طيّار',
    subtitle: 'اسحب رهانك قبل أن تطير الطائرة',
    emoji: '✈️',
    gradient: [Color(0xFF1B1B1B), Color(0xFF3A0A16), Color(0xFF9B1C31)],
    badge: 'رهان',
    tall: true,
    art: 'assets/images/crash/tile_crash.png',
  ),
  _GameEntry(
    title: 'عجلة الحظ',
    subtitle: 'راهن على قطاعك وانتظر جولات المكافأة',
    emoji: '🎡',
    gradient: [Color(0xFF3E0A2E), Color(0xFF8E1B4A), Color(0xFFC62828)],
    badge: 'رهان',
    tall: true,
  ),
  _GameEntry(
    title: 'بلينكو',
    subtitle: 'أسقط الكرة ودعها ترتد نحو أكبر مضاعف',
    emoji: '🎱',
    gradient: [Color(0xFF120A26), Color(0xFF4A148C), Color(0xFF00897B)],
    badge: 'رهان',
    tall: true,
  ),
];

/// Kept so the older games can be put back in one move: add the entry to
/// [_games] and restore its case in [GamesHubScreen._open].
// ignore: unused_element
const List<_GameEntry> _hiddenGames = [
  _GameEntry(
    title: 'عجلة المهارة',
    subtitle: 'أوقف العجلة على الرقم المطلوب واربح مكافأتك',
    emoji: '🎯',
    gradient: [Color(0xFF1a0533), Color(0xFF6B21A8)],
    badge: 'مهارة',
  ),
  _GameEntry(
    title: 'صياد السمك',
    subtitle: 'أطلق النار على الأسماك واربح العملات',
    emoji: '🐠',
    gradient: [Color(0xFF063E7A), Color(0xFF0A5A8C), Color(0xFF0E7C9B)],
    badge: 'أركيد',
    tall: true,
  ),
  _GameEntry(
    title: 'حلبة الأسد والنمر',
    subtitle: 'ادخل الحلبة وسدّد لكماتك في الوقت المناسب',
    emoji: '🥊',
    gradient: [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFF2B1055)],
    badge: 'مهارة',
    tall: true,
  ),
  _GameEntry(
    title: 'نرد المهارة',
    subtitle: 'أوقف النرد على المهمة واربح مكافأتك',
    emoji: '🎲',
    gradient: [Color(0xFF0B3B2A), Color(0xFF146A48), Color(0xFF0E5138)],
    badge: 'مهارة',
  ),
];

class GamesHubScreen extends ConsumerWidget {
  const GamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0620),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('ألعاب', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0E3E), Color(0xFF0D0620)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _staggeredGrid(context),
        ),
      ),
    );
  }

  /// Two-column masonry: each tile is placed in whichever column is currently
  /// shorter, so the differing tile heights interlock instead of leaving a
  /// ragged gap down one side.
  Widget _staggeredGrid(BuildContext context) {
    final left = <Widget>[];
    final right = <Widget>[];
    var leftHeight = 0.0;
    var rightHeight = 0.0;

    for (var i = 0; i < _games.length; i++) {
      final height = _games[i].tall ? 230.0 : 150.0;
      final tile = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _GameBanner(
          entry: _games[i],
          height: height,
          onTap: () => _open(context, i),
        ),
      );

      if (leftHeight <= rightHeight) {
        left.add(tile);
        leftHeight += height + 12;
      } else {
        right.add(tile);
        rightHeight += height + 12;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        const SizedBox(width: 12),
        Expanded(child: Column(children: right)),
      ],
    );
  }

  void _open(BuildContext context, int index) {
    Widget screen;
    switch (index) {
      case 0: screen = const CrashGameScreen(); break;
      case 1: screen = const CrazyWheelScreen(); break;
      case 2: screen = const PlinkoScreen(); break;
      // Hidden games — indices follow whatever position they are restored to
      // in _games:
      // case 3: screen = const SkillWheelScreen(); break;
      // case 4: screen = const FishShooterScreen(); break;
      // case 5: screen = const LionTigerScreen(); break;
      // case 6: screen = const SkillDiceScreen(); break;
      default: return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _GameEntry {
  final String title, subtitle, emoji, badge;
  final List<Color> gradient;

  /// Drives the masonry: tall tiles get the full artwork treatment, short ones
  /// drop the subtitle. Alternating them is what makes the grid interlock.
  final bool tall;

  /// Optional key-art asset; falls back to the emoji when absent.
  final String? art;

  const _GameEntry({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.gradient,
    required this.badge,
    this.tall = false,
    this.art,
  });
}

class _GameBanner extends StatelessWidget {
  final _GameEntry entry;
  final double height;
  final VoidCallback onTap;
  const _GameBanner({required this.entry, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tall = entry.tall;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: entry.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: entry.gradient.last.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        // Clip so the oversized emoji bleeds off the tile edge instead of
        // overflowing into the neighbouring column.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            // Games with commissioned key art show it instead of an emoji.
            if (entry.art != null)
              Positioned.fill(
                child: Image.asset(entry.art!, fit: BoxFit.cover),
              )
            else
              Positioned(
                right: -12,
                top: -12,
                child: Text(entry.emoji, style: TextStyle(fontSize: tall ? 86 : 62)),
              ),
            // Scrim so the title stays readable over the artwork.
            if (entry.art != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(entry.badge, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: tall ? 19 : 16, fontWeight: FontWeight.bold),
                  ),
                  // A half-height tile has no room for the subtitle as well as
                  // the play button, so it only appears on tall tiles.
                  if (tall) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, height: 1.25),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                    child: const Text('العب الآن', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

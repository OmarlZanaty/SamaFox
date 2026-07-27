import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'games/crash_game_screen.dart';
import 'games/skill_wheel_screen.dart';
import 'games/fish_shooter_screen.dart';
import 'games/lion_tiger_screen.dart';
import 'games/skill_dice_screen.dart';

const List<_GameEntry> _games = [
  _GameEntry(
    title: 'طيّار',
    subtitle: 'اسحب رهانك قبل أن تطير الطائرة',
    emoji: '✈️',
    gradient: [Color(0xFF1B1B1B), Color(0xFF3A0A16), Color(0xFF9B1C31)],
    badge: 'رهان',
  ),
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
  ),
  _GameEntry(
    title: 'حلبة الأسد والنمر',
    subtitle: 'ادخل الحلبة وسدّد لكماتك في الوقت المناسب',
    emoji: '🥊',
    gradient: [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFF2B1055)],
    badge: 'مهارة',
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
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _games.length,
          itemBuilder: (context, index) {
            final g = _games[index];
            return _GameBanner(
              entry: g,
              onTap: () {
                Widget screen;
                switch (index) {
                  case 0: screen = const CrashGameScreen(); break;
                  case 1: screen = const SkillWheelScreen(); break;
                  case 2: screen = const FishShooterScreen(); break;
                  case 3: screen = const LionTigerScreen(); break;
                  case 4: screen = const SkillDiceScreen(); break;
                  default: return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
              },
            );
          },
        ),
      ),
    );
  }
}

class _GameEntry {
  final String title, subtitle, emoji, badge;
  final List<Color> gradient;
  const _GameEntry({required this.title, required this.subtitle, required this.emoji, required this.gradient, required this.badge});
}

class _GameBanner extends StatelessWidget {
  final _GameEntry entry;
  final VoidCallback onTap;
  const _GameBanner({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: entry.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: entry.gradient.last.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Stack(children: [
          Positioned(right: -10, top: -10,
            child: Text(entry.emoji, style: const TextStyle(fontSize: 90))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(entry.badge, style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ),
              const SizedBox(height: 6),
              Text(entry.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text(entry.subtitle, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
            ]),
          ),
          Positioned(right: 16, bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: const Text('العب الآن', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}

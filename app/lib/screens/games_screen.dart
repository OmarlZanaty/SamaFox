import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'games/roulette_screen.dart';


/// Games Screen - Displays available games in decorative cards
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ألعاب',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
          onPressed: () {},
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A0E3E),
              const Color(0xFF0D0620),
            ],
          ),
        ),
        child: Column(
          children: [
            // "ألعاب حظ" header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'ألعاب حظ',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // Games grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.75,
                ),
                itemCount: games.length,
                itemBuilder: (context, index) {
                  final game = games[index];
                  return _GameCard(game: game);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameItem game;

  const _GameCard({required this.game});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (game.id == 'roulette') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const RouletteScreen(),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening ${game.name}...')),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: game.gradientColors,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: game.borderColor,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: game.borderColor.withOpacity(0.5),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative top ornament
            Positioned(
              top: -5,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: game.borderColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    Icons.diamond,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            // Game content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Game icon/image placeholder
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Center(
                        child: Icon(
                          game.icon,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Game name
                  Text(
                    game.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// Game data model
class GameItem {
  final String id; // NEW
  final String name;
  final IconData icon;
  final List<Color> gradientColors;
  final Color borderColor;

  GameItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.gradientColors,
    required this.borderColor,
  });
}

// Games list matching the image
final List<GameItem> games = [
  GameItem(
    id: 'roulette',
    name: 'روليت',
    icon: Icons.casino_outlined,
    gradientColors: [Color(0xFF6B21A8), Color(0xFF1a0533)],
    borderColor: Color(0xFFFFD700),
  ),
  GameItem(
    id: 'reaction',
    name: 'اختبار السرعة',
    icon: Icons.flash_on,
    gradientColors: [Color(0xFFFF5722), Color(0xFFBF360C)],
    borderColor: Color(0xFFFFD740),
  ),
  GameItem(
    id: 'math',
    name: 'تحدي الحساب',
    icon: Icons.calculate,
    gradientColors: [Color(0xFF607D8B), Color(0xFF263238)],
    borderColor: Color(0xFF00BCD4),
  ),

  // باقي الألعاب (قريباً)
  GameItem(
    id: 'quiz',
    name: 'تحدي المعرفة',
    icon: Icons.quiz,
    gradientColors: [Color(0xFF3F51B5), Color(0xFF1A237E)],
    borderColor: Color(0xFFFFD700),
  ),
  GameItem(
    id: 'word',
    name: 'خمن الكلمة',
    icon: Icons.text_fields,
    gradientColors: [Color(0xFF009688), Color(0xFF004D40)],
    borderColor: Color(0xFF00E5FF),
  ),
  GameItem(
    id: 'memory',
    name: 'لعبة الذاكرة',
    icon: Icons.grid_on,
    gradientColors: [Color(0xFF9C27B0), Color(0xFF4A148C)],
    borderColor: Color(0xFFFF80AB),
  ),
  GameItem(
    id: 'puzzle',
    name: 'ألغاز ذكية',
    icon: Icons.extension,
    gradientColors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
    borderColor: Color(0xFFB2FF59),
  ),
  GameItem(
    id: 'draw',
    name: 'ارسم وخمّن',
    icon: Icons.brush,
    gradientColors: [Color(0xFF03A9F4), Color(0xFF01579B)],
    borderColor: Color(0xFFFFD700),
  ),
];

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/screens/games/dice_game_screen.dart';
import 'package:samafox/screens/games/all_games_screens.dart';


/// Games Hub Screen - Displays all available games in a grid
class GamesHubScreen extends ConsumerWidget {
  const GamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'الالعاب',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
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
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
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
    // Check if game is available (only Greedy Dice is available)
    final isAvailable = game.isAvailable;

    return GestureDetector(
      onTap: () {
        if (isAvailable && game.builder != null) {
          Navigator.push(context, MaterialPageRoute(builder: game.builder!));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${game.name} قريباً...')),
          );
        }
      },

      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isAvailable
                ? game.gradientColors
                : [const Color(0xFF4A4A4A), const Color(0xFF2A2A2A)], // Gray for unavailable
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isAvailable ? game.borderColor : Colors.grey,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: (isAvailable ? game.borderColor : Colors.grey).withOpacity(0.5),
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
                    color: isAvailable ? game.borderColor : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
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
                          color: Colors.white.withOpacity(isAvailable ? 1.0 : 0.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Game name
                  Text(
                    game.name,
                    style: TextStyle(
                      color: Colors.white.withOpacity(isAvailable ? 1.0 : 0.6),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      shadows: const [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  // "Coming Soon" label for unavailable games
                  if (!isAvailable) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'قريبا',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
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
  final String id;
  final String name;
  final IconData icon;
  final List<Color> gradientColors;
  final Color borderColor;

  final WidgetBuilder? builder; // ✅ optional
  final bool isAvailable;

  GameItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.gradientColors,
    required this.borderColor,
    this.builder, // ✅ optional
    this.isAvailable = true,
  });
}



// Games list
final List<GameItem> games = [
  GameItem(
    id: 'tic',
    name: 'إكس أو',
    icon: Icons.grid_3x3,
    gradientColors: [Color(0xFF795548), Color(0xFF3E2723)],
    borderColor: Color(0xFFFFD700),
  ),
  GameItem(
    id: 'dice',
    name: 'نرد التحدي',
    icon: Icons.casino_outlined,
    gradientColors: [Color(0xFF6D4C41), Color(0xFF4E342E)],
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



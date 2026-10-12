import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class FruitJackpotCelebration extends StatefulWidget {
  final int prize;
  final bool jackpot, motion, arabic;
  const FruitJackpotCelebration({
    super.key,
    required this.prize,
    required this.jackpot,
    required this.motion,
    required this.arabic,
  });
  @override
  State<FruitJackpotCelebration> createState() =>
      _FruitJackpotCelebrationState();
}

class _FruitJackpotCelebrationState extends State<FruitJackpotCelebration> {
  final controller = ConfettiController(duration: const Duration(seconds: 2));
  @override
  void initState() {
    super.initState();
    if (widget.motion) controller.play();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xff35134e),
    title: Text(
      widget.jackpot
          ? 'JACKPOT'
          : widget.arabic
          ? 'فوز'
          : 'WIN',
      textAlign: TextAlign.center,
    ),
    content: Stack(
      alignment: Alignment.topCenter,
      children: [
        ConfettiWidget(
          confettiController: controller,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: 15,
          colors: const [Colors.amber, Colors.orange, Colors.purpleAccent],
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: widget.prize.toDouble()),
          duration: Duration(milliseconds: widget.motion ? 1200 : 0),
          builder: (_, value, __) => Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              '🪙 ${value.round()}',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: Colors.amber,
              ),
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.arabic ? 'إغلاق' : 'Close'),
      ),
    ],
  );
}

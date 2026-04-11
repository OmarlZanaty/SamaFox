import 'package:flutter/material.dart';
import '../models/gift.dart';

class MegaGiftCard extends StatefulWidget {
  final Gift gift;
  final bool selected;
  final VoidCallback onTap;

  const MegaGiftCard({
    super.key,
    required this.gift,
    required this.selected,
    required this.onTap,
  });

  @override
  State<MegaGiftCard> createState() => _MegaGiftCardState();
}

class _MegaGiftCardState extends State<MegaGiftCard>
    with SingleTickerProviderStateMixin {

  late AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {

          final glow = 0.6 + (controller.value * 0.4);

          return Container(
            width: 92,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF7C4DFF),
                  Color(0xFF00E5FF),
                ],
              ),
              border: Border.all(
                color: widget.selected
                    ? Colors.amber
                    : Colors.amber.withOpacity(glow),
                width: widget.selected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(glow),
                  blurRadius: 12,
                )
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [

                Stack(
                  children: [

                    Image.asset(
                      widget.gift.imageUrl ?? '',
                      height: 44,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.card_giftcard,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),

                    const Positioned(
                      right: -2,
                      top: -2,
                      child: Icon(
                        Icons.workspace_premium,
                        color: Colors.amber,
                        size: 16,
                      ),
                    )
                  ],
                ),

                const SizedBox(height: 6),

                Flexible(
                  child: Text(
                    widget.gift.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Text(
                  "${widget.gift.priceCoins}",
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
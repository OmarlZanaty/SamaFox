import 'dart:math';
import 'package:flutter/material.dart';
import '../models/gift.dart';
import '../config/app_config.dart';

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
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _shimmerController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _shimmerController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MegaGiftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _scaleController.forward().then((_) => _scaleController.reverse());
    }
  }

  Widget _buildImage() {
    final raw = (widget.gift.imageUrl ?? '').trim();
    if (raw.isEmpty) {
      return const Icon(Icons.card_giftcard, color: Colors.amber, size: 36);
    }
    if (raw.startsWith('assets/')) {
      return Image.asset(raw, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.card_giftcard, color: Colors.amber, size: 36));
    }
    final url = raw.startsWith('http') ? raw : '${AppConfig.apiBaseUrl}$raw';
    return Image.network(url, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
        const Icon(Icons.card_giftcard, color: Colors.amber, size: 36));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_glowController, _shimmerController, _scaleAnim]),
        builder: (_, __) {
          final glow = _glowController.value;
          final shimmer = _shimmerController.value;

          return Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              width: 90,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.selected
                      ? [
                    const Color(0xFFFFD700),
                    const Color(0xFFFF6B35),
                    const Color(0xFFFF1493),
                  ]
                      : [
                    const Color(0xFF2A0A5E),
                    const Color(0xFF1A0A3E),
                  ],
                ),
                border: Border.all(
                  color: widget.selected
                      ? Colors.amber
                      : Colors.amber.withOpacity(0.3 + glow * 0.5),
                  width: widget.selected ? 2.5 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (widget.selected ? Colors.amber : const Color(0xFF7C4DFF))
                        .withOpacity(0.3 + glow * 0.4),
                    blurRadius: 16 + glow * 10,
                    spreadRadius: widget.selected ? 2 : 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  children: [
                    // Shimmer sweep
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset((shimmer * 2 - 0.5) * 120, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.12),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                              transform: const GradientRotation(pi / 4),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Crown badge
                          Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.workspace_premium,
                                  color: Colors.white, size: 10),
                            ),
                          ),
                          const SizedBox(height: 2),

                          // Gift image
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: _buildImage(),
                          ),

                          const SizedBox(height: 6),

                          // Name
                          Text(
                            widget.gift.nameAr?.isNotEmpty == true
                                ? widget.gift.nameAr!
                                : widget.gift.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: widget.selected ? Colors.white : Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 3),

                          // Price
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.monetization_on,
                                  color: widget.selected
                                      ? Colors.white
                                      : Colors.amber,
                                  size: 10),
                              const SizedBox(width: 2),
                              Text(
                                '${widget.gift.priceCoins ?? widget.gift.displayCoinsValue}',
                                style: TextStyle(
                                  color: widget.selected
                                      ? Colors.white
                                      : Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
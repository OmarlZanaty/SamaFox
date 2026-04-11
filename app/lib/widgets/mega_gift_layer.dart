import 'package:flutter/material.dart';
import '../services/gift_animation_service.dart';
import '../models/gift.dart';

class MegaGiftLayer extends StatefulWidget {

  final GiftAnimationData data;
  final VoidCallback onFinish;

  const MegaGiftLayer({
    super.key,
    required this.data,
    required this.onFinish,
  });

  @override
  State<MegaGiftLayer> createState() => _MegaGiftLayerState();
}

class _MegaGiftLayerState extends State<MegaGiftLayer>
    with TickerProviderStateMixin {

  late AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.data.durationMs),
    );

    controller.forward();

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinish();
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    switch (widget.data.animationType) {

      case GiftAnimationType.dragon:
        return _dragonAnimation();

      case GiftAnimationType.rocket:
        return _rocketAnimation();

      case GiftAnimationType.castle:
        return _castleAnimation();

      default:
        return const SizedBox();
    }
  }

  Widget _dragonAnimation() {

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {

        final progress = controller.value;

        return Positioned(
          left: -300 + (MediaQuery.of(context).size.width + 600) * progress,
          top: 120,
          child: Image.asset(
            "assets/mega/dragon.png",
            width: 320,
          ),
        );
      },
    );
  }

  Widget _rocketAnimation() {

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {

        final progress = controller.value;

        return Positioned(
          bottom: -200 + (MediaQuery.of(context).size.height + 400) * progress,
          left: MediaQuery.of(context).size.width / 2 - 60,
          child: Image.asset(
            "assets/mega/rocket.png",
            width: 120,
          ),
        );
      },
    );
  }

  Widget _castleAnimation() {

    return Stack(
      children: [

        Center(
          child: Image.asset(
            "assets/mega/castle.png",
            width: 260,
          ),
        ),

        Positioned.fill(
          child: Image.asset(
            "assets/mega/explosion.gif",
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}
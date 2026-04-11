import 'dart:math';
import 'package:flutter/material.dart';

class GiftRainOverlay extends StatefulWidget {
  final bool active;

  const GiftRainOverlay({super.key, required this.active});

  @override
  State<GiftRainOverlay> createState() => _GiftRainOverlayState();
}

class _GiftRainOverlayState extends State<GiftRainOverlay>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;
  final Random _rand = Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(GiftRainOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Stack(
            children: List.generate(20, (i) {
              final left = _rand.nextDouble() * MediaQuery.of(context).size.width;

              return Positioned(
                top: -50 + _controller.value * MediaQuery.of(context).size.height,
                left: left,
                child: const Icon(
                  Icons.favorite,
                  color: Colors.pinkAccent,
                  size: 16,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
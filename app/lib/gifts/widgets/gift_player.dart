import 'package:flutter/material.dart';

import '../models/gift.dart';
import 'svg_css_gift_player.dart';
import 'video_gift_player.dart';

/// Factory widget that routes a gift to the right player by format.
class GiftPlayer extends StatelessWidget {
  const GiftPlayer({
    super.key,
    required this.gift,
    required this.onComplete,
    this.onError,
  });

  final Gift gift;
  final VoidCallback onComplete;
  final VoidCallback? onError;

  @override
  Widget build(BuildContext context) {
    switch (gift.format) {
      case GiftFormat.svgCss:
        return SvgCssGiftPlayer(
          gift: gift,
          onComplete: onComplete,
          onError: onError,
        );
      case GiftFormat.video:
        return VideoGiftPlayer(
          gift: gift,
          onComplete: onComplete,
          onError: onError,
        );
    }
  }
}

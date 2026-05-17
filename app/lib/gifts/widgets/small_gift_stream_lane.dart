import 'package:flutter/material.dart';

import '../models/gift.dart';
import 'gift_player.dart';

class SmallGiftStreamLane extends StatelessWidget {
  const SmallGiftStreamLane({
    super.key,
    required this.items,
    required this.onComplete,
  });

  final List<SmallGiftItem> items;
  final void Function(String id) onComplete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: true,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          for (int i = items.length - 1; i >= 0 && i >= items.length - 6; i--)
            Positioned(
              bottom: (items.length - 1 - i) * 78.0,
              right: 0,
              child: AnimatedSlide(
                key: ValueKey(items[i].id),
                duration: const Duration(milliseconds: 260),
                offset: Offset.zero,
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: _SmallGiftCell(
                    item: items[i],
                    onComplete: () => onComplete(items[i].id),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallGiftCell extends StatelessWidget {
  const _SmallGiftCell({required this.item, required this.onComplete});

  final SmallGiftItem item;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return GiftPlayer(gift: item.gift, onComplete: onComplete);
  }
}

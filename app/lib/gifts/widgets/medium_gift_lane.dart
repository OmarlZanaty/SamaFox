import 'package:flutter/material.dart';

import '../models/gift.dart';
import 'gift_player.dart';

class MediumGiftLane extends StatelessWidget {
  const MediumGiftLane({
    super.key,
    required this.slots,
    required this.onSlotComplete,
  });

  final List<GiftSendEvent?> slots;
  final void Function(int slotIndex) onSlotComplete;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < slots.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: 200,
                height: 200,
                child: slots[i] == null
                    ? const SizedBox.shrink()
                    : GiftPlayer(
                        key: ValueKey('medium-$i-${slots[i]!.transactionId}'),
                        gift: slots[i]!.gift,
                        onComplete: () => onSlotComplete(i),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

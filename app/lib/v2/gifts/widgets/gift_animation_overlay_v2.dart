import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/gift_animation_provider.dart';
import '../services/gift_v2_socket_service.dart';
import 'broadcast_banner_layer.dart';
import 'fireworks_overlay.dart';
import 'gift_player.dart';
import 'medium_gift_lane.dart';
import 'sender_banner_layer.dart';
import 'small_gift_stream_lane.dart';

/// Full-screen gift animation stack. Mount above the voice room UI.
/// Caller is responsible for providing a [GiftV2SocketService] that
/// has been bound to the underlying socket.
class GiftAnimationOverlayV2 extends ConsumerStatefulWidget {
  const GiftAnimationOverlayV2({super.key, required this.socket});

  final GiftV2SocketService socket;

  @override
  ConsumerState<GiftAnimationOverlayV2> createState() => _GiftAnimationOverlayV2State();
}

class _GiftAnimationOverlayV2State extends ConsumerState<GiftAnimationOverlayV2> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(giftAnimationProvider.notifier).bindSocket(widget.socket);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(giftAnimationProvider);
    final notifier = ref.read(giftAnimationProvider.notifier);

    return IgnorePointer(
      ignoring: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: ambient small stream
          Positioned(
            right: 16,
            bottom: 100,
            width: 110,
            height: 480,
            child: SmallGiftStreamLane(
              items: state.smallStream,
              onComplete: (_) {/* controller handles cleanup by timer */},
            ),
          ),

          // Layer 2: medium overlays (top-left in LTR)
          Positioned(
            left: 16,
            top: 96,
            child: MediumGiftLane(
              slots: state.activeMediumSlots,
              onSlotComplete: notifier.onMediumComplete,
            ),
          ),

          // Layer 3: large center stage
          if (state.activeLarge != null)
            Center(
              child: SizedBox(
                width: 360,
                height: 360,
                child: GiftPlayer(
                  key: ValueKey('large-${state.activeLarge!.transactionId}'),
                  gift: state.activeLarge!.gift,
                  onComplete: notifier.onLargeComplete,
                ),
              ),
            ),

          // Layer 4: legendary takeover
          if (state.activeLegendary != null) ...[
            Positioned.fill(child: Container(color: const Color(0x66000000))),
            Positioned.fill(
              child: GiftPlayer(
                key: ValueKey('legendary-${state.activeLegendary!.transactionId}'),
                gift: state.activeLegendary!.gift,
                onComplete: notifier.onLegendaryComplete,
              ),
            ),
          ],

          // Layer 5: fireworks overlay
          if (state.fireworksActive)
            Positioned.fill(
              child: RepaintBoundary(
                child: FireworksOverlay(
                  key: ValueKey('fireworks-${state.activeLegendary?.transactionId ?? ''}'),
                  palette: state.fireworksPalette,
                  duration: Duration(
                    milliseconds: state.activeLegendary?.gift.animationMs ?? 4000,
                  ),
                ),
              ),
            ),

          // Layer 6: per-event sender banner
          const SenderBannerLayer(),

          // Layer 7: cross-room broadcasts
          BroadcastBannerLayer(socket: widget.socket),
        ],
      ),
    );
  }
}

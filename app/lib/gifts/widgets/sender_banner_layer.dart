import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift.dart';
import '../providers/gift_animation_provider.dart';

class SenderBannerLayer extends ConsumerWidget {
  const SenderBannerLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(giftAnimationProvider);
    final event = state.activeLegendary ?? state.activeLarge;
    if (event == null || event.sender == null) return const SizedBox.shrink();
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Positioned(
      top: 60,
      left: isRtl ? null : 16,
      right: isRtl ? 16 : null,
      child: IgnorePointer(
        ignoring: true,
        child: _SenderBanner(event: event),
      ),
    );
  }
}

class _SenderBanner extends StatefulWidget {
  const _SenderBanner({required this.event});
  final GiftSendEvent event;

  @override
  State<_SenderBanner> createState() => _SenderBannerState();
}

class _SenderBannerState extends State<_SenderBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final ev = widget.event;
    final fromX = isRtl ? 1.0 : -1.0;
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(fromX, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xCC1A0E3E), Color(0xCC2A1A5E)],
          ),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: const Color(0x66FFD700), width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF4A2A8C),
              backgroundImage: (ev.sender?.avatarUrl != null && ev.sender!.avatarUrl!.isNotEmpty)
                  ? NetworkImage(ev.sender!.avatarUrl!)
                  : null,
              child: (ev.sender?.avatarUrl == null || ev.sender!.avatarUrl!.isEmpty)
                  ? Text(
                      (ev.sender?.name.isNotEmpty == true ? ev.sender!.name[0] : '?').toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ev.sender?.name ?? '',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ev.gift.nameAr ?? ev.gift.name,
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    if (ev.quantity > 1) ...[
                      const SizedBox(width: 6),
                      Text('×${ev.quantity}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                    if (ev.comboCount > 1) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4081),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('COMBO x${ev.comboCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

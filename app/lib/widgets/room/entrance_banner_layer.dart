import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/room_controller_provider.dart';

/// Group 12: animated user-entrance banner.
///
/// When a user with an active entrance design (store purchase or VIP grant)
/// enters the room, a banner slides in from the left, pauses ~2.5s in the
/// middle, then slides out to the right and disappears. Entries queue so
/// simultaneous joins play one after another.
class EntranceBannerLayer extends ConsumerStatefulWidget {
  const EntranceBannerLayer({super.key, required this.roomId});
  final int roomId;

  @override
  ConsumerState<EntranceBannerLayer> createState() => _EntranceBannerLayerState();
}

class _EntranceBannerLayerState extends ConsumerState<EntranceBannerLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;

  final List<EntranceEvent> _queue = [];
  EntranceEvent? _current;
  bool _playing = false;
  int _lastSeq = 0;

  @override
  void initState() {
    super.initState();
    // slide in (0.5s) → pause (2.5s) → slide out (0.5s)
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );
    _offset = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: const Offset(-1.4, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 14,
      ),
      TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 72),
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: const Offset(1.4, 0))
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 14,
      ),
    ]).animate(_ctrl);
  }

  void _enqueue(EntranceEvent e) {
    // Only users who own an entrance design get the animated banner;
    // everyone still gets the chat line from the controller.
    if ((e.bannerUrl ?? '').trim().isEmpty) return;
    _queue.add(e);
    _maybePlay();
  }

  Future<void> _maybePlay() async {
    if (_playing || _queue.isEmpty || !mounted) return;
    _playing = true;
    setState(() => _current = _queue.removeAt(0));
    try {
      await _ctrl.forward(from: 0);
    } finally {
      _playing = false;
      if (mounted) setState(() => _current = null);
      _maybePlay();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EntranceEvent?>(
      roomControllerProvider(widget.roomId).select((s) => s.lastEntrance),
      (prev, next) {
        if (next == null || next.seq == _lastSeq) return;
        _lastSeq = next.seq;
        _enqueue(next);
      },
    );

    final e = _current;
    if (e == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 118),
          child: SlideTransition(
            position: _offset,
            child: Container(
              height: 54,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.86,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                image: DecorationImage(
                  image: NetworkImage(e.bannerUrl!),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.35),
                    BlendMode.darken,
                  ),
                  onError: (_, __) {},
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (e.vipLevel > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'VIP ${e.vipLevel}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      '${e.username} دخل الغرفة',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

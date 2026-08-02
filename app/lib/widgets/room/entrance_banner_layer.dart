import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/room_controller_provider.dart';

/// Group 12: animated user-entrance banner.
///
/// When a user with an active entrance design (store purchase or VIP grant)
/// enters the room, a banner slides in from the left, pauses ~2.5s in the
/// middle, then slides out to the right and disappears. Entries queue so
/// simultaneous joins play one after another.
///
/// The banner is drawn as artwork, not a tinted rectangle: a crest sits on the
/// left and a 9-sliced plate stretches behind the text, so long and short
/// usernames both keep the rounded end-cap intact. A purchased entrance item
/// replaces the plate texture; VIPs without one fall back to the bundled crest
/// design.
class EntranceBannerLayer extends ConsumerStatefulWidget {
  const EntranceBannerLayer({super.key, required this.roomId});
  final int roomId;

  @override
  ConsumerState<EntranceBannerLayer> createState() => _EntranceBannerLayerState();
}

class _EntranceBannerLayerState extends ConsumerState<EntranceBannerLayer>
    with SingleTickerProviderStateMixin {
  /// Crest artwork is 123x77; the plate is 226x46 with its flat middle between
  /// x 60..170 and y 18..28. Those numbers are the source-pixel slice guides —
  /// only the middle stretches, the rounded right cap never distorts.
  static const String _emblemAsset = 'assets/images/entrance_emblem.png';
  static const String _barAsset = 'assets/images/entrance_bar.png';
  static const Rect _barSlice = Rect.fromLTRB(60, 18, 170, 28);

  static const double _bannerHeight = 68;
  static const double _emblemWidth = _bannerHeight * 123 / 77; // ≈ 108
  static const double _barHeight = 42;
  // The plate is tucked under the crest so its straight left cut never shows.
  static const double _barInset = 46;

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

  /// Who gets the animated banner: anyone with an entrance design equipped, or
  /// any VIP (they fall back to the bundled crest). Everyone else still gets
  /// the plain chat line from the controller.
  bool _eligible(EntranceEvent e) =>
      (e.bannerUrl ?? '').trim().isNotEmpty || e.vipLevel > 0;

  void _enqueue(EntranceEvent e) {
    if (!_eligible(e)) return;
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

  /// The stretchable plate. A purchased design fills the same footprint; the
  /// bundled artwork is 9-sliced so only its middle grows.
  DecorationImage _plate(EntranceEvent e) {
    final url = (e.bannerUrl ?? '').trim();
    if (url.isNotEmpty) {
      return DecorationImage(
        image: NetworkImage(url),
        fit: BoxFit.fill,
        onError: (_, __) {},
      );
    }
    return const DecorationImage(
      image: AssetImage(_barAsset),
      centerSlice: _barSlice,
      fit: BoxFit.fill,
    );
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

    final maxBarWidth = MediaQuery.of(context).size.width * 0.86 - _barInset;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 118),
          child: SlideTransition(
            position: _offset,
            child: SizedBox(
              height: _bannerHeight,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: _barInset),
                    child: Container(
                      height: _barHeight,
                      constraints: BoxConstraints(
                        minWidth: 150,
                        maxWidth: maxBarWidth,
                      ),
                      // Text clears the crest on the left and the rounded cap
                      // on the right.
                      padding: const EdgeInsets.only(left: 74, right: 30),
                      decoration: BoxDecoration(image: _plate(e)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (e.vipLevel > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withOpacity(0.9),
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
                                shadows: [
                                  Shadow(color: Colors.black87, blurRadius: 4)
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Image.asset(
                    _emblemAsset,
                    height: _bannerHeight,
                    width: _emblemWidth,
                    fit: BoxFit.contain,
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

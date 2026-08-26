import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/room_controller_provider.dart';
import '../../utils/image_intrinsic_size.dart';

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
      // `centerSlice` is in the SOURCE image's pixels. Passing the BUNDLED
      // bar's 226x46 for every uploaded design sliced it in the wrong place;
      // the artwork's real size is resolved once per URL and cached.
      final intrinsic = _intrinsicBarSize(url);
      return DecorationImage(
        image: NetworkImage(url),
        // Only when the dashboard configured a slice AND the artwork has been
        // measured; otherwise the design stretches whole, exactly as before.
        centerSlice:
            intrinsic == null ? null : e.bannerLayout.centerSlice(intrinsic),
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

  /// Source-pixel size of a custom entry bar, or null while it resolves.
  Size? _intrinsicBarSize(String url) {
    final known = ImageIntrinsicSize.peek(url);
    if (known != null) return known;
    ImageIntrinsicSize.resolve(url).then((size) {
      if (size != null && mounted) setState(() {});
    });
    return null;
  }

  /// True when this entry uses a design bought/granted from the dashboard.
  /// A custom bar carries its own artwork end-to-end, so the bundled crest is
  /// NOT drawn over it and the plate is not tucked behind one — the client's
  /// "انا محكوم بالفارغ اللي بداخله ... مليش علاقه بالزخرفة".
  static bool _isCustom(EntranceEvent e) => (e.bannerUrl ?? '').trim().isNotEmpty;

  /// Padding that keeps "VIP 1  فهد  دخل الغرفة" inside the bar's empty middle.
  ///
  /// The bundled bar keeps its hand-tuned values (the text has to clear the
  /// crest on the left and the rounded cap on the right). A custom design uses
  /// whatever inner box the dashboard configured for it, resolved against the
  /// bar's own box.
  EdgeInsets _barPadding(EntranceEvent e, Size bar) {
    const bundled = EdgeInsets.only(left: 74, right: 30);
    if (!_isCustom(e)) return bundled;
    const fallback = EdgeInsets.symmetric(horizontal: 18, vertical: 8);
    return e.bannerLayout.padding(bar, fallback);
  }

  /// One decorated standing pill (VIP / LV) on the entry line.
  static Widget _standingPill(String label, Color from, Color to) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [from, to]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.55), width: 0.8),
          boxShadow: [BoxShadow(color: from.withOpacity(0.45), blurRadius: 5)],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
          ),
        ),
      );

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

    final custom = _isCustom(e);
    // A custom bar owns the whole width — there is no crest to tuck it behind.
    final barInset = custom ? 0.0 : _barInset;
    final maxBarWidth = MediaQuery.of(context).size.width * 0.86 - barInset;
    // 2026-08-23 — the bar used to be pinned to 42px while the line inside it
    // was free to be taller, which is exactly the reported
    // "شريط الدخوليه بيظهر رفيع والكلام اكبر منه". A custom design now takes its
    // height from its own content (floored at _barHeight) so the artwork always
    // encloses the text; the bundled bar keeps its fixed height because its
    // 9-slice guides are hand-tuned to it.
    final barBox = Size(maxBarWidth, custom ? _bannerHeight : _barHeight);

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
                    padding: EdgeInsets.only(left: barInset),
                    child: Container(
                      height: custom ? null : _barHeight,
                      constraints: BoxConstraints(
                        minWidth: 150,
                        maxWidth: maxBarWidth,
                        minHeight: custom ? _barHeight : 0,
                        maxHeight: custom ? _bannerHeight : double.infinity,
                      ),
                      // Confined to the bar's empty inner box.
                      padding: _barPadding(e, barBox),
                      decoration: BoxDecoration(image: _plate(e)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // "VIP 1  LV 5  فهد  دخل الغرفة" — each standing in
                          // its own decorated pill, side by side, ahead of the
                          // name (client: "دا عاوز جنب بعضه اللي هو الليفل
                          // والفي اي بي ... كل واحدة في مربع مزخرف").
                          if (e.vipLevel > 0) ...[
                            _standingPill(
                              'VIP ${e.vipLevel}',
                              const Color(0xFFFFD700),
                              const Color(0xFFFF8F00),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (e.level > 0) ...[
                            _standingPill(
                              'LV ${e.level}',
                              const Color(0xFF7C4DFF),
                              const Color(0xFF4A21C7),
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
                  // The bundled crest is part of the DEFAULT design only — it
                  // must never be painted on top of a purchased bar.
                  if (!custom)
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

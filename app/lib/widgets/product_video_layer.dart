import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// D5 — "جميع المنتجات اضيف (صوره- فيديو)".
///
/// The upload endpoint has accepted a video for every product type since
/// 2026-08-23, and the store sells them, but three of the places a product is
/// actually WORN only ever drew an image: the avatar frame, the chat bubble and
/// the entrance banner. A bought video frame resolved to a raster load, failed,
/// and fell through to `SizedBox.shrink()` — the user paid and saw nothing.
///
/// This is the missing renderer. Deliberately small:
///  • muted always. These play in a voice room; a frame with a soundtrack would
///    fight the call, and every one of them would play at once.
///  • looping, because a worn product is permanent — it is not an event.
///  • nothing on screen until the first frame is ready, and nothing on failure,
///    so a bad file degrades to the pre-existing "no decoration" look instead
///    of a spinner or a black box sitting on someone's avatar.
///  • no controls, no gestures — it is decoration and must never eat a tap.
class ProductVideoLayer extends StatefulWidget {
  const ProductVideoLayer({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
  });

  final String url;
  final BoxFit fit;

  @override
  State<ProductVideoLayer> createState() => _ProductVideoLayerState();
}

/// Is this product file a clip rather than a picture?
///
/// Extension-based on purpose: the URL is all the wearing widgets are given —
/// the product's mime type is known to the upload endpoint and to nobody else.
/// A query string is stripped first, since signed URLs carry one.
bool isProductVideoUrl(String? url) {
  if (url == null) return false;
  final path = url.split('?').first.toLowerCase();
  return path.endsWith('.mp4') ||
      path.endsWith('.webm') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v');
}

class _ProductVideoLayerState extends State<ProductVideoLayer> {
  VideoPlayerController? _controller;
  bool _ready = false;

  /// Decoders held right now by ALL product videos (frames, bubbles, banners).
  ///
  /// Each one is a separate player with its own hardware decoder, and nothing
  /// limited how many a room could open: every video frame on a seat, every
  /// video chat bubble on screen. سجل العملاء (2026-09-24) showed the app at
  /// 700 MB – 1.2 GB on mid-range phones and 26 sessions killed by the OS. Past
  /// the cap a decoration simply does not play — the same "no decoration" look
  /// as a clip that fails to load — until a slot frees up.
  static const int _maxActive = 6;
  static int _active = 0;
  bool _holdsSlot = false;

  void _releaseSlot() {
    if (_holdsSlot) {
      _holdsSlot = false;
      _active--;
    }
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant ProductVideoLayer old) {
    super.didUpdateWidget(old);
    // A seat can change hands, and the frame with it. Without this the new
    // owner would keep wearing the previous one's clip.
    if (old.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _releaseSlot();
      _ready = false;
      _open();
    }
  }

  Future<void> _open() async {
    if (_active >= _maxActive) {
      debugPrint('🎞️ [ProductVideoLayer] cap of $_maxActive reached — ${widget.url} not played');
      return;
    }
    _active++;
    _holdsSlot = true;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
      await controller.play();
    } catch (e) {
      // Decoration must never break the screen it decorates. Leave `_ready`
      // false so this renders as empty, exactly like a missing image — and
      // hand the decoder slot back, since a failed player plays nothing.
      debugPrint('🎞️ [ProductVideoLayer] ${widget.url} failed: $e');
      if (identical(_controller, controller)) {
        _controller = null;
        await controller.dispose();
        _releaseSlot();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _releaseSlot();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

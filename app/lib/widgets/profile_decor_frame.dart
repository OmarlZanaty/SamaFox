import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// إطار تزيين الصفحة الشخصية.
///
/// The client's spec: *"الاطار ده عباره عن مربع فارغ من النصف وله زينه وزخرفه،
/// منه صوره ومنه فيديو. المطلوب يكون علي حدود الصفحه الشخصيه ولا يغطي علي شئ من
/// الصفحه الشخصيه — يعني نفس نظام الاطار علي الحدود"*.
///
/// So this is drawn edge-to-edge ON TOP of the page, but it must never eat a
/// tap or hide content:
///   • [IgnorePointer] — every button underneath keeps working;
///   • `BoxFit.fill` — the artwork is stretched to the page's exact border, not
///     cropped, so its decorated corners land on the corners;
///   • the middle of the artwork is expected to be transparent — that is what
///     makes it a frame rather than a wallpaper. A product whose middle is
///     opaque would hide the page, which is a fault of the upload, not of this
///     widget, and the dashboard preview shows exactly what will render.
class ProfileDecorFrame extends StatefulWidget {
  const ProfileDecorFrame({
    super.key,
    required this.url,
    required this.isVideo,
  });

  final String url;
  final bool isVideo;

  @override
  State<ProfileDecorFrame> createState() => _ProfileDecorFrameState();
}

class _ProfileDecorFrameState extends State<ProfileDecorFrame> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  @override
  void didUpdateWidget(covariant ProfileDecorFrame old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.isVideo != widget.isVideo) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
      if (widget.isVideo) _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        // Decoration must never fight the room's voice or a background clip.
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = c;
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
      await c.play();
    } catch (_) {
      // A broken clip simply leaves the page undecorated.
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget art;
    if (widget.isVideo) {
      final c = _controller;
      if (c == null || !_ready) return const SizedBox.shrink();
      art = SizedBox.expand(
        child: FittedBox(
          // A frame clip is stretched to the border like a still one; cropping
          // it would push its corners off screen.
          fit: BoxFit.fill,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        ),
      );
    } else {
      art = Image.network(
        widget.url,
        fit: BoxFit.fill,
        // gif / webp animate on their own through this widget.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return IgnorePointer(child: art);
  }
}

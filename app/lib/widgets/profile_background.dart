import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// خلفية الصفحة الشخصية — the background a user picks for his own profile page.
///
/// Handles all three kinds the client asked for:
///   • a still image (jpg/png)
///   • an animated image (gif/webp) — `Image.network` animates these itself
///   • a video clip — muted, looping, no controls; it is wallpaper, not media
///
/// A dark scrim is painted on top so the white profile text stays readable over
/// whatever artwork the user chose.
class ProfileBackground extends StatefulWidget {
  const ProfileBackground({
    super.key,
    required this.url,
    required this.isVideo,
    this.scrim = 0.45,
  });

  final String url;
  final bool isVideo;

  /// 0 = show the artwork raw, 1 = black. Text over a bright photo needs this.
  final double scrim;

  @override
  State<ProfileBackground> createState() => _ProfileBackgroundState();
}

class _ProfileBackgroundState extends State<ProfileBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  @override
  void didUpdateWidget(covariant ProfileBackground old) {
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
        // Wallpaper must never fight the room's voice or the page's own audio.
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
      // A broken clip just leaves the default gradient showing.
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
      art = (c != null && _ready)
          ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            )
          : const SizedBox.shrink();
    } else {
      art = Image.network(
        widget.url,
        fit: BoxFit.cover,
        // gif / webp animate on their own through this widget.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        art,
        IgnorePointer(
          child: Container(color: Colors.black.withOpacity(widget.scrim)),
        ),
      ],
    );
  }
}

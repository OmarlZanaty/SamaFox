import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

class VideoPreview extends StatefulWidget {
  final String url;

  const VideoPreview({super.key, required this.url});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  bool isReady = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    VideoPlayerController controller;
    try {
      // Cached file first: a second look at the same clip costs no download.
      final cached = await DefaultCacheManager().getSingleFile(widget.url);
      controller = VideoPlayerController.file(File(cached.path));
    } catch (e) {
      debugPrint('[VideoPreview] cache miss for ${widget.url}, streaming: $e');
      controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    }
    if (_disposed) {
      controller.dispose();
      return;
    }
    _controller = controller;
    try {
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.initialize();
      if (_disposed) return;
      setState(() => isReady = true);
      await controller.play();
    } catch (e) {
      // A clip this device's decoder refuses (seen as MediaCodecVideoRenderer
      // errors on some phones) is a blank preview, not an uncaught error
      // reported as a crash.
      debugPrint('[VideoPreview] cannot play ${widget.url}: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!isReady || controller == null) {
      return const ColoredBox(color: Color(0xFF14102B));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}

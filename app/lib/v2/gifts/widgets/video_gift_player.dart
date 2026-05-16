import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../models/gift_v2.dart';

class VideoGiftPlayer extends StatefulWidget {
  const VideoGiftPlayer({
    super.key,
    required this.gift,
    required this.onComplete,
    this.onError,
  });

  final GiftV2 gift;
  final VoidCallback onComplete;
  final VoidCallback? onError;

  @override
  State<VideoGiftPlayer> createState() => _VideoGiftPlayerState();
}

class _VideoGiftPlayerState extends State<VideoGiftPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Timer? _hardTimer;
  bool _completed = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _hardTimer = Timer(
      Duration(milliseconds: widget.gift.animationMs + 500),
      _markComplete,
    );
  }

  Future<void> _initialize() async {
    final url = widget.gift.animationUrl;
    if (url == null || url.isEmpty) {
      widget.onError?.call();
      _markComplete();
      return;
    }
    try {
      VideoPlayerController controller;
      try {
        final cached = await DefaultCacheManager().getSingleFile(url);
        controller = VideoPlayerController.file(File(cached.path),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      } catch (_) {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }
      _controller = controller;
      await controller.initialize();
      controller.setLooping(false);
      controller.addListener(_onTick);
      if (!mounted) return;
      setState(() => _initialized = true);
      await controller.play();
    } catch (_) {
      widget.onError?.call();
      _markComplete();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null) return;
    if (c.value.hasError) {
      widget.onError?.call();
      _markComplete();
      return;
    }
    if (c.value.position >= c.value.duration && c.value.duration > Duration.zero) {
      _markComplete();
    }
  }

  void _markComplete() {
    if (_completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      c.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (!_completed) c.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hardTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !_initialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

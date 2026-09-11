import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../models/gift.dart';

class VideoGiftPlayer extends StatefulWidget {
  const VideoGiftPlayer({
    super.key,
    required this.gift,
    required this.onComplete,
    this.onError,
  });

  final Gift gift;
  final VoidCallback onComplete;
  final VoidCallback? onError;

  @override
  State<VideoGiftPlayer> createState() => _VideoGiftPlayerState();

  /// Longest a clip is ever allowed to hold the screen, whatever it says its
  /// duration is — a corrupt header must not freeze the room forever.
  static const Duration maxPlayback = Duration(seconds: 60);
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
    // Safety net only, until the real duration is known. `animationMs` is an
    // admin-typed number that has nothing to do with the uploaded file, so
    // using it as the cut-off chopped every clip that ran longer than it —
    // "الهديه لا تنزل كما وضعتها". Rearmed from the decoded duration below.
    _hardTimer = Timer(VideoGiftPlayer.maxPlayback, _markComplete);
  }

  /// D1 — a video gift that fails shows nothing at all, and the failure used
  /// to be discarded by a bare `catch (_)`. The sender had paid, the room saw
  /// an empty flash, and there was no way to tell a bad upload from a missing
  /// codec from a dead URL. Every failure path now says what happened and for
  /// which gift; the user-visible behaviour (skip the clip, don't hang the
  /// room) is unchanged.
  void _reportFailure(String stage, Object? error) {
    debugPrint(
      '🎬 [VideoGiftPlayer] $stage failed for gift ${widget.gift.id} '
      '(${widget.gift.animationUrl}): ${error ?? 'no detail'}',
    );
    widget.onError?.call();
  }

  Future<void> _initialize() async {
    final url = widget.gift.animationUrl;
    if (url == null || url.isEmpty) {
      _reportFailure('lookup', 'gift has no animationUrl');
      _markComplete();
      return;
    }
    try {
      VideoPlayerController controller;
      try {
        final cached = await DefaultCacheManager().getSingleFile(url);
        controller = VideoPlayerController.file(File(cached.path),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      } catch (e) {
        // Not a failure yet — the network player below is the real attempt.
        debugPrint('🎬 [VideoGiftPlayer] cache miss for $url, streaming: $e');
        controller = VideoPlayerController.networkUrl(
          Uri.parse(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }
      _controller = controller;
      await controller.initialize();
      controller.setLooping(false);
      // D1 — the clip's own audio track, at full volume. `mixWithOthers` is
      // what keeps this from hijacking the call: without it the platform gives
      // the video exclusive use of the audio session and the room goes silent
      // for as long as the gift plays.
      //
      // Routing is deliberately NOT forced here. The gift follows whatever the
      // call is already using — earpiece or speaker — because the alternative
      // is a gift that blasts out of the speaker while the user is holding the
      // phone to their ear. The room's own speaker toggle stays the one place
      // that decides.
      await controller.setVolume(1.0);
      controller.addListener(_onTick);
      if (!mounted) return;
      setState(() => _initialized = true);

      // Play for exactly as long as the FILE lasts (plus a small tail), so the
      // gift is seen the way it was uploaded.
      final real = controller.value.duration;
      if (real > Duration.zero) {
        _hardTimer?.cancel();
        final window = real + const Duration(milliseconds: 600);
        _hardTimer = Timer(
          window > VideoGiftPlayer.maxPlayback ? VideoGiftPlayer.maxPlayback : window,
          _markComplete,
        );
      }

      await controller.play();
    } catch (e) {
      _reportFailure('playback', e);
      _markComplete();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null) return;
    if (c.value.hasError) {
      _reportFailure('decode', c.value.errorDescription);
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
        // `contain`, not `cover`: gift clips are usually portrait and `cover`
        // cropped the sides of the artwork away.
        fit: BoxFit.contain,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

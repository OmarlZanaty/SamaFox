import 'package:flutter/material.dart';

import '../services/badge_size.dart';
import '../services/device_tier.dart';
import 'app_network_image.dart';

/// Two fixed sizes everywhere: square for round artwork, 2:1 otherwise.
/// Unknown dimensions use the rectangular size. Artwork is never cropped.
class UserBadgeImage extends StatefulWidget {
  const UserBadgeImage(this.url, {super.key});

  final String url;

  @override
  State<UserBadgeImage> createState() => _UserBadgeImageState();
}

class _UserBadgeImageState extends State<UserBadgeImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _round = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveShape();
  }

  @override
  void didUpdateWidget(UserBadgeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolveShape();
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  void _resolveShape() {
    _detach();
    _round = false;
    if (widget.url.trim().isEmpty) return;
    // A small still frame detects aspect ratio even for animated badges.
    final stream = StillNetworkImage(widget.url, height: 96)
        .resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener((info, synchronousCall) {
      final aspect = info.image.width / info.image.height;
      info.dispose();
      if (!mounted) return;
      final round = aspect >= 0.9 && aspect <= 1.1;
      if (_round != round) setState(() => _round = round);
    }, onError: (Object error, StackTrace? stackTrace) {
      // Keep the rectangular fallback on missing or invalid artwork.
    });
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = BadgeSize.value;
    final w = _round ? h : h * 2;
    return SizedBox(
      width: w,
      height: h,
      child: AppNetworkImage(
        widget.url,
        width: w,
        height: h,
        fit: BoxFit.contain,
        cacheHeight: (h * 3).round(),
        filterQuality: FilterQuality.medium,
        still: DeviceTier.ultraLite,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

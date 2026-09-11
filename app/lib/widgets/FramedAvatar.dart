import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/app_config.dart';
import '../models/product_layout.dart';
import '../utils/image_opaque_bounds.dart';
import '../widgets/app_network_image.dart';
import 'product_video_layer.dart';

enum AvatarFrameType { samafoxDefault, vip, crown, neon, none }

class AvatarFrame {
  final AvatarFrameType type;
  final String? frameAsset;
  final String? url;
  final double innerScale;

  /// Where this frame's inner hole is, as configured in لوحة التحكم. When set,
  /// it replaces [innerScale] entirely — the avatar is placed on the exact
  /// rectangle the admin marked out, so a frame with off-centre or asymmetric
  /// decoration still rings the picture properly.
  final ProductLayout layout;

  const AvatarFrame({
    required this.type,
    this.frameAsset,
    this.url,
    required this.innerScale,
    this.layout = ProductLayout.empty,
  });

  factory AvatarFrame.fromUrl(String url, {ProductLayout layout = ProductLayout.empty}) {
    return AvatarFrame(
      type: AvatarFrameType.none,
      url: url,
      frameAsset: null,
      innerScale: 0.60,
      layout: layout,
    );
  }

  factory AvatarFrame.fromAsset(String assetPath) {
    return AvatarFrame(
      type: AvatarFrameType.samafoxDefault,
      frameAsset: assetPath,
      url: null,
      innerScale: 0.62,
    );
  }

  static AvatarFrame fromType(AvatarFrameType type) {
    return const AvatarFrame(
      type: AvatarFrameType.none,
      frameAsset: null,
      url: null,
      innerScale: 0.62,
    );
  }
}

class FramedAvatar extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final String? fallbackText;
  final AvatarFrame? frame;
  final double avatarSize;
  final bool glow;
  final Color glowColor;

  const FramedAvatar({
    super.key,
    required this.size,
    required this.frame,
    this.imageUrl,
    this.fallbackText,
    this.glow = false,
    required this.avatarSize,
    this.glowColor = const Color(0xFF22C55E),
  });

  @override
  Widget build(BuildContext context) {
    final f = frame;

    // 2026-08-23 — the frame used to be blown up to 1.2× the seat and then
    // BoxFit.contain-ed, while the avatar sat on a fixed 60% circle. A frame
    // whose artwork carries transparent padding therefore rendered its ring
    // SMALLER than the picture and sitting low — the client's
    // "في الصورتين الايطار اصغر من المايك والصوره وكمان نازل تحت".
    //
    // Now the frame fills the seat box exactly, and the avatar is positioned on
    // the hole the dashboard marked out for that specific product. With no
    // configuration the old centred circle is used, so nothing regresses for
    // frames that were never measured.
    final hole = (f == null || !f.layout.hasInsets)
        ? null
        : f.layout.padding(Size(size, size), EdgeInsets.zero);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none, // ✅ allows frame to overflow outside
        children: [
          if (glow)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withOpacity(0.55),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          if (hole != null)
            Positioned(
              left: hole.left,
              top: hole.top,
              right: hole.right,
              bottom: hole.bottom,
              child: ClipOval(child: _avatarChild()),
            )
          else
            SizedBox(
              width: f != null ? size * f.innerScale : avatarSize,
              height: f != null ? size * f.innerScale : avatarSize,
              child: ClipOval(child: _avatarChild()),
            ),
          // The frame occupies the seat box itself. An unmeasured frame has its
          // artwork auto-fitted instead, so a file with a wide transparent
          // margin still puts its RING on the seat rather than somewhere inside
          // it — until that measurement lands (and for assets and SVGs, which
          // are not measured) the old 20% bleed is kept, so nothing regresses.
          Positioned.fill(
            child: IgnorePointer(
              child: hole != null
                  ? _frameChild()
                  : _AutoFitFrame(
                      url: _measurableFrameUrl(),
                      size: size,
                      child: _frameChild(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The frame's raster URL, or null when there is nothing to measure — an
  /// SVG has no pixels to scan and a bundled asset is already cropped.
  String? _measurableFrameUrl() {
    final raw = frame?.url;
    if (raw == null || raw.isEmpty) return null;
    final url = _absoluteUrl(raw);
    if (url.toLowerCase().endsWith('.svg')) return null;
    // D5 — nor a clip: there is no still to scan, and asking the image
    // pipeline for one logs a decode error on every rebuild.
    if (isProductVideoUrl(url)) return null;
    return url;
  }

  Widget _frameChild() {
    if (frame == null) return const SizedBox.shrink();

    final remoteUrl = frame!.url;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final url = _absoluteUrl(remoteUrl);
      if (url.toLowerCase().endsWith('.svg')) {
        return SvgPicture.network(url, fit: BoxFit.contain);
      }
      // D5 — a video frame used to be handed to the raster loader, fail, and
      // fall through to the errorBuilder's empty box: the user had bought a
      // frame and wore nothing.
      if (isProductVideoUrl(url)) {
        return ProductVideoLayer(url: url, fit: BoxFit.contain);
      }
      return AppNetworkImage(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    final asset = frame!.frameAsset;
    if (asset != null && asset.isNotEmpty) {
      if (asset.toLowerCase().endsWith('.svg')) {
        return SvgPicture.asset(asset, fit: BoxFit.contain);
      }
      return Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _avatarChild() {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return AppNetworkImage(
        _absoluteUrl(url),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final letter = (fallbackText?.trim().isNotEmpty == true)
        ? fallbackText!.trim()[0].toUpperCase()
        : '?';

    return Container(
      color: Colors.white10,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  String _absoluteUrl(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    // Static assets (avatars, frames) are served from the server ROOT
    // (e.g. http://host:3000/uploads/...), NOT under the /api/v1 base.
    final base = AppConfig.socketUrl.replaceFirst(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) return '$base$raw';
    return '$base/$raw';
  }
}

/// Scales frame artwork until the part of it that is actually painted fills the
/// seat box, and centres that part on the seat.
///
/// Only for frames لوحة التحكم has not measured. A configured frame is placed on
/// its own inner box and never comes through here.
class _AutoFitFrame extends StatefulWidget {
  const _AutoFitFrame({
    required this.url,
    required this.size,
    required this.child,
  });

  final String? url;
  final double size;
  final Widget child;

  @override
  State<_AutoFitFrame> createState() => _AutoFitFrameState();
}

class _AutoFitFrameState extends State<_AutoFitFrame> {
  OpaqueBounds? _bounds;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AutoFitFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bounds = null;
      _load();
    }
  }

  void _load() {
    final url = widget.url;
    if (url == null) return;

    final known = ImageOpaqueBounds.peek(url);
    if (known != null) {
      _bounds = known;
      return;
    }

    ImageOpaqueBounds.resolve(url).then((value) {
      if (!mounted || value == null || widget.url != url) return;
      setState(() => _bounds = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _bounds;
    // Not measured yet, unmeasurable, or already edge to edge: the artwork keeps
    // the bleed it has always had.
    if (b == null || b.isFull) {
      return Transform.scale(scale: 1.2, child: widget.child);
    }

    // Where BoxFit.contain drops the artwork inside the square seat box.
    final double drawnW = b.aspect >= 1 ? 1.0 : b.aspect;
    final double drawnH = b.aspect >= 1 ? 1.0 / b.aspect : 1.0;
    final double drawnX = (1.0 - drawnW) / 2;
    final double drawnY = (1.0 - drawnH) / 2;

    // The painted part, in box fractions.
    final double left = drawnX + b.rect.left * drawnW;
    final double top = drawnY + b.rect.top * drawnH;
    final double width = b.rect.width * drawnW;
    final double height = b.rect.height * drawnH;
    if (width <= 0 || height <= 0) {
      return Transform.scale(scale: 1.2, child: widget.child);
    }

    // Grow until the longer side of the paint spans the seat. Capped so a file
    // that is almost all margin cannot blow its ring up to absurd size.
    final double scale = (1.0 / math.max(width, height)).clamp(1.0, 3.0).toDouble();

    // Offset is measured before the scale is applied, which is why it is not
    // divided by it: the translation is scaled along with the child.
    final double dx = (0.5 - (left + width / 2)) * widget.size;
    final double dy = (0.5 - (top + height / 2)) * widget.size;

    return Transform.scale(
      scale: scale,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: widget.child,
      ),
    );
  }
}

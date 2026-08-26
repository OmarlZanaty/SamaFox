import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/app_config.dart';
import '../models/product_layout.dart';

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
          // The frame occupies the seat box itself. An unmeasured frame keeps
          // the old 10% bleed so existing artwork still looks the same.
          Positioned.fill(
            child: IgnorePointer(
              child: hole != null
                  ? _frameChild()
                  : Transform.scale(scale: 1.2, child: _frameChild()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _frameChild() {
    if (frame == null) return const SizedBox.shrink();

    final remoteUrl = frame!.url;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final url = _absoluteUrl(remoteUrl);
      if (url.toLowerCase().endsWith('.svg')) {
        return SvgPicture.network(url, fit: BoxFit.contain);
      }
      return Image.network(
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
      return Image.network(
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

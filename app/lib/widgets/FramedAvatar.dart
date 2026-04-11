import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AvatarFrameType { samafoxDefault, vip, crown, neon, none }

class AvatarFrame {
  final AvatarFrameType type;

  /// Local SVG frame (asset)
  final String? frameAsset;


  /// Remote frame (from backend)
  final String? url;

  /// Inner avatar scale
  final double innerScale;

  const AvatarFrame({
    required this.type,
    this.frameAsset,
    this.url,


    required this.innerScale,
  });

  /// 🔥 FROM BACKEND (URL FRAME)
  factory AvatarFrame.fromUrl(String url) {
    return AvatarFrame(
      type: AvatarFrameType.none,
      url: url,
      frameAsset: null,
      innerScale: 0.62,
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

  /// 🔥 LOCAL TYPES (SVG)
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
  final double size; // total widget size (frame size)
  final String? imageUrl;
  final String? fallbackText;
  final AvatarFrame? frame;
  final double avatarSize; // ✅ ADD THIS
  /// Optional: show glow ring (later for speaking)
  final bool glow;
  final Color glowColor;

  const FramedAvatar({
    super.key,
    required this.size,
    required this.frame,
    this.imageUrl,
    this.fallbackText,
    this.glow = false,
    required this.avatarSize, // ✅ REQUIRED
    this.glowColor = const Color(0xFF22C55E),
  });

  @override
  Widget build(BuildContext context) {
    final innerSize = avatarSize;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ✅ glow behind everything
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

          // ✅ FRAME (BOTTOM — IMPORTANT)
          // ✅ FRAME (BOTTOM — IMPORTANT)
          // In FramedAvatar build(), the frame builder section — replace with:
          Positioned.fill(
            child: IgnorePointer(
              child: Builder(
                builder: (_) {
                  if (frame == null) return const SizedBox.shrink();

                  // ✅ Remote URL frame (from DB)
                  if (frame!.url != null && frame!.url!.isNotEmpty) {
                    final url = frame!.url!.toLowerCase();
                    if (url.endsWith('.svg')) {
                      return SvgPicture.network(
                        frame!.url!,
                        fit: BoxFit.contain,
                      );
                    }
                    return Image.network(
                      frame!.url!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    );
                  }

                  // ✅ Local asset frame (default fallback)
                  if (frame!.frameAsset != null && frame!.frameAsset!.isNotEmpty) {
                    if (frame!.frameAsset!.endsWith('.svg')) {
                      return SvgPicture.asset(
                        frame!.frameAsset!,
                        fit: BoxFit.contain,
                      );
                    }
                    // ✅ PNG/WebP asset
                    return Image.asset(
                      frame!.frameAsset!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ),

          // ✅ AVATAR (TOP — smaller, visible inside frame)
          SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: ClipOval(
              child: _avatarChild(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarChild() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
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
}

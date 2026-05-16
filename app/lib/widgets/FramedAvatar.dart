import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/app_config.dart';

enum AvatarFrameType { samafoxDefault, vip, crown, neon, none }

class AvatarFrame {
  final AvatarFrameType type;
  final String? frameAsset;
  final String? url;
  final double innerScale;

  const AvatarFrame({
    required this.type,
    this.frameAsset,
    this.url,
    required this.innerScale,
  });

  factory AvatarFrame.fromUrl(String url) {
    return AvatarFrame(
      type: AvatarFrameType.none,
      url: url,
      frameAsset: null,
      innerScale: 0.60,
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
          SizedBox(
            width: frame != null ? size * frame!.innerScale : avatarSize,
            height: frame != null ? size * frame!.innerScale : avatarSize,
            child: ClipOval(child: _avatarChild()),
          ),
          Positioned(
            top: -(size * 0.1),
            left: -(size * 0.1),
            right: -(size * 0.1),
            bottom: -(size * 0.1),
            child: IgnorePointer(child: _frameChild()),
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
    final base = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) return '$base$raw';
    return '$base/$raw';
  }
}

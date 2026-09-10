import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Every remote image in the app, cached on disk and decoded at the size it is
/// actually drawn at.
///
/// `Image.network` keeps nothing on disk. Flutter's in-memory image cache is
/// cleared with the app, so avatars, mic frames, product art, room covers and
/// gift icons were re-downloaded on every cold start and every time a screen
/// that had scrolled out of the cache came back — the "بطء عام" the client
/// reports, and why the store feels slowest of all: it is the screen with the
/// most images per pixel of scroll.
///
/// It also decodes at FULL resolution. A 1024px badge PNG drawn into a 16px box
/// still costs 1024×1024×4 ≈ 4MB of RAM and a full-size decode, which is what
/// makes lists stutter as they scroll.
///
/// This is a drop-in for `Image.network`: same positional URL, same named
/// arguments the app uses ([width], [height], [fit], [cacheWidth],
/// [filterQuality], [errorBuilder]). Underneath it is [CachedNetworkImage], so
/// the bytes land in the shared `flutter_cache_manager` store and survive
/// restarts, and the decode is capped at the drawn size.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode,
    this.placeholder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// Decode cap in PIXELS, like `Image.network`'s argument of the same name.
  /// When omitted it is derived from [width] so a badge never decodes at poster
  /// resolution; a caller that genuinely wants the full-size decode (a preview
  /// the user can zoom) passes a large value explicitly.
  final int? cacheWidth;
  final int? cacheHeight;

  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final Alignment alignment;
  final Color? color;
  final BlendMode? colorBlendMode;

  /// Shown while the bytes are in flight. Defaults to empty space — most of
  /// these images sit inside a coloured tile that already looks fine bare.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return errorBuilder?.call(context, 'empty url', null) ??
          const SizedBox.shrink();
    }

    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;

    int? memWidth = cacheWidth;
    int? memHeight = cacheHeight;
    if (memWidth == null && memHeight == null) {
      if (width != null && width!.isFinite && width! > 0) {
        memWidth = (width! * dpr).round();
      } else if (height != null && height!.isFinite && height! > 0) {
        memHeight = (height! * dpr).round();
      }
    }

    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      color: color,
      colorBlendMode: colorBlendMode,
      filterQuality: filterQuality,
      memCacheWidth: memWidth,
      memCacheHeight: memHeight,
      // A cached image is already on disk; fading it in every time it scrolls
      // back reads as sluggishness rather than polish.
      fadeInDuration: const Duration(milliseconds: 90),
      fadeOutDuration: Duration.zero,
      placeholder: placeholder == null ? null : (_, __) => placeholder!,
      errorWidget: (context, _, error) =>
          errorBuilder?.call(context, error, null) ?? const SizedBox.shrink(),
    );
  }
}

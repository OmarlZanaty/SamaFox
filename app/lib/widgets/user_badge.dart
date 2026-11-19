import 'package:flutter/material.dart';

import '../services/badge_size.dart';
import '../services/device_tier.dart';
import 'app_network_image.dart';

/// A badge's artwork at the ONE badge height used everywhere in the app.
///
/// The uploaded art can be any pixel size and any aspect ratio, so the height
/// is fixed ([BadgeSize.value] unless [height] is given), the width follows the
/// art but never passes `height * 2.2`, and the picture is fitted inside
/// (BoxFit.contain) — never stretched, never cropped.
class UserBadgeImage extends StatelessWidget {
  const UserBadgeImage(this.url, {super.key, this.height});

  final String url;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final h = height ?? BadgeSize.value;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: h * 2.2, maxHeight: h),
      child: AppNetworkImage(
        url,
        height: h,
        fit: BoxFit.contain,
        cacheHeight: (h * 3).round(),
        filterQuality: FilterQuality.medium,
        // A row of badges is a row of open GIF/WebP decoders.
        still: DeviceTier.ultraLite,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

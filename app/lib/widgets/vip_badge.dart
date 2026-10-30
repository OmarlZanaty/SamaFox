import 'package:flutter/material.dart';
import 'package:samafox/services/level_catalog_service.dart';
import '../widgets/app_network_image.dart';

/// VIP chip shown for users with a VIP level (Step 3/4). Renders nothing for
/// level 0.
///
/// Follows لوحة التحكم: when an admin configures a badge image or a name for
/// the tier (`/api/v1/vip/levels`), that is what shows. The golden "VIP N" chip
/// stays as the fallback for unconfigured tiers, so the app looks unchanged
/// until the dashboard actually says otherwise.
class VipBadge extends StatefulWidget {
  const VipBadge({super.key, required this.level, this.fontSize = 11});

  final int level;
  final double fontSize;

  @override
  State<VipBadge> createState() => _VipBadgeState();
}

class _VipBadgeState extends State<VipBadge> {
  @override
  void initState() {
    super.initState();
    if (widget.level > 0 && LevelCatalogService.vipLevel(widget.level) == null) {
      LevelCatalogService.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.level <= 0) return const SizedBox.shrink();

    final tier = LevelCatalogService.vipLevel(widget.level);
    final badgeUrl = LevelCatalogService.absoluteBadgeUrl(tier?.badgeUrl);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _chip(null),
      if (badgeUrl != null) ...[
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.fontSize * 1.8, maxWidth: widget.fontSize * 3.4),
          child: AppNetworkImage(badgeUrl, height: widget.fontSize * 1.8,
            fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
      ],
    ]);
  }

  Widget _chip(String? name) {
    final fontSize = widget.fontSize;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.7, vertical: fontSize * 0.22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x66FFD700), blurRadius: 6, spreadRadius: 0.5),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: fontSize * 1.2, color: Colors.white),
          SizedBox(width: fontSize * 0.25),
          Text(
            name ?? 'VIP ${widget.level}',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

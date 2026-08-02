import 'package:flutter/material.dart';
import 'package:samafox/services/level_catalog_service.dart';

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
    if (badgeUrl != null) {
      return Image.network(
        badgeUrl,
        height: widget.fontSize * 1.8,
        fit: BoxFit.contain,
        // A deleted or broken upload must never blank the badge out.
        errorBuilder: (_, __, ___) => _chip(tier?.name),
      );
    }
    return _chip(tier?.name);
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

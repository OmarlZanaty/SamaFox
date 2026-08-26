import 'package:flutter/material.dart';
import 'package:samafox/services/level_catalog_service.dart';

/// LV (المستوى) chip — the counterpart of [VipBadge], following the same rule:
/// لوحة التحكم wins when it configures a badge image or a name for the tier
/// (`/api/v1/levels`), otherwise the built-in cyan chip is used, so nothing
/// changes until an admin configures the tier.
class LevelBadge extends StatefulWidget {
  const LevelBadge({super.key, required this.level, this.fontSize = 16});

  final int level;
  final double fontSize;

  @override
  State<LevelBadge> createState() => _LevelBadgeState();
}

class _LevelBadgeState extends State<LevelBadge> {
  @override
  void initState() {
    super.initState();
    if (LevelCatalogService.level(widget.level) == null) {
      LevelCatalogService.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = LevelCatalogService.level(widget.level);
    final badgeUrl = LevelCatalogService.absoluteBadgeUrl(tier?.badgeUrl);
    if (badgeUrl != null) {
      // The dashboard may hold a very large PNG. Clamping BOTH axes and using
      // BoxFit.contain makes every uploaded badge render at the app's own badge
      // size instead of blowing the row apart (client: "تظهر في التطبيق صغيرة").
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.fontSize * 1.8,
          maxWidth: widget.fontSize * 3.4,
        ),
        child: Image.network(
        badgeUrl,
        height: widget.fontSize * 1.8,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _chip(tier?.name),
      ),
      );
    }
    return _chip(tier?.name);
  }

  Widget _chip(String? name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A level chip, so it carries a level icon — the gender symbol that
          // used to sit here now lives next to the age instead.
          Icon(Icons.military_tech, color: Colors.white, size: widget.fontSize),
          const SizedBox(width: 4),
          Text(
            name ?? '${widget.level}',
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

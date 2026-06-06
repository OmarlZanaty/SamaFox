import 'package:flutter/material.dart';

/// Small golden "VIP N" chip shown for users with a VIP level (Step 3/4).
/// Renders nothing for level 0. An admin-uploaded badge image, when wired to
/// the /api/v1/vip/levels catalog, can replace the text later.
class VipBadge extends StatelessWidget {
  const VipBadge({super.key, required this.level, this.fontSize = 11});

  final int level;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (level <= 0) return const SizedBox.shrink();
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
            'VIP $level',
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

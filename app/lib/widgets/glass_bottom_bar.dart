import 'dart:ui';
import 'package:flutter/material.dart';

class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({
    super.key,
    required this.homeLabel,
    required this.searchLabel,
    required this.gamesLabel,
    required this.profileLabel,
    required this.onHome,
    required this.onSearch,
    required this.onGames,
    required this.onProfile,
    required this.onCenter,
    required this.hasRoom,
    this.roomImageUrl,
  });

  final String homeLabel;
  final String searchLabel;
  final String gamesLabel;
  final String profileLabel;
  final bool hasRoom;
  final VoidCallback onHome;
  final VoidCallback onSearch;
  final VoidCallback onGames;
  final VoidCallback onProfile;
  final VoidCallback onCenter;
  final String? roomImageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              Expanded(child: BarItem(icon: Icons.home_rounded, label: homeLabel, onTap: onHome)),
              Expanded(child: BarItem(icon: Icons.message_rounded, label: searchLabel, onTap: onSearch)),
              // المتجر / وكلاء الشحن moved to the profile screen's quick-access row.
              Expanded(child: BarItem(icon: Icons.videogame_asset_rounded, label: gamesLabel, onTap: onGames)),
              Expanded(child: BarItem(icon: Icons.person_rounded, label: profileLabel, onTap: onProfile)),
            ],
          ),
        ),
      ),
    );
  }
}

class BarItem extends StatelessWidget {
  const BarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        height: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.85), size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
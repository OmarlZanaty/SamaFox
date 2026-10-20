import 'package:flutter/material.dart';

/// Width the seats area leaves free on the left for the rail.
const double kRoomRailGutter = 40;

/// SPEC52 #19 / #28 / #29 — the column at the top-LEFT of the room, under the
/// header: [PK] above [Rocket] above [Games]. Physically left in RTL too (the
/// caller positions it with `left:`), and it only takes its own width, so the
/// seats keep the space the bottom bar used to give the games button.
class RoomLeftRail extends StatelessWidget {
  const RoomLeftRail({
    super.key,
    required this.onGames,
    this.pk,
    this.rocket,
  });

  final VoidCallback onGames;
  final Widget? pk;
  final Widget? rocket;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pk != null) ...[pk!, const SizedBox(height: 8)],
        if (rocket != null) ...[rocket!, const SizedBox(height: 8)],
        RoomRailButton(
          icon: Icons.sports_esports_rounded,
          color: Colors.greenAccent,
          label: 'ألعاب',
          onTap: onGames,
        ),
      ],
    );
  }
}

/// A round glassy button with a tiny caption, used by the rail.
class RoomRailButton extends StatelessWidget {
  const RoomRailButton({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.45),
                  border: Border.all(color: color.withOpacity(0.7), width: 1.2),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 8)],
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              if (badge != null)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                    child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black, blurRadius: 3)],
              )),
        ],
      ),
    );
  }
}

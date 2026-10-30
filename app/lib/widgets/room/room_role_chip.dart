import 'package:flutter/material.dart';
import '../../l10n/tr.dart';

class RoomRoleChip extends StatelessWidget {
  const RoomRoleChip({super.key, required this.isOwner, this.size = 16});
  final bool isOwner;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: isOwner ? tr('صاحب الغرفة', 'Room owner') : tr('مشرف الغرفة', 'Room admin'),
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOwner ? const Color(0xFFFF8A00) : const Color(0xFF22C55E),
      ),
      child: Icon(isOwner ? Icons.home_rounded : Icons.person_rounded,
          color: Colors.white, size: size),
    ),
  );
}

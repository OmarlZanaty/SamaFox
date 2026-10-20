import 'package:flutter/material.dart';

import '../app_network_image.dart';

/// SPEC52 #15 — "معلومات الغرفة": opened by tapping the room picture, for
/// everyone. Read-only; owners/admins/super-admins also get their existing
/// edit/close actions as buttons here (still authorised by the server).
class RoomInfoSheet extends StatelessWidget {
  const RoomInfoSheet({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.roomIdLabel,
    required this.ownerName,
    required this.ownerAvatarUrl,
    required this.ownerIdLabel,
    required this.usersCount,
    required this.usedSeats,
    required this.totalSeats,
    this.onOwnerTap,
    this.onEdit,
    this.onClose,
  });

  final String? imageUrl;
  final String name;
  final String roomIdLabel;
  final String? ownerName;
  final String? ownerAvatarUrl;
  final String? ownerIdLabel;
  final int usersCount;
  final int usedSeats;
  final int totalSeats;
  final VoidCallback? onOwnerTap;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;

  static Future<void> show(BuildContext context, RoomInfoSheet sheet) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Directionality(textDirection: TextDirection.rtl, child: sheet),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final side = (mq.size.width * 0.30).clamp(84.0, 132.0);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2B1A5E), Color(0xFF160C33)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.7), width: 2),
                boxShadow: [BoxShadow(color: const Color(0xFFB388FF).withOpacity(0.35), blurRadius: 18)],
              ),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl ?? '').trim().isNotEmpty
                  ? AppNetworkImage(imageUrl!.trim(), fit: BoxFit.cover, cacheWidth: (side * mq.devicePixelRatio).round())
                  : const ColoredBox(
                      color: Color(0xFF5E35B1),
                      child: Icon(Icons.mic, color: Colors.white, size: 40),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(roomIdLabel, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _stat(Icons.people_alt_rounded, '$usersCount', 'المتواجدون')),
                const SizedBox(width: 10),
                Expanded(child: _stat(Icons.mic_rounded, '$usedSeats / $totalSeats', 'المايكات المستخدمة')),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onOwnerTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.deepPurple,
                      backgroundImage: (ownerAvatarUrl ?? '').trim().isNotEmpty ? appImage(ownerAvatarUrl!.trim(), 40) : null,
                      child: (ownerAvatarUrl ?? '').trim().isNotEmpty ? null : const Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('صاحب الغرفة', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          Text(ownerName ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          if (ownerIdLabel != null)
                            Text(ownerIdLabel!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left, color: Colors.white38),
                  ],
                ),
              ),
            ),
            if (onEdit != null || onClose != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onEdit != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('تعديل الغرفة'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  if (onEdit != null && onClose != null) const SizedBox(width: 10),
                  if (onClose != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onClose,
                        icon: const Icon(Icons.lock, size: 18),
                        label: const Text('إغلاق الغرفة'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFFFD54F), size: 20),
            const SizedBox(height: 4),
            // "3 / 10" must read left-to-right even inside the RTL sheet.
            Text(value,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      );
}

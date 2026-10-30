import 'package:flutter/material.dart';

import '../marquee_text.dart';

/// SPEC52 #14 — the room's name and ID in a translucent "glass" plate.
///
/// The speaker and keep-room buttons left the header, so the name gets the
/// width they freed. 23/10: a translucent gradient replaces the blur, which
/// reran on every frame while the name scrolled. 26/10 (@431): «خلي لون المربع
/// له لون شفاف مثلا اخضر اصفر ازرق بس يكون شفاف» — a coloured, see-through
/// glass: tinted body, light sheen on top, tinted rim.
class RoomHeaderGlass extends StatelessWidget {
  const RoomHeaderGlass({
    super.key,
    required this.name,
    required this.idLabel,
    required this.onTap,
    this.tint = const Color(0xFF19C37D),
  });

  final String name;

  /// The glass colour (green by default; blue / yellow work the same way).
  final Color tint;

  /// e.g. "ID: 123456" — null hides the second line.
  final String? idLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 10, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.45, 1],
              colors: [
                Color.lerp(tint, Colors.white, 0.35)!.withValues(alpha: 0.42),
                tint.withValues(alpha: 0.26),
                tint.withValues(alpha: 0.16),
              ],
            ),
            border: Border.all(color: Color.lerp(tint, Colors.white, 0.4)!.withValues(alpha: 0.6), width: 1),
            boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.25), blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MarqueeText(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              if (idLabel != null)
                Text(
                  idLabel!,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

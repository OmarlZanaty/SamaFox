import 'dart:ui';

import 'package:flutter/material.dart';

import '../marquee_text.dart';

/// SPEC52 #14 — the room's name and ID in a translucent "glass" plate.
///
/// The speaker and keep-room buttons left the header, so the name gets the
/// width they freed. The blur is limited to this small plate (never the whole
/// screen), which keeps it cheap on Realme C3-class phones.
class RoomHeaderGlass extends StatelessWidget {
  const RoomHeaderGlass({
    super.key,
    required this.name,
    required this.idLabel,
    required this.onTap,
  });

  final String name;

  /// e.g. "ID: 123456" — null hides the second line.
  final String? idLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 10, 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.16),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
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
      ),
    );
  }
}

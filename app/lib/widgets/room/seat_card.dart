import 'package:flutter/material.dart';
import '../../services/socket_service.dart';
import '../FramedAvatar.dart';

class SeatCard extends StatelessWidget {
  final int seatNumber;
  final SeatData seat;
  final bool isMine;
  final bool isAdmin;
  final VoidCallback onTap;
  final bool isOwnerSeat;
  final bool isAdminSeat;
  final bool isSeatLocked;
  final bool isSeatMuted; // #11: admin-muted seat (show mute icon even when empty)
  final int coins24h; // gift coins received in this room (last 24h)

  /// Avatar diameter, solved by [SeatsGrid] so every mic fits in the top half
  /// of the screen without scrolling. It used to be hardcoded at 62.
  final double seatSize;

  const SeatCard({
    super.key,
    required this.seatNumber,
    required this.seat,
    required this.isMine,
    required this.onTap,
    required this.isAdmin,
    this.seatSize = 62,
    this.isOwnerSeat = false,
    this.isAdminSeat = false,
    this.isSeatLocked = false,
    this.isSeatMuted = false,
    this.coins24h = 0,
  });

  static String _fmtCoins(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  bool get _isOccupied => seat.userId != null;

  @override
  Widget build(BuildContext context) {
    final imageUrl = seat.avatarUrl;
    final username = (seat.username?.trim().isNotEmpty == true) ? seat.username! : 'User';
    final isMuted = seat.isMuted;
    final locked = isSeatLocked;

    final outerSize = seatSize;
    // The bare (frameless) avatar keeps the same proportion it always had.
    final innerAvatar = seatSize * (50.0 / 62.0);
    // Labels shrink with the seat so a 30-mic room doesn't turn into text.
    final nameSize = (seatSize * (10.0 / 62.0)).clamp(7.0, 11.0);
    final coinSize = (seatSize * (9.0 / 62.0)).clamp(6.5, 10.0);
    final badgeSize = (seatSize * (18.0 / 62.0)).clamp(12.0, 20.0);

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: locked && !_isOccupied ? 0.55 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Avatar / Empty Seat ──
            SizedBox(
              width: outerSize,
              height: outerSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isOccupied)
                  // Occupied: show framed avatar
                    FramedAvatar(
                      size: outerSize,
                      avatarSize: innerAvatar,
                      imageUrl: imageUrl,
                      fallbackText: username,
                      frame: (seat.avatarFrameUrl != null &&
                          seat.avatarFrameUrl!.isNotEmpty)
                          ? AvatarFrame.fromUrl(seat.avatarFrameUrl!,
                              layout: seat.frameLayout)
                          : null,
                      glow: seat.isSpeaking,
                    ),

                  // ── من المتحدث؟ ──
                  // A pulsing ring around whoever is actually speaking, so the
                  // room can tell at a glance. It stops the moment they go
                  // quiet ("واذا سكت تختفي الدائره"). Drawn UNDER the mute
                  // badge and outside the avatar so it never hides the face.
                  if (_isOccupied && seat.isSpeaking)
                    IgnorePointer(child: _SpeakingRing(size: outerSize)),

                  if (!_isOccupied)
                  // Empty seat: mic icon with gradient ring
                    Container(
                      width: outerSize,
                      height: outerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: locked ? const Color(0xFF3A3A3A) : const Color(0xFF555555),
                        border: Border.all(
                          color: locked
                              ? Colors.red.withOpacity(0.4)
                              : Colors.white.withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: locked
                          ? Icon(Icons.lock, size: outerSize * 0.36, color: Colors.redAccent)
                          : isSeatMuted
                              // #11: show mute icon on an empty admin-muted seat too.
                              ? Icon(Icons.mic_off_rounded, size: outerSize * 0.39, color: Colors.orangeAccent)
                              : Icon(
                                  Icons.mic_none_rounded,
                                  size: outerSize * 0.39,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                    ),

                  // Mute badge (occupied only)
                  if (_isOccupied && isMuted)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: badgeSize,
                        height: badgeSize,
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: Icon(Icons.mic_off, size: badgeSize * 0.61, color: Colors.white),
                      ),
                    ),

                    ],
                      ),
                    ),

            const SizedBox(height: 4),

            // ── Label: name if occupied, seat number if empty ──
            SizedBox(
              width: outerSize,
              child: _isOccupied
                  ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // ✅ Show username if seat is taken
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: nameSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (coins24h > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.monetization_on, color: const Color(0xFFFFD700), size: coinSize + 1),
                        const SizedBox(width: 2),
                        Text(
                          _fmtCoins(coins24h),
                          style: TextStyle(color: const Color(0xFFFFD700), fontSize: coinSize, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                ],
              )
                  : Text(
                // ✅ Show seat number if empty
                locked ? '🔒 $seatNumber' : '$seatNumber',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: locked
                      ? Colors.red.withOpacity(0.7)
                      : Colors.white.withOpacity(0.4),
                  fontSize: nameSize,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two concentric rings that expand and fade out of the avatar, restarting for
/// as long as the user holds the mic. Deliberately cheap: one repeating
/// controller driving two CustomPaint circles, no images and no layout work, so
/// twenty of them on screen cost nothing measurable.
class _SpeakingRing extends StatefulWidget {
  const _SpeakingRing({required this.size});

  final double size;

  @override
  State<_SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<_SpeakingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _SpeakingRingPainter(_c.value)),
      ),
    );
  }
}

class _SpeakingRingPainter extends CustomPainter {
  _SpeakingRingPainter(this.t);

  /// 0..1, repeating.
  final double t;

  static const Color _color = Color(0xFF22C55E);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2;

    // Two waves half a cycle apart, so there is always a ring on screen.
    for (final phase in const [0.0, 0.5]) {
      final p = (t + phase) % 1.0;
      final radius = base * (0.92 + p * 0.34);
      final opacity = (1 - p) * 0.55;
      if (opacity <= 0) continue;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = _color.withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeakingRingPainter old) => old.t != t;
}

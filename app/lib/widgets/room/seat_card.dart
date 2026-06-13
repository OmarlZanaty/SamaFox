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
  final int coins24h; // gift coins received in this room (last 24h)

  const SeatCard({
    super.key,
    required this.seatNumber,
    required this.seat,
    required this.isMine,
    required this.onTap,
    required this.isAdmin,
    this.isOwnerSeat = false,
    this.isAdminSeat = false,
    this.isSeatLocked = false,
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

    const outerSize = 62.0;
    const innerAvatar = 50.0;

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
                          ? AvatarFrame.fromUrl(seat.avatarFrameUrl!)
                          : null,
                      glow: seat.isSpeaking,
                    )
                  else
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
                          ? const Icon(Icons.lock, size: 22, color: Colors.redAccent)
                          : Icon(
                        Icons.mic_none_rounded,
                        size: 24,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),

                  // Mute badge (occupied only)
                  if (_isOccupied && isMuted)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: const Icon(Icons.mic_off, size: 11, color: Colors.white),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (coins24h > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 10),
                        const SizedBox(width: 2),
                        Text(
                          _fmtCoins(coins24h),
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 9, fontWeight: FontWeight.w600),
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
                  fontSize: 10,
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

class SeatsGrid extends StatelessWidget {
  final Map<int, SeatData> seats;
  final int seatCount;
  final int ownerId;
  final List<int> adminIds;
  final Set<int> lockedSeats;

  final bool scrollable;
  final int? myUserId;
  final bool isAdmin;
  final void Function(int seatNumber, SeatData seat) onSeatTap;

  final Map<int, GlobalKey> seatKeys;

  const SeatsGrid({
    super.key,
    required this.seats,
    required this.seatCount,
    required this.myUserId,
    required this.isAdmin,
    required this.onSeatTap,
    required this.ownerId,
    required this.adminIds,
    required this.lockedSeats,
    required this.seatKeys,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final safeCount = seatCount.clamp(1, 24);
    final seatNumbers = List<int>.generate(safeCount, (i) => i + 1);

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      shrinkWrap: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: seatNumbers.length,
      cacheExtent: 400,
      addRepaintBoundaries: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
        // ✅ Increased to give more vertical room and prevent overflow
        childAspectRatio: 0.72,
      ),
      itemBuilder: (_, i) {
        final seatNumber = seatNumbers[i];
        final isLocked = lockedSeats.contains(seatNumber);
        final seat = seats[seatNumber] ?? SeatData.empty(seatNumber);
        final uid = seat.userId;
        final isMine = uid != null && uid == myUserId;
        final isOwnerSeat = uid != null && uid == ownerId;
        final isAdminSeat =
            uid != null && adminIds.contains(uid) && !isOwnerSeat;
        final seatKey =
        seatKeys.putIfAbsent(seatNumber, () => GlobalKey());

        return KeyedSubtree(
          key: seatKey,
          child: SeatCard(
            seatNumber: seatNumber,
            seat: seat,
            isMine: isMine,
            isAdmin: isAdmin,
            isSeatLocked: isLocked,
            isOwnerSeat: isOwnerSeat,
            isAdminSeat: isAdminSeat,
            onTap: () => onSeatTap(seatNumber, seat),
          ),
        );
      },
    );
  }
}
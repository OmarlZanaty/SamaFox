import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = seat.avatarUrl;
    final username = (seat.username?.trim().isNotEmpty == true) ? seat.username! : 'User';
    final isMuted = seat.isMuted;
    final locked = isSeatLocked;

    const outerSize = 70.0;     // Frame diameter
    const innerAvatar = 58.0;   // Avatar diameter inside the frame

    print("🪑 seat ${seat.seatNumber} frame = ${seat.avatarFrameUrl}");

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: SizedBox(
          width: outerSize,
          height: outerSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FramedAvatar(
                size: outerSize,
                avatarSize: innerAvatar,
                imageUrl: imageUrl,
                fallbackText: username,
                frame: (seat.avatarFrameUrl != null && seat.avatarFrameUrl!.isNotEmpty)
                    ? AvatarFrame.fromUrl(seat.avatarFrameUrl!)
                    : null,
                glow: seat.isSpeaking,
              ),
              if (locked)
                const Positioned(
                  top: 10,
                  left: 10,
                  child: Icon(Icons.lock, size: 18, color: Colors.redAccent),
                ),
              Positioned(
                top: 10,
                right: 10,
                child: _roleBadge(),
              ),

              // 🎤 MIC → show ONLY when muted
              if (isMuted)
                Positioned(
                  bottom: 28,
                  left: 18,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mic_off,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                  ),
                ),

              if (seat.relationPartner?.avatarUrl != null &&
                  seat.relationPartner!.avatarUrl!.isNotEmpty)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundImage:
                          NetworkImage(seat.relationPartner!.avatarUrl!),
                    ),
                  ),
                ),

// 🔢 SEAT NUMBER → BELOW SEAT
              Positioned(
                bottom: -16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$seatNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleBadge() {
    if (!isOwnerSeat && !isAdminSeat) return const SizedBox.shrink();

    final isOwner = isOwnerSeat;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isOwner ? Colors.amber : Colors.lightBlueAccent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isOwner ? Colors.amber : Colors.lightBlueAccent).withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        isOwner ? Icons.workspace_premium : Icons.verified,
        size: 14,
        color: Colors.black,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // For a consistent seat layout (4 columns and adjustable aspect ratio)
        const int crossAxisCount = 4;
        const double childAspectRatio = 0.72;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            shrinkWrap: false,
            itemCount: seatNumbers.length,
            cacheExtent: 400,
            addRepaintBoundaries: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
            ),
            itemBuilder: (_, i) {
              final seatNumber = seatNumbers[i];
              final isLocked = lockedSeats.contains(seatNumber);

              final seat = seats[seatNumber] ?? SeatData.empty(seatNumber);

              final uid = seat.userId;
              final isMine = uid != null && uid == myUserId;

              final isOwnerSeat = uid != null && uid == ownerId;
              final isAdminSeat = uid != null && adminIds.contains(uid) && !isOwnerSeat;

              final seatKey = seatKeys.putIfAbsent(seatNumber, () => GlobalKey());

              return Container(
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
          ),
        );
      },
    );
  }
}

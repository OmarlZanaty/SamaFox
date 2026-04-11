import 'package:flutter/material.dart';
import '../../services/socket_service.dart';
import 'seat_card.dart';

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

  /// ✅ NEW: seat keys for animation system
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
    required this.seatKeys, // ✅ NEW
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final safeCount = seatCount.clamp(1, 24);
    final seatNumbers = List<int>.generate(safeCount, (i) => i + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        // Keep room seats at 5 columns per row.
        const int crossAxisCount = 5;

        // 👇 adjust this to make seats look good
        double childAspectRatio = 0.72;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: GridView.builder(
              physics: const BouncingScrollPhysics(), // or AlwaysScrollableScrollPhysics()
              shrinkWrap: false,
            itemCount: seatNumbers.length,
            cacheExtent: 400,
            addRepaintBoundaries: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
              }
          ),
        );
      },
    );
  }
}

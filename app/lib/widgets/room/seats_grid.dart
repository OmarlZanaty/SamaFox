import 'package:flutter/material.dart';
import '../../services/socket_service.dart';
import 'seat_card.dart';

/// The mic grid.
///
/// 2026-08-23 — this used to be a scrolling `GridView` pinned to 5 columns with
/// a fixed 62px seat, so a room with 20–30 mics ran off the bottom and the user
/// had to drag to see the rest. The client's rule is that **every** occupant
/// must be visible at once inside the top half of the screen, whatever the seat
/// count: *"لما اكبر عدد المايكات تكون محكومه في نصف الشاشه ... لازم المستخدم
/// يكون شايف كل اللي علي المايك قدامه بدون سحب"*.
///
/// So the layout is solved instead of assumed: for the box it is given, it
/// picks the column count that lets the seats be as large as possible while
/// still fitting in full, and shrinks the seats themselves as the count grows.
/// Nothing scrolls.
class SeatsGrid extends StatelessWidget {
  final Map<int, SeatData> seats;
  final int seatCount;

  final int ownerId;
  final List<int> adminIds;
  final Set<int> lockedSeats;
  final Set<int> mutedSeats; // #11: admin-muted seat numbers

  final bool scrollable;
  final int? myUserId;
  final bool isAdmin;
  final void Function(int seatNumber, SeatData seat) onSeatTap;

  /// ✅ NEW: seat keys for animation system
  final Map<int, GlobalKey> seatKeys;

  /// userId -> coins received in this room (last 24h)
  final Map<int, int> seatEarnings;

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
    this.mutedSeats = const {},
    this.seatEarnings = const {},
    this.scrollable = false,
  });

  /// Rooms can be configured up to 30 mics.
  static const int _maxSeats = 30;

  /// Column counts worth trying. Fewer than 4 wastes width on phones; more
  /// than 8 makes the avatars too small to recognise.
  static const List<int> _columnChoices = [4, 5, 6, 7, 8];

  /// Name (+ optional coins line) drawn under each avatar.
  static const double _labelHeight = 26;
  static const double _spacing = 8;

  /// Nobody needs a 120px seat in a two-person room.
  static const double _maxSeatSize = 68;
  static const double _minSeatSize = 26;

  /// The column count that makes the seats biggest while still fitting every
  /// seat inside [box]. Returns the chosen columns and the seat diameter.
  static ({int columns, double seatSize}) _solve(Size box, int count) {
    int bestColumns = _columnChoices.first;
    double bestSize = 0;

    for (final columns in _columnChoices) {
      if (columns > count && bestSize > 0) break; // more columns than seats
      final rows = (count / columns).ceil();
      final tileW = (box.width - _spacing * (columns - 1)) / columns;
      final tileH = (box.height - _spacing * (rows - 1)) / rows;
      // A tile holds the avatar plus its label, so the avatar is the smaller
      // of "as wide as the tile" and "as tall as the tile minus the label".
      final size = (tileW < tileH - _labelHeight ? tileW : tileH - _labelHeight)
          .clamp(0.0, _maxSeatSize)
          .toDouble();
      if (size > bestSize) {
        bestSize = size;
        bestColumns = columns;
      }
    }

    // A room crammed past what the box can honestly hold still renders — the
    // seats just reach their floor size. This is the only case where the grid
    // can exceed its box, and it is preferable to invisible occupants.
    return (columns: bestColumns, seatSize: bestSize.clamp(_minSeatSize, _maxSeatSize).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final safeCount = seatCount.clamp(1, _maxSeats);
    final seatNumbers = List<int>.generate(safeCount, (i) => i + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(
          constraints.maxWidth,
          constraints.hasBoundedHeight
              ? constraints.maxHeight - MediaQuery.of(context).padding.bottom
              : MediaQuery.of(context).size.height * 0.5,
        );
        final solved = _solve(box, safeCount);
        final rows = (safeCount / solved.columns).ceil();

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int row = 0; row < rows; row++)
                Padding(
                  padding: EdgeInsets.only(bottom: row == rows - 1 ? 0 : _spacing),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int col = 0; col < solved.columns; col++)
                        if (row * solved.columns + col < seatNumbers.length)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _spacing / 2),
                            child: _seat(
                              seatNumbers[row * solved.columns + col],
                              solved.seatSize,
                            ),
                          ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _seat(int seatNumber, double seatSize) {
    final isLocked = lockedSeats.contains(seatNumber);
    final seat = seats[seatNumber] ?? SeatData.empty(seatNumber);

    final uid = seat.userId;
    final isMine = uid != null && uid == myUserId;
    final isOwnerSeat = uid != null && uid == ownerId;
    final isAdminSeat = uid != null && adminIds.contains(uid) && !isOwnerSeat;

    final seatKey = seatKeys.putIfAbsent(seatNumber, () => GlobalKey());

    return KeyedSubtree(
      key: seatKey,
      child: SeatCard(
        seatNumber: seatNumber,
        seat: seat,
        seatSize: seatSize,
        isMine: isMine,
        isAdmin: isAdmin,
        isSeatLocked: isLocked,
        isSeatMuted: mutedSeats.contains(seatNumber),
        isOwnerSeat: isOwnerSeat,
        isAdminSeat: isAdminSeat,
        coins24h: uid != null ? (seatEarnings[uid] ?? 0) : 0,
        onTap: () => onSeatTap(seatNumber, seat),
      ),
    );
  }
}

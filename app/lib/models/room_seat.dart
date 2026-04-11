class RoomSeat {
  final int seatNumber;
  final int? userId;
  final String? username;
  final String? avatarUrl;
  final int level;
  final bool isMuted;
  final bool isLocked;

  RoomSeat({
    required this.seatNumber,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.level,
    required this.isMuted,
    required this.isLocked,
  });

  factory RoomSeat.empty(int i) => RoomSeat(
    seatNumber: i,
    userId: null,
    username: null,
    avatarUrl: null,
    level: 0,
    isMuted: true,
    isLocked: false,
  );

  RoomSeat copyWith({
    int? userId,
    String? username,
    String? avatarUrl,
    int? level,
    bool? isMuted,
    bool? isLocked,
  }) {
    return RoomSeat(
      seatNumber: seatNumber,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      isMuted: isMuted ?? this.isMuted,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

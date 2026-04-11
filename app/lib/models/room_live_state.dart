import '../services/socket_service.dart';

class RoomLiveState {
  final int roomId;

  /// seatNumber -> SeatData
  final Map<int, SeatData> seats;

  /// mic queue = list of userIds
  final List<int> micQueue;

  /// room chat
  final List<SocketMessage> messages;

  RoomLiveState({
    required this.roomId,
    required this.seats,
    required this.micQueue,
    required this.messages,
  });

  factory RoomLiveState.empty(int roomId, {int maxSeats = 8}) {
    final seats = <int, SeatData>{};
    for (int i = 1; i <= maxSeats; i++) {
      seats[i] = SeatData(
        seatNumber: i,
        userId: null,
        username: null,
        avatarUrl: null,
        level: 0,
        isMuted: true,
        isLocked: false,
      );
    }
    return RoomLiveState(roomId: roomId, seats: seats, micQueue: const [], messages: const []);
  }

  RoomLiveState copyWith({
    Map<int, SeatData>? seats,
    List<int>? micQueue,
    List<SocketMessage>? messages,
  }) {
    return RoomLiveState(
      roomId: roomId,
      seats: seats ?? this.seats,
      micQueue: micQueue ?? this.micQueue,
      messages: messages ?? this.messages,
    );
  }
}

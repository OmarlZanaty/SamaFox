import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../repositories/room_repository.dart';
import '../utils/logger.dart';

final roomRepositoryProvider = Provider((ref) => RoomRepository());

final roomsProvider =
StateNotifierProvider<RoomsNotifier, RoomsState>((ref) {
  return RoomsNotifier(ref.read(roomRepositoryProvider));
});

class RoomsState {
  final List<Room> rooms;
  final bool isLoading;
  final String? error;
  final Room? selectedRoom;
  Room? findById(int id) {
    try {
      return rooms.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
  RoomsState({
    this.rooms = const [],
    this.isLoading = false,
    this.error,
    this.selectedRoom,
  });

  RoomsState copyWith({
    List<Room>? rooms,
    bool? isLoading,
    String? error,
    Room? selectedRoom,
  }) {
    return RoomsState(
      rooms: rooms ?? this.rooms,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      selectedRoom: selectedRoom ?? this.selectedRoom,
    );
  }
}

class RoomsNotifier extends StateNotifier<RoomsState> {
  final RoomRepository _repository;

  RoomsNotifier(this._repository) : super(RoomsState()) {
    loadRooms();
  }

  // ===============================
  // LOAD ROOMS
  // ===============================

  Future<void> loadRooms({int page = 1, int limit = 20}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      AppLogger.info('Loading rooms...');
      final result = await _repository.getRooms(page: page, limit: limit);

      if (result.isSuccess && result.data != null) {

        AppLogger.info(
            'Rooms loaded successfully: ${result.data!.length} rooms');
        state = state.copyWith(
          isLoading: false,
          rooms: result.data!,
        );
      } else {
        AppLogger.error('Failed to load rooms: ${result.error}');
        state = state.copyWith(
          isLoading: false,
          error: result.error,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Exception loading rooms: $e');
      AppLogger.error('Stack trace: $stackTrace');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load rooms: ${e.toString()}',
      );
    }
  }

  // ===============================
  // LOAD SINGLE ROOM
  // ===============================

  Future<void> loadRoomById(int roomId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.getRoomById(roomId);

      if (result.isSuccess && result.data != null) {
        state = state.copyWith(
          isLoading: false,
          selectedRoom: result.data!,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result.error,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Exception loading room: $e');
      AppLogger.error('Stack trace: $stackTrace');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  // ===============================
  // CREATE ROOM  ✅ RESTORED
  // ===============================

  Future<bool> createRoom(CreateRoomRequest request, int userId) async {
    // ✅ CHECK FIRST (IMPORTANT)
    final alreadyHasRoom = state.rooms.any(
          (room) => room.ownerId == userId || room.owner?.id == userId,
    );

    if (alreadyHasRoom) {
      state = state.copyWith(
        error: 'لا يمكنك إنشاء أكثر من غرفة واحدة',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _repository.createRoom(request);

      if (result.isSuccess) {
        await loadRooms();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result.error,
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  // ===============================
  // JOIN / LEAVE ROOM (FIRE & FORGET)
  // ===============================

  Future<void> joinRoom(int roomId, int userId) async {
    /*try {
      await _repository.joinRoom(roomId, userId);
    } catch (e) {
      AppLogger.error('Failed to join room: $e');
    }*/
  }

  Future<void> leaveRoom(int roomId, int userId) async {
    try {
      await _repository.leaveRoom(roomId, userId);
    } catch (e) {
      AppLogger.error('Failed to leave room: $e');
    }
  }
}

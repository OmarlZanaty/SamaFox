import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../repositories/room_repository.dart';

/// Room Admin State
class RoomAdminState {
  final Room? room;
  final bool isLoading;
  final String? error;
  final List<RoomMember> admins;
  final List<User> bannedUsers;

  const RoomAdminState({
    this.room,
    this.isLoading = false,
    this.error,
    this.admins = const [],
    this.bannedUsers = const [],
  });

  RoomAdminState copyWith({
    Room? room,
    bool? isLoading,
    String? error,
    List<RoomMember>? admins,
    List<User>? bannedUsers,
  }) {
    return RoomAdminState(
      room: room ?? this.room,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      admins: admins ?? this.admins,
      bannedUsers: bannedUsers ?? this.bannedUsers,
    );
  }
}

/// Room Admin Provider
class RoomAdminNotifier extends StateNotifier<RoomAdminState> {
  final RoomRepository _roomRepository;

  RoomAdminNotifier(this._roomRepository) : super(const RoomAdminState());

  /// Initialize with room data
  void initializeRoom(Room room) {
    state = state.copyWith(room: room);
    _loadAdmins();
  }

  /// Load list of admins for the room
  void _loadAdmins() {
    if (state.room == null) return;

    final admins = state.room!.roomMembers
        .where((member) =>
    member.role == 'admin' || member.role == 'owner')
        .toList();

    state = state.copyWith(admins: admins);
  }

  /// Update room lock status
  Future<void> toggleRoomLock() async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      final newLockState = !state.room!.isRoomLocked;

      await _roomRepository.updateRoom(
        state.room!.id,
        UpdateRoomRequest(isPublic: !newLockState),
      );

      // Update local state
      final updatedRoom = Room(
        id: state.room!.id,
        name: state.room!.name,
        roomNumber: state.room!.roomNumber,
        description: state.room!.description,
        coverImageUrl: state.room!.coverImageUrl,
        backgroundImageUrl: state.room!.backgroundImageUrl,
        isPublic: !newLockState,
        currentMembers: state.room!.currentMembers,
        maxMembers: state.room!.maxMembers,
        maxSeats: state.room!.maxSeats,
        type: state.room!.type,
        ownerId: state.room!.ownerId,
        owner: state.room!.owner,
        members: state.room!.members,
        membersCount: state.room!.membersCount,
        createdAt: state.room!.createdAt,
        updatedAt: state.room!.updatedAt,
        isLocked: newLockState,
        backgroundMusicUrl: state.room!.backgroundMusicUrl,
        muteGiftSounds: state.room!.muteGiftSounds,
        muteEntranceSounds: state.room!.muteEntranceSounds,
      );

      state = state.copyWith(room: updatedRoom, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update room lock status: $e',
      );
    }
  }

  /// Update mic count (max seats)
  Future<void> updateMicCount(int count) async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      await _roomRepository.updateRoom(
        state.room!.id,
        UpdateRoomRequest(maxSeats: count),
      );

      // Update local state
      final updatedRoom = Room(
        id: state.room!.id,
        name: state.room!.name,
        roomNumber: state.room!.roomNumber,
        description: state.room!.description,
        coverImageUrl: state.room!.coverImageUrl,
        backgroundImageUrl: state.room!.backgroundImageUrl,
        isPublic: state.room!.isPublic,
        currentMembers: state.room!.currentMembers,
        maxMembers: state.room!.maxMembers,
        maxSeats: count,
        type: state.room!.type,
        ownerId: state.room!.ownerId,
        owner: state.room!.owner,
        members: state.room!.members,
        membersCount: state.room!.membersCount,
        createdAt: state.room!.createdAt,
        updatedAt: state.room!.updatedAt,
        isLocked: state.room!.isLocked,
        backgroundMusicUrl: state.room!.backgroundMusicUrl,
        muteGiftSounds: state.room!.muteGiftSounds,
        muteEntranceSounds: state.room!.muteEntranceSounds,
      );

      state = state.copyWith(room: updatedRoom, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update mic count: $e',
      );
    }
  }

  /// Add admin to room
  Future<void> addAdmin(int userId) async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      // Call API to add admin
      // await _roomRepository.addRoomAdmin(state.room!.id, userId);

      // Refresh room data to get updated members list
      // For now, just update loading state
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to add admin: $e',
      );
    }
  }

  /// Remove admin from room
  Future<void> removeAdmin(int userId) async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      // Call API to remove admin
      // await _roomRepository.removeRoomAdmin(state.room!.id, userId);

      // Refresh room data to get updated members list
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to remove admin: $e',
      );
    }
  }

  /// Ban user from room
  Future<void> banUser(int userId, String? reason) async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      // Call API to ban user
      // await _roomRepository.banUser(state.room!.id, userId, reason);

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to ban user: $e',
      );
    }
  }

  /// Unban user from room
  Future<void> unbanUser(int userId) async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      // Call API to unban user
      // await _roomRepository.unbanUser(state.room!.id, userId);

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to unban user: $e',
      );
    }
  }

  /// Mute/unmute user
  Future<void> toggleMute(int userId, bool mute) async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      // Call API to mute/unmute user
      // await _roomRepository.muteUser(state.room!.id, userId, mute);

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to ${mute ? "mute" : "unmute"} user: $e',
      );
    }
  }

  /// Update sound settings
  Future<void> updateSoundSettings({
    bool? muteGiftSounds,
    bool? muteEntranceSounds,
  }) async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      // Call API to update sound settings
      // For now, just update local state
      final updatedRoom = Room(
        id: state.room!.id,
        name: state.room!.name,
        roomNumber: state.room!.roomNumber,
        description: state.room!.description,
        coverImageUrl: state.room!.coverImageUrl,
        backgroundImageUrl: state.room!.backgroundImageUrl,
        isPublic: state.room!.isPublic,
        currentMembers: state.room!.currentMembers,
        maxMembers: state.room!.maxMembers,
        maxSeats: state.room!.maxSeats,
        type: state.room!.type,
        ownerId: state.room!.ownerId,
        owner: state.room!.owner,
        members: state.room!.members,
        membersCount: state.room!.membersCount,
        createdAt: state.room!.createdAt,
        updatedAt: state.room!.updatedAt,
        isLocked: state.room!.isLocked,
        backgroundMusicUrl: state.room!.backgroundMusicUrl,
        muteGiftSounds: muteGiftSounds ?? state.room!.muteGiftSounds,
        muteEntranceSounds:
        muteEntranceSounds ?? state.room!.muteEntranceSounds,
      );

      state = state.copyWith(room: updatedRoom, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update sound settings: $e',
      );
    }
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Refresh room data
  Future<void> refreshRoom() async {
    if (state.room == null) return;

    state = state.copyWith(isLoading: true);

    try {
      final result = await _roomRepository.getRoomById(state.room!.id);
      if (result.isSuccess) {
        state = state.copyWith(room: result.data, isLoading: false);
        _loadAdmins();
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to refresh room data: ${result.error}',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to refresh room data: $e',
      );
    }
  }
}

/// Provider for Room Admin functionality
final roomAdminProvider =
StateNotifierProvider<RoomAdminNotifier, RoomAdminState>((ref) {
  final roomRepository = RoomRepository();
  return RoomAdminNotifier(roomRepository);
});

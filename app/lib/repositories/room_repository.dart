import '../services/api_service.dart';
import '../services/dio_client.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../models/api_response.dart';
import '../utils/result.dart';

class RoomRepository {
  late final ApiService _apiService;

  RoomRepository() {
    _apiService = ApiService(DioClient.dio);
  }

  Future<Result<List<Room>>> getRooms({int page = 1, int limit = 20}) async {
    try {
      final response = await _apiService.getRooms(page: page, limit: limit);
      return Result.success(response.rooms);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<Room>> getRoomById(int roomId) async {
    try {
      final room = await _apiService.getRoomById(roomId);
      return Result.success(room);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<void>> createRoom(CreateRoomRequest request) async {
    try {
      final room = await _apiService.createRoom(request);
      return Result.success(room);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<void>> updateRoom(
      int roomId,
      UpdateRoomRequest request,
      ) async {
    try {
      await _apiService.updateRoom(roomId, request);
      return Result.success(null);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<void>> deleteRoom(int roomId) async {
    try {
      await _apiService.deleteRoom(roomId);
      return Result.success(null);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  /// ✅ FIXED SIGNATURE
  Future<void> joinRoom(int roomId, int userId) async {
    return;
  }

  Future<Result<void>> leaveRoom(int roomId, int userId) async {
    try {
      await _apiService.leaveRoom(roomId, {'userId': userId});
      return Result.success(null);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<List<RoomMessage>>> getRoomMessages(
      int roomId, {
        int limit = 50,
        int offset = 0,
      }) async {
    try {
      final response =
      await _apiService.getRoomMessages(roomId, limit: limit, offset: offset);
      return Result.success(response);
    } catch (e) {
      return Result.error(e.toString());
    }
  }
}

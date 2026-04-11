import '../services/api_service.dart';
import '../services/dio_client.dart';
import '../models/user.dart';
import '../utils/result.dart';

class UserRepository {
  late final ApiService _apiService;

  UserRepository() {
    _apiService = ApiService(DioClient.dio);
  }

  Future<Result<User>> getUserProfile(int userId) async {
    try {
      final user = await _apiService.getUserProfile(userId);
      return Result.success(user);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<User>> getCurrentUser() async {
    try {
      final user = await _apiService.getCurrentUser();
      return Result.success(user);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<User>> updateProfile(Map<String, dynamic> data) async {
    try {
      final user = await _apiService.updateProfile(data);
      return Result.success(user);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<void>> followUser(int userId) async {
    try {
      await _apiService.followUser(userId);
      return Result.success(null);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<void>> unfollowUser(int userId) async {
    try {
      await _apiService.unfollowUser(userId);
      return Result.success(null);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<List<User>>> getFollowers(int userId) async {
    try {
      final response = await _apiService.getFollowers(userId);
      return Result.success(response.users);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<List<User>>> getFollowing(int userId) async {
    try {
      final response = await _apiService.getFollowing(userId);
      return Result.success(response.users);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<List<User>>> searchUsers(String query) async {
    try {
      final response = await _apiService.searchUsers(query);
      return Result.success(response.users);
    } catch (e) {
      return Result.error(e.toString());
    }
  }
}

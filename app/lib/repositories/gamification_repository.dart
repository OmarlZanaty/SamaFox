import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/achievement.dart';
import '../models/quest.dart';

class GamificationRepository {
  final Dio _dio;

  GamificationRepository(this._dio);

  // Get access token from storage
  Future<String?> _getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.accessTokenKey);
  }

  // Achievements
  Future<List<Achievement>> getAllAchievements() async {
    try {
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}gamification/achievements',
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data as List<dynamic>;
        return data.map((json) => Achievement.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load achievements');
      }
    } catch (e) {
      debugPrint('Error fetching achievements: $e');
      rethrow;
    }
  }

  Future<List<UserAchievement>> getUserAchievements(int userId) async {
    try {
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}gamification/achievements/user/$userId',
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data as List<dynamic>;
        return data.map((json) => UserAchievement.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load user achievements');
      }
    } catch (e) {
      debugPrint('Error fetching user achievements: $e');
      rethrow;
    }
  }

  // Quests
  Future<List<QuestWithProgress>> getDailyQuests() async {
    try {
      final token = await _getAccessToken();
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}gamification/quests/daily',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data as List<dynamic>;
        return data.map((json) => QuestWithProgress.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load daily quests');
      }
    } catch (e) {
      debugPrint('Error fetching daily quests: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> completeQuest(String questId) async {
    try {
      final token = await _getAccessToken();
      final response = await _dio.post(
        '${AppConfig.apiBaseUrl}gamification/quests/$questId/complete',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to complete quest');
      }
    } catch (e) {
      debugPrint('Error completing quest: $e');
      rethrow;
    }
  }

  // Room Level
  Future<Map<String, dynamic>> getRoomLevel(int roomId) async {
    try {
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}gamification/rooms/$roomId/level',
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load room level');
      }
    } catch (e) {
      debugPrint('Error fetching room level: $e');
      rethrow;
    }
  }

  // Streak
  Future<Map<String, dynamic>> getStreakInfo() async {
    try {
      final token = await _getAccessToken();
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}gamification/streak',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load streak info');
      }
    } catch (e) {
      debugPrint('Error fetching streak info: $e');
      rethrow;
    }
  }
}

import 'package:dio/dio.dart';
import 'dio_client.dart';

class FollowService {
  FollowService._();

  static Dio get _dio => DioClient.dio;

  static Future<String> getFollowStatus(int userId) async {
    final res = await _dio.get('/follow/status/$userId');
    final data = (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>?;
    return (data?['status'] as String?) ?? 'none';
  }

  static Future<void> sendFollowRequest(int userId) async {
    await _dio.post('/follow/$userId');
  }

  /// #25: users the current account follows, each with liveRoomId if hosting.
  static Future<List<Map<String, dynamic>>> getFollowing() async {
    final res = await _dio.get('/follow/following');
    final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> unfollow(int userId) async {
    await _dio.delete('/follow/$userId');
  }

  static Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final res = await _dio.get('/follow/requests');
    final list = ((res.data as Map<String, dynamic>)['data'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> respondToFollow(int followId, String action) async {
    await _dio.patch('/follow/$followId/respond', data: {'action': action});
  }
}

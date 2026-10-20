import 'package:dio/dio.dart';
import 'dio_client.dart';

class NotificationService {
  NotificationService._();

  static Dio get _dio => DioClient.dio;

  static Future<Map<String, dynamic>> getNotifications({int page = 1, int limit = 30, String? category}) async {
    final res = await _dio.get('/notifications', queryParameters: {
      'page': page,
      'limit': limit,
      if (category != null) 'category': category,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> markRead(int notificationId) async {
    await _dio.patch('/notifications/$notificationId/read');
  }

  static Future<void> markAllRead({String? category}) async {
    await _dio.patch('/notifications/read-all', queryParameters: {if (category != null) 'category': category});
  }
}

import 'package:dio/dio.dart';
import 'dio_client.dart';

class NotificationService {
  NotificationService._();

  static Dio get _dio => DioClient.dio;

  static Future<Map<String, dynamic>> getNotifications({int page = 1, int limit = 30}) async {
    final res = await _dio.get('/notifications', queryParameters: {'page': page, 'limit': limit});
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> markRead(int notificationId) async {
    await _dio.patch('/notifications/$notificationId/read');
  }

  static Future<void> markAllRead() async {
    await _dio.patch('/notifications/read-all');
  }
}

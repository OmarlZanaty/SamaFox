import 'package:dio/dio.dart';
import 'dio_client.dart';

class RelationService {
  RelationService._();

  static Dio get _dio => DioClient.dio;

  static Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final res = await _dio.get('/relations/requests');
    final list = ((res.data as Map<String, dynamic>)['data'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> respondToRelation(int relationId, String action) async {
    await _dio.patch('/relations/$relationId/respond', data: {'action': action});
  }
}

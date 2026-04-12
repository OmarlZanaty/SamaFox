import 'package:dio/dio.dart';
import 'dio_client.dart';

class RelationService {
  RelationService._();

  static Dio get _dio => DioClient.dio;

  static Future<void> respondToRelation(int relationId, String action) async {
    await _dio.patch('/relations/$relationId/respond', data: {'action': action});
  }
}

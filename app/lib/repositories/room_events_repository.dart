import '../services/dio_client.dart';

class RoomEventsRepository {
  static Future<List<Map<String, dynamic>>> claimPk(String pkId) async {
    final response = await DioClient.dio.post('/pk/$pkId/claim');
    final data = response.data['data'] as Map;
    return (data['rewards'] as List)
        .map((reward) => Map<String, dynamic>.from(reward as Map))
        .toList();
  }
}

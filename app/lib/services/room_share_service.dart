import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'dio_client.dart';
import '../l10n/tr.dart';

class RoomShareService {
  static final Map<int, String> joinTokens = {};

  static Future<Map<String, dynamic>> create(int roomId,
      {List<int>? recipients, String? requestId}) async {
    final response = await DioClient.dio.post('rooms/$roomId/share',
      data: {'channel': recipients == null ? 'external' : 'dm',
        if (recipients != null) 'recipientIds': recipients},
      options: Options(headers: {'Idempotency-Key': requestId ?? const Uuid().v4()}));
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<int> resolve(String token) async {
    final response = await DioClient.dio.get('rooms/share/${Uri.encodeComponent(token)}');
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['ok'] != true) throw Exception(data['message']);
    final roomId = (data['roomId'] as num).toInt();
    joinTokens[roomId] = token;
    return roomId;
  }

  static String errorMessage(Object error) {
    if (error is DioException && error.response?.data is Map) {
      return (error.response!.data as Map)['message']?.toString() ?? tr('تعذر فتح الغرفة', 'Could not open the room');
    }
    return tr('تعذر الاتصال، حاول مرة أخرى', 'Connection failed, try again');
  }

  static String? tokenFromUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host != 'samafox.almobarmg.com' ||
        uri.pathSegments.length != 2 || uri.pathSegments.first != 'room') return null;
    return validToken(uri.pathSegments.last) ? uri.pathSegments.last : null;
  }

  static bool validToken(String token) => RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(token);
}

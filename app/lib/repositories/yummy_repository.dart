import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../services/dio_client.dart';
import '../screens/games/yummy_engine.dart';

class YummyRepository {
  final Dio? _injectedDio;
  YummyRepository({Dio? dio}) : _injectedDio = dio;
  Dio get _dio => _injectedDio ?? DioClient.dio;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? data,
    String? requestId,
  }) async {
    try {
      final response = data == null
          ? await _dio.get<Map<String, dynamic>>('games/yummy/$path')
          : await _dio.post<Map<String, dynamic>>(
              'games/yummy/$path',
              data: data,
              options: Options(
                headers: {
                  if (requestId != null) 'Idempotency-Key': requestId,
                },
              ),
            );
      final body = response.data ?? {};
      if (body['success'] != true) {
        throw YummyException(body['code']?.toString() ?? 'FAILED');
      }
      return body;
    } on DioException catch (error) {
      final body = error.response?.data;
      throw YummyException(
        body is Map ? body['code']?.toString() ?? 'FAILED' : 'NETWORK',
      );
    }
  }

  Future<Map<String, dynamic>> fetchState() => request('state');
  Future<List<YummyRound>> history() async => ((await request(
        'history',
      ))['history'] as List)
          .map(
            (row) => YummyRound.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
  Future<YummyRound> spin(
    int betPerLine,
    int activeLines, {
    String? requestId,
  }) async =>
      YummyRound.fromJson(
        await request(
          'spin',
          data: {'betPerLine': betPerLine, 'activeLines': activeLines},
          requestId: requestId ?? const Uuid().v4(),
        ),
      );

  /// Latest big wins announced to everyone (newest first).
  Future<List<Map<String, dynamic>>> feed() async =>
      ((await request('feed'))['wins'] as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
  Future<Map<String, dynamic>> leaderboard() => request('leaderboard');
  Future<Map<String, dynamic>> missions() => request('missions');
  Future<Map<String, dynamic>> claimMission(String key) =>
      request('missions/$key/claim', data: const {});
}

class YummyException implements Exception {
  final String code;
  const YummyException(this.code);
}

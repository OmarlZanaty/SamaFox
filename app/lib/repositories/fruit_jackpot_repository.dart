import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../services/dio_client.dart';
import '../screens/games/fruit_jackpot_engine.dart';

class FruitJackpotRepository {
  int? lastPingMs;
  final Dio? _injectedDio;
  FruitJackpotRepository({Dio? dio}) : _injectedDio = dio;
  Dio get _dio => _injectedDio ?? DioClient.dio;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? data,
    String? requestId,
  }) async {
    final clock = Stopwatch()..start();
    try {
      final response = data == null
          ? await _dio.get<Map<String, dynamic>>('games/fruit-jackpot/$path')
          : await _dio.post<Map<String, dynamic>>(
              'games/fruit-jackpot/$path',
              data: data,
              options: Options(
                headers: {if (requestId != null) 'Idempotency-Key': requestId},
              ),
            );
      lastPingMs = clock.elapsedMilliseconds;
      final body = response.data ?? {};
      if (body['success'] != true) {
        throw FruitJackpotException(body['code']?.toString() ?? 'FAILED');
      }
      return body;
    } on DioException catch (error) {
      lastPingMs = clock.elapsedMilliseconds;
      final body = error.response?.data;
      throw FruitJackpotException(
        body is Map ? body['code']?.toString() ?? 'FAILED' : 'NETWORK',
      );
    }
  }

  Future<Map<String, dynamic>> fetchState() => request('state');
  Future<List<FruitJackpotRound>> history() async =>
      ((await request('history'))['history'] as List)
          .map(
            (row) => FruitJackpotRound.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
  Future<FruitJackpotRound> spin(
    int betPerLine,
    int activeLines, {
    String? requestId,
  }) async => FruitJackpotRound.fromJson(
    await request(
      'spin',
      data: {'betPerLine': betPerLine, 'activeLines': activeLines},
      requestId: requestId ?? const Uuid().v4(),
    ),
  );
}

class FruitJackpotException implements Exception {
  final String code;
  const FruitJackpotException(this.code);
}

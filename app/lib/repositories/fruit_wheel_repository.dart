import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../services/dio_client.dart';
import '../screens/games/fruit_wheel_engine.dart';

class FruitWheelRepository {
  final Dio? _injectedDio;
  FruitWheelRepository({Dio? dio}) : _injectedDio = dio;
  Dio get _dio => _injectedDio ?? DioClient.dio;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? data,
    String? requestId,
  }) async {
    try {
      final response = data == null
          ? await _dio.get<Map<String, dynamic>>('games/fruitwheel/$path')
          : await _dio.post<Map<String, dynamic>>(
              'games/fruitwheel/$path',
              data: data,
              options: Options(
                headers: {
                  if (requestId != null) 'Idempotency-Key': requestId,
                },
              ),
            );
      final body = response.data ?? {};
      if (body['success'] != true) {
        throw FruitWheelException(body['code']?.toString() ?? 'FAILED');
      }
      return body;
    } on DioException catch (error) {
      final body = error.response?.data;
      throw FruitWheelException(
        body is Map ? body['code']?.toString() ?? 'FAILED' : 'NETWORK',
      );
    }
  }

  Future<Map<String, dynamic>> fetchState() => request('state');
  Future<FruitRound> spin(FruitBets bets, {String? requestId}) async =>
      FruitRound.fromJson(
        await request(
          'spin',
          data: {'bets': bets.json},
          requestId: requestId ?? const Uuid().v4(),
        ),
      );
  Future<Map<String, dynamic>> leaderboard() => request('leaderboard');
  Future<Map<String, dynamic>> today() => request('today');
  Future<Map<String, dynamic>> fairness() => request('fair');
  Future<Map<String, dynamic>> rotateSeed() =>
      request('seed/rotate', data: const {});
  Future<Map<String, dynamic>> setClientSeed(String seed) =>
      request('seed', data: {'clientSeed': seed});
}

class FruitWheelException implements Exception {
  final String code;
  const FruitWheelException(this.code);
}

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../services/dio_client.dart';

/// REST for الروليت. Chips, undo, clear and repeat move coins, so they go
/// through here; the socket (`roulette_state`) only pushes the shared table.
class RouletteRepository {
  final Dio? _injectedDio;
  RouletteRepository({Dio? dio}) : _injectedDio = dio;
  Dio get _dio => _injectedDio ?? DioClient.dio;

  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic>? data,}) async {
    try {
      final response = data == null
          ? await _dio.get<Map<String, dynamic>>('games/roulette/$path')
          : await _dio.post<Map<String, dynamic>>(
              'games/roulette/$path',
              data: data,
              options: Options(headers: {'Idempotency-Key': const Uuid().v4()}),
            );
      final body = response.data ?? {};
      if (body['success'] != true) {
        throw RouletteException(body['code']?.toString() ?? 'FAILED');
      }
      return body;
    } on DioException catch (error) {
      final body = error.response?.data;
      throw RouletteException(
          body is Map ? body['code']?.toString() ?? 'FAILED' : 'NETWORK',);
    }
  }

  Future<Map<String, dynamic>> fetchState() => request('state');
  Future<Map<String, dynamic>> bet(String key, int amount) =>
      request('bet', data: {'key': key, 'amount': amount});
  Future<Map<String, dynamic>> undo() => request('undo', data: const {});
  Future<Map<String, dynamic>> clear() => request('clear', data: const {});
  Future<Map<String, dynamic>> repeat() => request('repeat', data: const {});
  Future<List<Map<String, dynamic>>> history() async =>
      ((await request('history'))['history'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
  Future<Map<String, dynamic>> ranking() => request('ranking');
}

class RouletteException implements Exception {
  final String code;
  const RouletteException(this.code);
}

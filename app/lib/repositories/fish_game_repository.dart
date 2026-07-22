import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

/// Talks to the real-coin fish-shooter endpoints. Cost per shot and reward
/// per fish are fixed and server-owned (no randomness in the payout amount,
/// only in which fish appears) — see backend/src/controllers/game.controller.ts.
class FishGameRepository {
  FishGameRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  Future<int> shoot(int bet) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/fish/shoot',
        data: {'bet': bet},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw FishGameException(body['message']?.toString() ?? 'فشل إطلاق الطلقة');
      }
      return (body['balance'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw _translateDioError(e, fallback: 'فشل إطلاق الطلقة');
    }
  }

  Future<FishCaptureResult> capture(String speciesKey) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'games/fish/capture',
        data: {'speciesKey': speciesKey},
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw FishGameException(body['message']?.toString() ?? 'فشل تحصيل الجائزة');
      }
      return FishCaptureResult(
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        reward: (body['reward'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _translateDioError(e, fallback: 'فشل تحصيل الجائزة');
    }
  }

  FishGameException _translateDioError(DioException e, {required String fallback}) {
    final data = e.response?.data;
    String? code;
    String? serverMessage;
    if (data is Map) {
      code = data['code']?.toString();
      serverMessage = data['message']?.toString();
    }
    final message = _arabicMessageFor(code) ?? serverMessage ?? fallback;
    return FishGameException(message, code: code);
  }

  String? _arabicMessageFor(String? code) {
    switch (code) {
      case 'INSUFFICIENT_COINS':
        return 'رصيدك لا يكفي';
      default:
        return null;
    }
  }
}

class FishCaptureResult {
  final int balance;
  final int reward;
  const FishCaptureResult({required this.balance, required this.reward});
}

class FishGameException implements Exception {
  final String message;
  final String? code;
  FishGameException(this.message, {this.code});
  @override
  String toString() => 'FishGameException(${code ?? '?'}: $message)';
}

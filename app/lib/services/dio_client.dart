import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/app_config.dart';
import '../utils/storage_service.dart';

class DioClient {
  static Dio? _dio;

  /// Call once at app startup (optional but recommended) to make sure
  /// interceptors are attached before any API calls happen.
  static Dio init() {
    return dio;
  }

  static Dio get dio {
    if (_dio != null) return _dio!;

    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
        receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
        sendTimeout: const Duration(milliseconds: AppConfig.sendTimeout),
        headers: const {
          'Accept': 'application/json',
          // REMOVE Content-Type from here
        },
      ),
    );


    // ✅ Always attach token (fix 401 on sendGift, etc.)
    _dio!.interceptors.add(AuthInterceptor());

    // ✅ Nice logs only in debug
    if (kDebugMode) {
      _dio!.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
          maxWidth: 90,
        ),
      );
    }

    // ✅ Friendly error messages
    _dio!.interceptors.add(ErrorInterceptor());

    return _dio!;
  }
}

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      String? token = await StorageService.getAccessToken();

      token = token?.trim();
      if (token != null && token.isNotEmpty) {
        // ✅ remove accidental quotes if stored like "token"
        token = token.replaceAll('"', '').replaceAll("'", '').trim();

        options.headers['Authorization'] = 'Bearer $token';
      }

      handler.next(options);
    } catch (_) {
      handler.next(options);
    }
  }
}

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String errorMessage = 'An error occurred';

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        errorMessage = 'Connection timeout. Please try again.';
        break;

      case DioExceptionType.badResponse:
        final code = err.response?.statusCode;
        // Prefer backend error message when available
        final serverMsg = _extractServerMessage(err.response?.data);
        errorMessage = serverMsg ?? _handleStatusCode(code);
        break;

      case DioExceptionType.cancel:
        errorMessage = 'Request cancelled';
        break;

      case DioExceptionType.connectionError:
        errorMessage = 'No internet connection';
        break;

      default:
        errorMessage = 'Something went wrong';
    }

    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        error: errorMessage,
        type: err.type,
        response: err.response,
      ),
    );
  }

  String? _extractServerMessage(dynamic data) {
    try {
      if (data is Map) {
        final msg = data['message'] ?? data['error'];
        if (msg != null) return msg.toString();
      }
    } catch (_) {}
    return null;
  }

  String _handleStatusCode(int? statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad request';
      case 401:
        return 'Unauthorized. Please login again.';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not found';
      case 500:
        return 'Internal server error';
      case 503:
        return 'Service unavailable';
      default:
        return 'Error: $statusCode';
    }
  }
}

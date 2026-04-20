import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:samafox/services/socket_service.dart';

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
  bool _isRefreshing = false;
  final List<RequestOptions> _pendingRequests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    String? token = await StorageService.getAccessToken();
    token = token?.trim().replaceAll('"', '').replaceAll("'", '');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Don't retry the refresh endpoint itself
    if (err.requestOptions.path.contains('/auth/refresh')) {
      handler.next(err);
      return;
    }

    if (_isRefreshing) {
      _pendingRequests.add(err.requestOptions);
      return;
    }

    _isRefreshing = true;
    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null) {
        handler.next(err);
        return;
      }

      final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final response = await refreshDio.post('/auth/refresh',
          data: {'refreshToken': refreshToken});

      final newAccessToken = response.data['accessToken'] as String?;
      final newRefreshToken = response.data['refreshToken'] as String?;

      if (newAccessToken == null) {
        handler.next(err);
        return;
      }

      await StorageService.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken ?? refreshToken,
      );
      SocketService().updateToken(newAccessToken);

      // Retry original request
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      final retryResponse = await DioClient.dio.fetch(retryOptions);
      handler.resolve(retryResponse);

      // Retry any queued requests
      for (final pending in _pendingRequests) {
        pending.headers['Authorization'] = 'Bearer $newAccessToken';
        DioClient.dio.fetch(pending);
      }
      _pendingRequests.clear();
    } catch (e) {
      // Refresh failed — force logout
      await StorageService.clearTokens();
      SocketService().disconnect();
      handler.next(err);
    } finally {
      _isRefreshing = false;
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

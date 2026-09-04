import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:samafox/services/socket_service.dart';

import '../config/app_config.dart';
import '../utils/storage_service.dart';
import 'token_refresher.dart';

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
  // Each pending 401 gets its own completer so it can be individually resolved.
  final List<Completer<String>> _pendingCompleters = [];

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

    // Don't retry the refresh endpoint itself.
    if (err.requestOptions.path.contains('/auth/refresh')) {
      handler.next(err);
      return;
    }

    if (_isRefreshing) {
      // Park this request until the in-progress refresh completes.
      final completer = Completer<String>();
      _pendingCompleters.add(completer);
      try {
        final newToken = await completer.future;
        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newToken';
        handler.resolve(await DioClient.dio.fetch(retryOptions));
      } catch (_) {
        handler.next(err);
      }
      return;
    }

    _isRefreshing = true;
    try {
      // Shared with the socket's auth-failure handler so the two never rotate
      // the refresh token concurrently — see TokenRefresher.
      final result = await TokenRefresher.refresh();

      if (!result.ok) {
        _rejectAllPending();
        if (result.sessionEnded) {
          // Refresh was refused outright — force logout.
          await StorageService.clearTokens();
          SocketService().disconnect();
        }
        handler.next(err);
        return;
      }

      final newAccessToken = result.accessToken!;
      SocketService().updateToken(newAccessToken);

      // Unblock all parked requests with the new token.
      _resolveAllPending(newAccessToken);

      // Retry the original request that triggered the refresh.
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      handler.resolve(await DioClient.dio.fetch(retryOptions));
    } catch (_) {
      _rejectAllPending();
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }

  void _resolveAllPending(String token) {
    for (final c in _pendingCompleters) {
      if (!c.isCompleted) c.complete(token);
    }
    _pendingCompleters.clear();
  }

  void _rejectAllPending() {
    for (final c in _pendingCompleters) {
      if (!c.isCompleted) c.completeError('Token refresh failed');
    }
    _pendingCompleters.clear();
  }
}

class ErrorInterceptor extends Interceptor {
  /// Called when the API reports the account is banned. Wired to the auth
  /// notifier at startup; kept as a hook so this file stays free of Riverpod.
  static void Function(String message)? onBanned;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String errorMessage = 'An error occurred';

    // A banned account gets 403 + code BANNED from every authenticated
    // endpoint, including /auth/refresh. End the session rather than let the
    // app keep retrying against an account that can't come back.
    if (err.response?.statusCode == 403) {
      final data = err.response?.data;
      if (data is Map && (data['code'] ?? '').toString() == 'BANNED') {
        final msg = (data['message'] ?? '').toString().trim();
        onBanned?.call(msg.isEmpty ? 'تم حظر حسابك' : msg);
      }
    }

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
        if (kIsWeb && _looksLikeCorsError(err)) {
          errorMessage = 'Request blocked by CORS. Allow this web origin on the backend (CORS_ORIGIN).';
        } else {
          errorMessage = 'No internet connection';
        }
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

  bool _looksLikeCorsError(DioException err) {
    final message = [
      err.message,
      err.error?.toString(),
      err.response?.statusMessage,
    ].whereType<String>().join(' ').toLowerCase();

    return message.contains('xmlhttprequest onerror') ||
        message.contains('blocked by cors policy') ||
        message.contains('access-control-allow-origin') ||
        message.contains('net::err_failed');
  }
}

import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../utils/logger.dart';
import '../utils/storage_service.dart';
import 'dio_client.dart' show ErrorInterceptor;

/// Outcome of one attempt to exchange the refresh token for a fresh access
/// token. `sessionEnded` separates "the exchange itself failed" (the server
/// refused us, or the account is banned — the caller should end the session)
/// from "there was nothing to exchange", which leaves the caller's existing
/// error handling in charge.
class RefreshResult {
  const RefreshResult._(this.accessToken, this.sessionEnded);

  final String? accessToken;
  final bool sessionEnded;

  bool get ok => accessToken != null;

  static const noSession = RefreshResult._(null, false);
  static const ended = RefreshResult._(null, true);
}

/// The single place an expired access token is exchanged for a fresh one.
///
/// Two independent callers need this: the Dio 401 interceptor and the socket's
/// auth-failure handler. `/auth/refresh` rotates the refresh token, so a second
/// concurrent exchange is actively harmful — the winner invalidates the loser's
/// token and the user is logged out of a perfectly good session. Every caller
/// therefore shares the one in-flight future here instead of rotating twice.
class TokenRefresher {
  TokenRefresher._();

  static Future<RefreshResult>? _inFlight;

  /// Callers arriving mid-exchange await the running one rather than starting
  /// a second rotation.
  static Future<RefreshResult> refresh() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _run();
    _inFlight = future;
    // Guarded so a refresh that started after this one isn't cleared by it.
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  static Future<RefreshResult> _run() async {
    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null) return RefreshResult.noSession;

      // A bare Dio: going through DioClient would re-enter the 401 interceptor
      // that called us.
      final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      final newAccessToken = response.data['accessToken'] as String?;
      final newRefreshToken = response.data['refreshToken'] as String?;
      if (newAccessToken == null) return RefreshResult.noSession;

      await StorageService.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken ?? refreshToken,
      );
      return RefreshResult._(newAccessToken, false);
    } catch (e) {
      // A banned account is refused here with 403 BANNED; surface the reason
      // so the user is told why instead of being dropped at a silent login.
      if (e is DioException && e.response?.statusCode == 403) {
        final data = e.response?.data;
        if (data is Map && (data['code'] ?? '').toString() == 'BANNED') {
          final msg = (data['message'] ?? '').toString().trim();
          ErrorInterceptor.onBanned?.call(msg.isEmpty ? 'تم حظر حسابك' : msg);
        }
      }
      AppLogger.error('Token refresh failed: $e');
      return RefreshResult.ended;
    }
  }
}

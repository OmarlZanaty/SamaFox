import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Idempotency for every request that moves coins (server item 21).
///
/// Each such request is given a fresh `Idempotency-Key` once, on its
/// RequestOptions. Anything that re-sends THOSE options — the 401 token-refresh
/// retry, and the network retry below — therefore carries the same key, and the
/// server answers the repeat with the stored result of the first attempt
/// instead of charging, paying or rolling a second time.
///
/// A new tap by the user is a new request and gets a new key: that is a new
/// action, not a retry.
class IdempotencyInterceptor extends Interceptor {
  IdempotencyInterceptor(this._dio);

  final Dio _dio;
  static const _uuid = Uuid();
  static const _header = 'Idempotency-Key';
  static const _retriesKey = 'idem_retries';
  static const int _maxNetworkRetries = 2;

  /// Paths (relative to /api/v1/) whose POST/PATCH/DELETE move coins.
  static final List<RegExp> _moneyPaths = [
    RegExp(r'gifts/(send|send-batch)$'),
    RegExp(r'gifts/supporter-rewards/[^/]+/claim$'),
    RegExp(r'games/.+/(spin|drop|bet|cashout|cancel|clear|repeat|reduce|join|play|claim|pick|shoot|capture)$'),
    RegExp(r'games/(fish)/(shoot|capture)$'),
    RegExp(r'store/(buy|send)$'),
    RegExp(r'vip/buy$'),
    RegExp(r'messages/conversations/[^/]+/unlock$'),
    RegExp(r'charging-agencies/(transfer|topup)$'),
    RegExp(r'agencies/(send-coins|target/convert|target/sell)$'),
    RegExp(r'agencies/invite/[^/]+/respond$'),
    RegExp(r'cp/(requests|requests/[^/]+/(accept|reject)|unlock/confirm|partners/[^/]+)$'),
  ];

  static bool isMoneyRequest(RequestOptions o) {
    final m = o.method.toUpperCase();
    if (m != 'POST' && m != 'PATCH' && m != 'DELETE' && m != 'PUT') return false;
    final path = o.path.split('?').first.replaceFirst(RegExp(r'^/+'), '');
    return _moneyPaths.any((r) => r.hasMatch(path));
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isMoneyRequest(options) && options.headers[_header] == null) {
      options.headers[_header] = _uuid.v4();
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    final network = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout;
    // 409 REQUEST_IN_PROGRESS: the first copy is still running on the server —
    // ask again shortly with the same key and get its result.
    final inProgress = err.response?.statusCode == 409 &&
        err.response?.data is Map &&
        (err.response!.data as Map)['code'] == 'REQUEST_IN_PROGRESS';
    final tries = (o.extra[_retriesKey] as int?) ?? 0;
    if ((network || inProgress) && o.headers[_header] != null && tries < _maxNetworkRetries) {
      o.extra[_retriesKey] = tries + 1;
      await Future<void>.delayed(Duration(milliseconds: 700 * (tries + 1)));
      try {
        debugPrint('[idempotency] retry #${tries + 1} ${o.method} ${o.path} (same key)');
        handler.resolve(await _dio.fetch(o));
        return;
      } on DioException catch (e) {
        handler.next(e);
        return;
      }
    }
    handler.next(err);
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:samafox/services/dio_client.dart';

import '../models/gift.dart';

class GiftRepository {
  GiftRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  /// Video gift clips already pulled into the cache this session.
  static final Set<String> _warmedVideos = <String>{};

  /// How long to leave the room alone before starting any background download.
  ///
  /// A12/A25 — the client's most-repeated complaint is that entering a room is
  /// slow and that the app eats data ("استهلاك الداتا العالي بيخلي الناس تمسح
  /// البرنامج"). Warm-up used to start the instant the room screen was built,
  /// so joining a room fired a burst of clip downloads that competed with the
  /// socket handshake, the WebRTC negotiation and the seat/room API calls for
  /// the same connection — during the exact seconds the user is staring at a
  /// half-drawn room.
  static const Duration _warmupDelay = Duration(seconds: 6);

  /// Cap on clips pulled per room entry.
  ///
  /// The old loop downloaded EVERY video gift in the catalog. With a few dozen
  /// legendary clips that is tens of megabytes on every single room join, for
  /// gifts that may never be sent in that room. The cheapest ones are the ones
  /// actually sent often, so warming a bounded, cheapest-first slice buys most
  /// of the benefit for a fraction of the traffic.
  static const int _warmupLimit = 6;

  /// Pre-downloads a small set of VIDEO gift clips into the shared cache.
  ///
  /// [VideoGiftPlayer] fetches through the cache manager, so without any warm-up
  /// the first client to see a given gift stalls while it downloads and its
  /// audio lands seconds after everyone else's. This keeps that benefit for the
  /// gifts people actually send, without the full-catalog download that made
  /// room entry slow.
  ///
  /// Best-effort and fire-and-forget: failures are swallowed, each URL is
  /// attempted once per session, and clips are fetched one at a time so the
  /// warm-up never saturates the connection the room is running on.
  Future<void> warmVideoCache() async {
    try {
      await Future<void>.delayed(_warmupDelay);
      final catalog = await fetchCatalog();
      final videoGifts = catalog.all
          .where((g) => g.format == GiftFormat.video)
          .where((g) => (g.animationUrl ?? '').isNotEmpty)
          .where((g) => !_warmedVideos.contains(g.animationUrl))
          .toList()
        // Cheapest first: a 50-coin gift is sent hundreds of times for every
        // one time a legendary is, so those are the clips worth having local.
        ..sort((a, b) => a.coinCost.compareTo(b.coinCost));

      for (final gift in videoGifts.take(_warmupLimit)) {
        final url = gift.animationUrl!;
        _warmedVideos.add(url);
        try {
          await DefaultCacheManager().downloadFile(url);
        } catch (_) {
          // Missing/unreachable clip — the player falls back to streaming it.
          _warmedVideos.remove(url);
        }
      }
    } catch (e) {
      debugPrint('[GiftRepository] video warm-up skipped: $e');
    }
  }

  Future<GiftCatalog> fetchCatalog() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('gifts');
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw GiftRepositoryException(body['message']?.toString() ?? 'فشل تحميل الهدايا');
      }
      return GiftCatalog.fromJson(body);
    } on DioException catch (e) {
      throw _translateDioError(e, fallback: 'فشل تحميل الهدايا');
    }
  }

  Future<GiftSendResult> send({
    required String giftId,
    required int recipientId,
    int? roomId,
    int quantity = 1,
    String? comboKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'gifts/send',
        data: {
          'giftId': giftId,
          'recipientId': recipientId,
          if (roomId != null) 'roomId': roomId,
          'quantity': quantity,
          if (comboKey != null) 'comboKey': comboKey,
        },
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw GiftRepositoryException(
          body['message']?.toString() ?? 'فشل إرسال الهدية',
          code: body['code']?.toString(),
        );
      }
      return GiftSendResult(
        transactionId: body['transactionId'] as String,
        senderBalance: (body['senderBalance'] as num?)?.toInt() ?? 0,
        comboCount: (body['comboCount'] as num?)?.toInt() ?? 1,
        broadcast: body['broadcast'] as bool? ?? false,
      );
    } on DioException catch (e) {
      throw _translateDioError(e, fallback: 'فشل إرسال الهدية');
    }
  }

  /// A27 — "المايك الكامل" / "جميع الغرفة": one request, N full-price gifts.
  ///
  /// Each recipient receives the WHOLE gift and the sender pays price x N — the
  /// client's rule: "10 اشخاص على المايك والهدية بـ100، كل واحد ياخذ 100
  /// وينخصم من المُهدي 1000".
  ///
  /// This replaces a client-side loop over [send]: on a full room that was 30
  /// sequential requests, deep enough for the rate limiter to cut it off
  /// half-way with no way to tell the user which recipients had missed out.
  Future<GiftBatchSendResult> sendBatch({
    required String giftId,
    required List<int> recipientIds,
    int? roomId,
    int quantity = 1,
    String? comboKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'gifts/send-batch',
        data: {
          'giftId': giftId,
          'recipientIds': recipientIds,
          if (roomId != null) 'roomId': roomId,
          'quantity': quantity,
          if (comboKey != null) 'comboKey': comboKey,
        },
      );
      final body = res.data ?? const {};
      if (body['success'] != true) {
        throw GiftRepositoryException(
          body['message']?.toString() ?? 'فشل إرسال الهدية',
          code: body['code']?.toString(),
        );
      }
      final failures = ((body['failures'] as List?) ?? const [])
          .whereType<Map>()
          .map((f) => f['message']?.toString() ?? '')
          .where((m) => m.isNotEmpty)
          .toList();
      return GiftBatchSendResult(
        sent: (body['sent'] as num?)?.toInt() ?? 0,
        requested: (body['requested'] as num?)?.toInt() ?? recipientIds.length,
        senderBalance: (body['senderBalance'] as num?)?.toInt() ?? 0,
        broadcast: body['broadcast'] as bool? ?? false,
        failureMessages: failures,
      );
    } on DioException catch (e) {
      throw _translateDioError(e, fallback: 'فشل إرسال الهدية');
    }
  }

  /// Converts Dio errors into GiftRepositoryException with an Arabic message
  /// matched to known backend codes.
  GiftRepositoryException _translateDioError(DioException e, {required String fallback}) {
    final data = e.response?.data;
    String? code;
    String? serverMessage;
    if (data is Map) {
      code = data['code']?.toString();
      serverMessage = data['message']?.toString();
    }
    final message = _arabicMessageFor(code) ?? serverMessage ?? fallback;
    return GiftRepositoryException(message, code: code);
  }

  String? _arabicMessageFor(String? code) {
    switch (code) {
      case 'SELF_GIFT':
        return 'لا يمكنك إرسال هدية إلى نفسك';
      case 'INSUFFICIENT_COINS':
      case 'INSUFFICIENT_BALANCE':
        return 'رصيدك لا يكفي';
      case 'RATE_LIMIT':
      case 'RATE_LIMITED':
        return 'حاول لاحقاً';
      case 'RECIPIENT_NOT_FOUND':
        return 'لم يتم العثور على المستلم';
      case 'GIFT_NOT_FOUND':
      case 'INVALID_GIFT':
        return 'الهدية غير متوفرة';
      case 'INVALID_QUANTITY':
        return 'العدد غير صالح';
      case 'UNAUTHORIZED':
        return 'الجلسة منتهية، سجل الدخول مرة أخرى';
      default:
        return null;
    }
  }

  Future<List<GiftTransaction>> transactions({
    int page = 1,
    int limit = 20,
    String direction = 'all',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      'gifts/transactions',
      queryParameters: {'page': page, 'limit': limit, 'direction': direction},
    );
    final body = res.data ?? const {};
    final items = (body['items'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(GiftTransaction.fromJson)
        .toList();
  }
}

class GiftRepositoryException implements Exception {
  final String message;
  final String? code;
  GiftRepositoryException(this.message, {this.code});
  @override
  String toString() => 'GiftRepositoryException(${code ?? '?'}: $message)';
}

/// Outcome of a fan-out send. `sent` may be less than `requested` when some
/// recipients left the room mid-send; `failureMessages` explains which rules
/// stopped them so the user is not left guessing.
class GiftBatchSendResult {
  final int sent;
  final int requested;
  final int senderBalance;
  final bool broadcast;
  final List<String> failureMessages;
  const GiftBatchSendResult({
    required this.sent,
    required this.requested,
    required this.senderBalance,
    required this.broadcast,
    this.failureMessages = const [],
  });
}

class GiftSendResult {
  final String transactionId;
  final int senderBalance;
  final int comboCount;
  final bool broadcast;
  const GiftSendResult({
    required this.transactionId,
    required this.senderBalance,
    required this.comboCount,
    required this.broadcast,
  });
}

class GiftTransaction {
  final String id;
  final int senderId;
  final int recipientId;
  final int? roomId;
  final int quantity;
  final int totalCoins;
  final int comboCount;
  final DateTime createdAt;
  final Map<String, dynamic> rawGift;
  final Map<String, dynamic>? sender;
  final Map<String, dynamic>? recipient;

  GiftTransaction({
    required this.id,
    required this.senderId,
    required this.recipientId,
    this.roomId,
    required this.quantity,
    required this.totalCoins,
    required this.comboCount,
    required this.createdAt,
    required this.rawGift,
    this.sender,
    this.recipient,
  });

  factory GiftTransaction.fromJson(Map<String, dynamic> json) {
    return GiftTransaction(
      id: json['id'] as String,
      senderId: (json['senderId'] as num).toInt(),
      recipientId: (json['recipientId'] as num).toInt(),
      roomId: (json['roomId'] as num?)?.toInt(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      totalCoins: (json['totalCoins'] as num?)?.toInt() ?? 0,
      comboCount: (json['comboCount'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      rawGift: (json['gift'] as Map<String, dynamic>?) ?? const {},
      sender: json['sender'] as Map<String, dynamic>?,
      recipient: json['recipient'] as Map<String, dynamic>?,
    );
  }
}

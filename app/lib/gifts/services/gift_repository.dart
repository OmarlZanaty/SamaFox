import 'package:dio/dio.dart';
import 'package:samafox/services/dio_client.dart';

import '../models/gift.dart';

class GiftRepository {
  GiftRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

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

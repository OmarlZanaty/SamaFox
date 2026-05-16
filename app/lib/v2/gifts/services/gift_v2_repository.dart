import 'package:dio/dio.dart';
import 'package:samafox/config/app_config.dart';
import 'package:samafox/services/dio_client.dart';

import '../models/gift_v2.dart';

class GiftV2Repository {
  GiftV2Repository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  /// Compute the V2 base URL from V1. AppConfig.apiBaseUrl ends with `/api/v1/`.
  String get _v2 => AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '/api/v2');

  Future<GiftV2Catalog> fetchCatalog() async {
    final res = await _dio.get<Map<String, dynamic>>('$_v2/gifts');
    final body = res.data ?? const {};
    if (body['success'] != true) {
      throw GiftV2RepositoryException(body['message']?.toString() ?? 'Failed to load catalog');
    }
    return GiftV2Catalog.fromJson(body);
  }

  Future<GiftV2SendResult> send({
    required String giftId,
    required int recipientId,
    int? roomId,
    int quantity = 1,
    String? comboKey,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_v2/gifts/send',
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
      throw GiftV2RepositoryException(
        body['message']?.toString() ?? 'Send failed',
        code: body['code']?.toString(),
      );
    }
    return GiftV2SendResult(
      transactionId: body['transactionId'] as String,
      senderBalance: (body['senderBalance'] as num?)?.toInt() ?? 0,
      comboCount: (body['comboCount'] as num?)?.toInt() ?? 1,
      broadcast: body['broadcast'] as bool? ?? false,
    );
  }

  Future<List<GiftV2Transaction>> transactions({
    int page = 1,
    int limit = 20,
    String direction = 'all',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_v2/gifts/transactions',
      queryParameters: {'page': page, 'limit': limit, 'direction': direction},
    );
    final body = res.data ?? const {};
    final items = (body['items'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(GiftV2Transaction.fromJson)
        .toList();
  }
}

class GiftV2RepositoryException implements Exception {
  final String message;
  final String? code;
  GiftV2RepositoryException(this.message, {this.code});
  @override
  String toString() => 'GiftV2RepositoryException(${code ?? '?'}: $message)';
}

class GiftV2SendResult {
  final String transactionId;
  final int senderBalance;
  final int comboCount;
  final bool broadcast;
  const GiftV2SendResult({
    required this.transactionId,
    required this.senderBalance,
    required this.comboCount,
    required this.broadcast,
  });
}

class GiftV2Transaction {
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

  GiftV2Transaction({
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

  factory GiftV2Transaction.fromJson(Map<String, dynamic> json) {
    return GiftV2Transaction(
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

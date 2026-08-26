import 'package:dio/dio.dart';

import '../services/dio_client.dart';

/// A15 / #20 / #44 — نظام الـ CP.
///
/// Client spec (17/08 23:01, with a video and a screenshot):
///   • A sends a CP gift to B → B gets "فلان بعتلك هدية CP: قبول / رفض"
///   • reject → the gift does not complete, but **30%** of its value is still
///     taken off A
///   • accept → A pays the full price and the value goes into B's target
///   • the pairing then shows on the profile, and the home page carries a box
///     listing everyone you have a CP with, each tappable to cancel
///
/// Nothing is charged when the invitation is sent — that is what makes the
/// 30%/100% split possible at all. The server verifies A can afford it up
/// front and takes the money when B answers.
class CpRepository {
  CpRepository({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;

  /// Sends the CP invitation. Throws [CpException] with an Arabic message.
  Future<void> sendRequest({
    required int recipientId,
    required String giftId,
    int quantity = 1,
    int? roomId,
  }) async {
    await _post('cp/requests', {
      'recipientId': recipientId,
      'giftId': giftId,
      'quantity': quantity,
      if (roomId != null) 'roomId': roomId,
    });
  }

  /// Invitations still waiting on me.
  Future<List<CpRequest>> pendingRequests() async {
    final body = await _get('cp/requests/pending');
    return ((body['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => CpRequest.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> accept(int requestId) => _post('cp/requests/$requestId/accept', const {});

  Future<void> reject(int requestId) => _post('cp/requests/$requestId/reject', const {});

  /// The sender withdrawing his own invitation. Costs nothing.
  Future<void> cancelRequest(int requestId) => _delete('cp/requests/$requestId');

  /// My CP partners, or someone else's for their profile card.
  Future<List<CpPartner>> partners({int? userId}) async {
    final body = await _get(userId == null ? 'cp/partners' : 'cp/partners/$userId');
    return ((body['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => CpPartner.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// "الغاء CP مع فلان؟ نعم / لا" — ends the pairing, refunds nothing.
  Future<void> removePartner(int partnerId) => _delete('cp/partners/$partnerId');

  // ---- transport -------------------------------------------------------

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path);
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: data);
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(path);
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic>? body) {
    final data = body ?? const <String, dynamic>{};
    if (data['success'] != true) {
      throw CpException(
        data['message']?.toString() ?? 'تعذر إتمام العملية',
        code: data['code']?.toString(),
      );
    }
    return data;
  }

  CpException _translate(DioException e) {
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    final serverMessage = data is Map ? data['message']?.toString() : null;
    // The server already speaks Arabic for every CP rule, so its message is
    // preferred; the map below only covers codes raised by the gift layer that
    // acceptance runs through.
    const fallbacks = <String, String>{
      'INSUFFICIENT_COINS': 'رصيدك لا يكفي',
      'ALREADY_PAIRED': 'لديكما ارتباط CP بالفعل',
      'SELF_CP': 'لا يمكنك إرسال هدية CP لنفسك',
      'ALREADY_RESOLVED': 'تم الرد على هذا الطلب بالفعل',
    };
    return CpException(
      serverMessage ?? fallbacks[code] ?? 'تعذر إتمام العملية',
      code: code,
    );
  }
}

class CpException implements Exception {
  final String message;
  final String? code;
  CpException(this.message, {this.code});
  @override
  String toString() => 'CpException(${code ?? '?'}: $message)';
}

/// A pending invitation shown to the recipient.
class CpRequest {
  final int id;
  final int senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String giftName;
  final String giftIconUrl;
  final int quantity;
  final int totalCoins;

  /// What the SENDER loses if this is rejected — surfaced so the recipient
  /// understands that refusing is not free for the other person.
  final int rejectFeeCoins;

  const CpRequest({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl,
    required this.giftName,
    required this.giftIconUrl,
    required this.quantity,
    required this.totalCoins,
    required this.rejectFeeCoins,
  });

  factory CpRequest.fromJson(Map<String, dynamic> json) {
    final sender = (json['sender'] as Map?) ?? const {};
    final gift = (json['gift'] as Map?) ?? const {};
    return CpRequest(
      id: (json['id'] as num?)?.toInt() ?? 0,
      senderId: (sender['id'] as num?)?.toInt() ?? 0,
      senderName: sender['name']?.toString() ?? 'مستخدم',
      senderAvatarUrl: sender['avatarUrl']?.toString(),
      giftName: (gift['nameAr'] ?? gift['name'])?.toString() ?? 'هدية',
      giftIconUrl: gift['iconUrl']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      totalCoins: (json['totalCoins'] as num?)?.toInt() ?? 0,
      rejectFeeCoins: (json['rejectFeeCoins'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One person you are CP'd with.
class CpPartner {
  final int pairId;
  final int userId;
  final String name;
  final String? avatarUrl;
  final int? displayId;
  final int level;
  final int vipLevel;
  final String? giftIconUrl;
  final DateTime? since;

  const CpPartner({
    required this.pairId,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.displayId,
    this.level = 1,
    this.vipLevel = 0,
    this.giftIconUrl,
    this.since,
  });

  factory CpPartner.fromJson(Map<String, dynamic> json) {
    final partner = (json['partner'] as Map?) ?? const {};
    final gift = (json['gift'] as Map?);
    return CpPartner(
      pairId: (json['pairId'] as num?)?.toInt() ?? 0,
      userId: (partner['id'] as num?)?.toInt() ?? 0,
      name: partner['name']?.toString() ?? 'مستخدم',
      avatarUrl: partner['avatarUrl']?.toString(),
      displayId: (partner['displayId'] as num?)?.toInt(),
      level: (partner['level'] as num?)?.toInt() ?? 1,
      vipLevel: (partner['vipLevel'] as num?)?.toInt() ?? 0,
      giftIconUrl: gift?['iconUrl']?.toString(),
      since: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

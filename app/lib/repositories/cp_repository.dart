import 'package:shared_preferences/shared_preferences.dart';
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

  /// Sends a CP gift. Throws [CpException] with an Arabic message.
  ///
  /// Not yet partners → an invitation (charges nothing until answered).
  /// Already partners → the gift is sent now and raises the pair's CP level;
  /// the result carries the points added and the new level (2026-09-24).
  /// [requestKey] must be the same for retries of ONE tap, so a resend is
  /// recognised by the server and never charged or counted twice.
  Future<CpSendResult> sendRequest({
    required int recipientId,
    required String giftId,
    int quantity = 1,
    int? roomId,
    String? requestKey,
  }) async {
    final body = await _post('cp/requests', {
      'recipientId': recipientId,
      'giftId': giftId,
      'quantity': quantity,
      if (roomId != null) 'roomId': roomId,
      if (requestKey != null) 'requestKey': requestKey,
    });
    return CpSendResult.fromJson(Map<String, dynamic>.from((body['data'] as Map?) ?? const {}));
  }

  /// My partners, after uploading once a featured choice that an older app
  /// build kept only on this phone. Use for the OWNER's own views.
  Future<List<CpPartner>> myPartnersSynced({int? userId}) async {
    final list = await partners(userId: userId);
    if (await CpFeatured.uploadLocalChoice(this, list)) {
      return partners(userId: userId);
    }
    return list;
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

  // ---- صلاحيات فتح CP (2026-09-22) -------------------------------------
  //
  // Opening CP can cost coins now (admin policy or a per-user grant). The
  // server is the only one that decides and the only one that charges: the
  // app asks for the quote, shows it, and on "موافق" asks the server to take
  // exactly that. Under the default policy (free) nothing here costs anything.

  /// Am I unlocked, and if not, what would it cost? Shown BEFORE confirming.
  Future<CpUnlockStatus> unlockStatus() async {
    final body = await _get('cp/unlock/status');
    return CpUnlockStatus.fromJson(Map<String, dynamic>.from((body['data'] as Map?) ?? const {}));
  }

  /// The user agreed to the quoted fee. Throws [CpException] with code
  /// `INSUFFICIENT_COINS` (and [CpException.shortfall]) when the balance is
  /// short — nothing is deducted in that case. Safe to call twice.
  Future<CpUnlockResult> confirmUnlock() async {
    final body = await _post('cp/unlock/confirm', const {});
    return CpUnlockResult.fromJson(Map<String, dynamic>.from((body['data'] as Map?) ?? const {}));
  }

  /// "مستخدم CP الظاهر" — which partner shows beside my photo, for everyone
  /// who opens my profile. `null` goes back to the newest pair.
  Future<void> setFeatured(int? partnerId) => _patch('cp/featured', {'partnerId': partnerId});

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

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(path, data: data);
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
        data: data,
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
      'CP_LOCKED': 'يجب فتح الـ CP أولاً',
    };
    return CpException(
      serverMessage ?? fallbacks[code] ?? 'تعذر إتمام العملية',
      code: code,
      status: e.response?.statusCode,
      // CP_LOCKED / INSUFFICIENT_COINS carry feeCoins, balance and shortfall
      // at the top level of the body.
      data: data is Map ? Map<String, dynamic>.from(data) : null,
    );
  }
}

class CpException implements Exception {
  final String message;
  final String? code;
  final int? status;

  /// The raw error body, for the numbers the server attaches to it.
  final Map<String, dynamic>? data;

  CpException(this.message, {this.code, this.status, this.data});

  int? _int(String key) => (data?[key] as num?)?.toInt();

  /// The fee quoted on `CP_LOCKED` / `INSUFFICIENT_COINS`.
  int? get feeCoins => _int('feeCoins');

  /// Coins missing to pay [feeCoins]. Present on `INSUFFICIENT_COINS`.
  int? get shortfall => _int('shortfall');

  int? get balance => _int('balance');

  @override
  String toString() => 'CpException(${code ?? '?'}: $message)';
}

/// What `POST /cp/requests` did.
class CpSendResult {
  /// `invitation` or `partner_gift`.
  final String kind;

  /// partner_gift only: CP value this gift added, and the pair's state after.
  final int pointsAdded;
  final int? cpValue;
  final int? level;
  final String? levelName;
  final bool leveledUp;

  /// partner_gift only: the sender's balance after the charge.
  final int? balance;

  /// A resend of a request already completed — nothing new was charged.
  final bool duplicate;

  const CpSendResult({
    required this.kind,
    this.pointsAdded = 0,
    this.cpValue,
    this.level,
    this.levelName,
    this.leveledUp = false,
    this.balance,
    this.duplicate = false,
  });

  bool get isPartnerGift => kind == 'partner_gift';

  factory CpSendResult.fromJson(Map<String, dynamic> json) => CpSendResult(
        kind: json['kind']?.toString() ?? 'invitation',
        pointsAdded: (json['pointsAdded'] as num?)?.toInt() ?? 0,
        cpValue: (json['cpValue'] as num?)?.toInt(),
        level: (json['level'] as num?)?.toInt(),
        levelName: json['levelName']?.toString(),
        leveledUp: json['leveledUp'] == true,
        balance: (json['balance'] as num?)?.toInt(),
        duplicate: json['duplicate'] == true,
      );
}

/// `GET /cp/unlock/status`.
class CpUnlockStatus {
  final bool unlocked;

  /// `free` or `fee` — the policy that applies to this user.
  final String mode;

  /// What confirming would cost right now. 0 when already unlocked or free.
  final int feeCoins;
  final int balance;

  /// Coins missing to pay [feeCoins]; 0 when affordable.
  final int shortfall;

  const CpUnlockStatus({
    required this.unlocked,
    required this.mode,
    required this.feeCoins,
    required this.balance,
    required this.shortfall,
  });

  bool get needsPayment => !unlocked && feeCoins > 0;

  factory CpUnlockStatus.fromJson(Map<String, dynamic> json) => CpUnlockStatus(
        unlocked: json['unlocked'] == true,
        mode: json['mode']?.toString() ?? 'free',
        feeCoins: (json['feeCoins'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        shortfall: (json['shortfall'] as num?)?.toInt() ?? 0,
      );
}

/// `POST /cp/unlock/confirm`.
class CpUnlockResult {
  final bool alreadyUnlocked;
  final int paidCoins;

  /// The balance after the deduction — authoritative, use it to refresh the UI.
  final int balance;

  const CpUnlockResult({required this.alreadyUnlocked, required this.paidCoins, required this.balance});

  factory CpUnlockResult.fromJson(Map<String, dynamic> json) => CpUnlockResult(
        alreadyUnlocked: json['alreadyUnlocked'] == true,
        paidCoins: (json['paidCoins'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
      );
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
/// "لو انا معايا اكتر من سي بي مين يظهر معايا فوق — خليني احدده من القايمه".
///
/// Which pair is shown beside the photo. Since 2026-09-22 this lives on the
/// SERVER (`User.cpFeaturedPartnerId`, set with [CpRepository.setFeatured]):
/// a visitor must see the owner's choice, and the admin can change it. The
/// partners list carries it as [CpPartner.featured]. The device copy below is
/// only a fallback for a server that predates the flag.
class CpFeatured {
  CpFeatured._();

  static const String _key = 'cp_featured_partner_id';

  static Future<int?> get() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_key);
      return (v == null || v <= 0) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(int partnerUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, partnerUserId);
    } catch (_) {
      // A preference that will not save is not worth failing the tap over.
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// One-time move of a choice an older build stored on this phone up to the
  /// server, so the owner's pick is what VISITORS see. Afterwards the device
  /// copy is deleted and the server is the only source. Returns true when the
  /// server's choice was changed (the caller should re-fetch the list).
  static Future<bool> uploadLocalChoice(CpRepository repo, List<CpPartner> partners) async {
    final local = await get();
    if (local == null) return false;
    // A server without the `featured` flag: the device copy is still in use.
    if (partners.isEmpty || partners.every((p) => p.featured == null)) return false;
    final stillPaired = partners.any((p) => p.userId == local);
    final shown = partners.where((p) => p.featured == true);
    final int? serverShows = shown.isEmpty ? null : shown.first.userId;
    var changed = false;
    if (stillPaired && serverShows != local) {
      try {
        await repo.setFeatured(local);
        changed = true;
      } on CpException {
        return false; // keep the device copy and try again next time
      }
    }
    await clear();
    return changed;
  }

  /// The pair to show: the server's choice, else the locally chosen one if it
  /// still exists, else the newest.
  static CpPartner? pick(List<CpPartner> partners, int? chosenUserId) {
    if (partners.isEmpty) return null;
    for (final p in partners) {
      if (p.featured == true) return p;
    }
    if (chosenUserId != null) {
      for (final p in partners) {
        if (p.userId == chosenUserId) return p;
      }
    }
    return partners.first;
  }
}

class CpPartner {
  final int pairId;
  final int userId;
  final String name;
  final String? avatarUrl;
  final int? displayId;
  final int level;
  final int vipLevel;

  /// 'male' / 'female' / null — picks the blue or pink ring on the couple card.
  final String? gender;
  final String? giftIconUrl;

  /// The clip of the gift that created the pair, when it has one. Lets the
  /// profile card PLAY it instead of showing a still icon.
  final String? giftAnimationUrl;
  final DateTime? since;

  // The PAIR's CP level, computed by the server (2026-09-22). Not to be
  // confused with [level], which is the partner's own user LV. Null when the
  // server predates it — callers then fall back to the days ladder.
  final int? cpLevel;
  final String? cpLevelName;
  final int? cpValue;
  final int? cpDays;

  /// The owner's "مستخدم CP الظاهر". Null on an older server.
  final bool? featured;

  const CpPartner({
    required this.pairId,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.displayId,
    this.level = 1,
    this.vipLevel = 0,
    this.gender,
    this.giftIconUrl,
    this.giftAnimationUrl,
    this.since,
    this.cpLevel,
    this.cpLevelName,
    this.cpValue,
    this.cpDays,
    this.featured,
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
      gender: partner['gender']?.toString(),
      giftIconUrl: gift?['iconUrl']?.toString(),
      giftAnimationUrl: gift?['animationUrl']?.toString(),
      since: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      cpLevel: (json['level'] as num?)?.toInt(),
      cpLevelName: json['levelName']?.toString(),
      cpValue: (json['cpValue'] as num?)?.toInt(),
      cpDays: (json['days'] as num?)?.toInt(),
      featured: json['featured'] is bool ? json['featured'] as bool : null,
    );
  }
}

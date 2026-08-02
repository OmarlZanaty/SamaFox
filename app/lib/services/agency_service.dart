import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dio_client.dart';
import '../utils/storage_service.dart';

/// Hosting-agency client: agent panel (invite/search/members/exit policy)
/// and member actions (membership info, leave).
class AgencyService {
  Future<Options?> _auth() async {
    final token = await StorageService.getAccessToken();
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// null when the user belongs to no approved agency.
  ///
  /// [agencyType] picks which one when the user has both a HOSTING and a
  /// CHARGING agency — without it the server returns an arbitrary one.
  Future<Map<String, dynamic>?> getMyMembership({String? agencyType}) async {
    try {
      final res = await DioClient.dio.get(
        '/agencies/my-membership',
        queryParameters: {if (agencyType != null) 'agencyType': agencyType},
        options: await _auth(),
      );
      final data = (res.data is Map) ? res.data['data'] : null;
      return data == null ? null : _asMap(data);
    } catch (e) {
      debugPrint('AgencyService.getMyMembership error: $e');
      return null;
    }
  }

  /// Every approved agency the user belongs to — the data behind the وكالتي
  /// chooser (one entry per agency, each with its own role and type).
  Future<List<Map<String, dynamic>>> getMyMemberships() async {
    try {
      final res = await DioClient.dio.get('/agencies/my-memberships', options: await _auth());
      final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
      return list.map(_asMap).toList();
    } catch (e) {
      debugPrint('AgencyService.getMyMemberships error: $e');
      return const [];
    }
  }

  /// Agent only: agency info + members with target earnings.
  ///
  /// [agencyType] disambiguates when the caller manages BOTH a HOSTING and a
  /// CHARGING agency — without it the server can return the other agency's
  /// roster.
  Future<Map<String, dynamic>?> getMembersStats({String? agencyType}) async {
    try {
      final res = await DioClient.dio.get(
        '/agencies/members-stats',
        queryParameters: {if (agencyType != null) 'agencyType': agencyType},
        options: await _auth(),
      );
      return _asMap(res.data['data']);
    } catch (e) {
      debugPrint('AgencyService.getMembersStats error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchUser(String q, {String? agencyType}) async {
    final res = await DioClient.dio.get(
      '/agencies/search-user',
      queryParameters: {'q': q, if (agencyType != null) 'agencyType': agencyType},
      options: await _auth(),
    );
    final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
    return list.map(_asMap).toList();
  }

  /// [agencyType] must match the agency the panel is showing — without it the
  /// server invites into whichever agency the agent joined first, so the host
  /// silently lands in the wrong one.
  Future<void> inviteUser(int userId, {String? agencyType}) async {
    final res = await DioClient.dio.post(
      '/agencies/invite/$userId',
      queryParameters: {if (agencyType != null) 'agencyType': agencyType},
      options: await _auth(),
    );
    if (res.data is Map && res.data['success'] != true) {
      throw Exception(res.data['message'] ?? 'فشل إرسال الدعوة');
    }
  }

  Future<void> respondInvite(int inviteId, bool accept) async {
    await DioClient.dio.post(
      '/agencies/invite/$inviteId/respond',
      data: {'action': accept ? 'accept' : 'reject'},
      options: await _auth(),
    );
  }

  /// [agencyType] disambiguates the same way [inviteUser] does.
  Future<void> removeMember(int userId, {String? agencyType}) async {
    await DioClient.dio.delete(
      '/agencies/members/$userId',
      queryParameters: {if (agencyType != null) 'agencyType': agencyType},
      options: await _auth(),
    );
  }

  /// [agencyType] says which owned agency the fee belongs to.
  Future<void> setExitSettings({
    required bool exitLocked,
    required int exitPriceCoins,
    String? agencyType,
  }) async {
    await DioClient.dio.patch(
      '/agencies/exit-settings',
      data: {
        'exitLocked': exitLocked,
        'exitPriceCoins': exitPriceCoins,
        if (agencyType != null) 'agencyType': agencyType,
      },
      options: await _auth(),
    );
  }

  /// Leaves [agencyId] — the agency whose exit fee the user was just shown.
  /// Without it the server picks a membership itself, which is how someone in
  /// two agencies left the wrong (unlocked) one and skipped the fee.
  ///
  /// Returns the coins paid (0 when exit was open). Throws on insufficient coins.
  Future<int> leaveAgency({int? agencyId, String? agencyType}) async {
    try {
      final res = await DioClient.dio.post(
        '/agencies/leave',
        data: {
          if (agencyId != null) 'agencyId': agencyId,
          if (agencyType != null) 'agencyType': agencyType,
        },
        options: await _auth(),
      );
      final data = _asMap(res.data is Map ? res.data['data'] : null);
      return (data['paidCoins'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      final msg = (e.response?.data is Map) ? e.response?.data['message'] : null;
      if (msg == 'INSUFFICIENT_COINS') {
        throw Exception('رصيد الكوينز غير كافٍ لدفع رسوم الخروج');
      }
      rethrow;
    }
  }

  /// [agencyType] disambiguates when the caller owns both a HOSTING and a
  /// CHARGING agency — without it, the backend transfers whichever one it
  /// finds first, which is only safe for a single-agency owner.
  Future<void> transferOwnership(int toUserId, {String? agencyType}) async {
    await DioClient.dio.post(
      '/agencies/transfer-ownership',
      data: {'toUserId': toUserId, if (agencyType != null) 'agencyType': agencyType},
      options: await _auth(),
    );
  }

  // ── Branches (فرع): owner-only, up to 3 partners with the same management
  // access but no ownership. ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listBranches({String agencyType = 'HOSTING'}) async {
    final res = await DioClient.dio.get(
      '/agencies/branches',
      queryParameters: {'agencyType': agencyType},
      options: await _auth(),
    );
    final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
    return list.map(_asMap).toList();
  }

  Future<void> addBranch(int userId, {String agencyType = 'HOSTING'}) async {
    await DioClient.dio.post(
      '/agencies/branches',
      data: {'userId': userId, 'agencyType': agencyType},
      options: await _auth(),
    );
  }

  Future<void> removeBranch(int userId, {String agencyType = 'HOSTING'}) async {
    await DioClient.dio.delete(
      '/agencies/branches/$userId',
      queryParameters: {'agencyType': agencyType},
      options: await _auth(),
    );
  }
}

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
  Future<Map<String, dynamic>?> getMyMembership() async {
    try {
      final res = await DioClient.dio.get('/agencies/my-membership', options: await _auth());
      final data = (res.data is Map) ? res.data['data'] : null;
      return data == null ? null : _asMap(data);
    } catch (e) {
      debugPrint('AgencyService.getMyMembership error: $e');
      return null;
    }
  }

  /// Agent only: agency info + members with target earnings.
  Future<Map<String, dynamic>?> getMembersStats() async {
    try {
      final res = await DioClient.dio.get('/agencies/members-stats', options: await _auth());
      return _asMap(res.data['data']);
    } catch (e) {
      debugPrint('AgencyService.getMembersStats error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchUser(String q) async {
    final res = await DioClient.dio.get(
      '/agencies/search-user',
      queryParameters: {'q': q},
      options: await _auth(),
    );
    final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
    return list.map(_asMap).toList();
  }

  Future<void> inviteUser(int userId) async {
    final res = await DioClient.dio.post('/agencies/invite/$userId', options: await _auth());
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

  Future<void> removeMember(int userId) async {
    await DioClient.dio.delete('/agencies/members/$userId', options: await _auth());
  }

  Future<void> setExitSettings({required bool exitLocked, required int exitPriceCoins}) async {
    await DioClient.dio.patch(
      '/agencies/exit-settings',
      data: {'exitLocked': exitLocked, 'exitPriceCoins': exitPriceCoins},
      options: await _auth(),
    );
  }

  /// Returns the coins paid (0 when exit was open). Throws on insufficient coins.
  Future<int> leaveAgency() async {
    try {
      final res = await DioClient.dio.post('/agencies/leave', options: await _auth());
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
}

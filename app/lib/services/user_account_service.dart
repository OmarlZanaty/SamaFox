import 'package:dio/dio.dart';
import 'dio_client.dart';

/// Account-level actions from the settings menu (#2):
/// personal blacklist (القائمة السوداء) + delete account.
class UserAccountService {
  UserAccountService._();

  static Dio get _dio => DioClient.dio;

  /// Users the current account has blocked, newest first.
  /// Each entry: { blockedAt, user: {id, name, displayId, avatarUrl, ...} }
  static Future<List<Map<String, dynamic>>> myBlocks() async {
    final res = await _dio.get('/users/me/blocks');
    final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> block(int userId) async {
    await _dio.post('/users/$userId/block');
  }

  static Future<void> unblock(int userId) async {
    await _dio.delete('/users/$userId/block');
  }

  /// Whether the current account has blocked [userId].
  static Future<bool> isBlocked(int userId) async {
    final blocks = await myBlocks();
    return blocks.any((b) => (b['user'] as Map?)?['id'] == userId);
  }

  /// Permanently disables the caller's account (server anonymizes + bans it).
  static Future<void> deleteAccount() async {
    await _dio.delete('/users/me');
  }
}

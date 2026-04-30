import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/user.dart';

class StorageService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('StorageService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // ==================== AUTH DATA ====================

  static Future<void> saveAuthData({
    required String accessToken,
    required String refreshToken,
    required User user,
  }) async {
    // ✅ Clean token before saving to prevent quote issues
    String cleanToken = accessToken.trim();
    // Remove surrounding quotes (single or double)
    if (cleanToken.startsWith('"') && cleanToken.endsWith('"') && cleanToken.length > 2) {
      cleanToken = cleanToken.substring(1, cleanToken.length - 1);
    }
    if (cleanToken.startsWith("'") && cleanToken.endsWith("'") && cleanToken.length > 2) {
      cleanToken = cleanToken.substring(1, cleanToken.length - 1);
    }

    await prefs.setString(AppConfig.accessTokenKey, cleanToken);
    await prefs.setString('access_token', cleanToken); // ✅ save under both keys
    await prefs.setString(AppConfig.refreshTokenKey, refreshToken);
    await prefs.setString(AppConfig.userDataKey, jsonEncode(user.toJson()));
  }

  /// Save only tokens (no user object needed) — used by token refresh interceptor
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    String cleanToken = accessToken.trim()
        .replaceAll('"', '')
        .replaceAll("'", '');

    await prefs.setString(AppConfig.accessTokenKey, cleanToken);
    await prefs.setString('access_token', cleanToken); // both keys
    await prefs.setString(AppConfig.refreshTokenKey, refreshToken);
  }

  static Future<String?> getAccessToken() async {
    // ✅ Always use cached instance if available, avoids null during early calls
    final p = _prefs ?? await SharedPreferences.getInstance();
    // cache it for future sync calls
    _prefs ??= p;

    String? token = p.getString(AppConfig.accessTokenKey)
        ?? p.getString('access_token');

    if (token == null) return null;

    token = token.trim();

    if (token.startsWith('"') && token.endsWith('"') && token.length > 2) {
      token = token.substring(1, token.length - 1);
    }
    if (token.startsWith("'") && token.endsWith("'") && token.length > 2) {
      token = token.substring(1, token.length - 1);
    }

    if (token.split('.').length != 3) {
      print('⚠️ Stored token is malformed, clearing');
      await p.remove(AppConfig.accessTokenKey);
      await p.remove('access_token');
      return null;
    }

    return token;
  }

  static Future<String?> getRefreshToken() async {
    return prefs.getString(AppConfig.refreshTokenKey);
  }

  static Future<void> deleteAccessToken() async {
    await prefs.remove(AppConfig.accessTokenKey);
    await prefs.remove('access_token');
  }

  static Future<void> deleteRefreshToken() async {
    await prefs.remove(AppConfig.refreshTokenKey);
  }

  static Future<void> clearTokens() async {
    await deleteAccessToken();
    await deleteRefreshToken();
  }

  static Future<User?> getCurrentUser() async {
    final userJson = prefs.getString(AppConfig.userDataKey);
    if (userJson == null) return null;

    try {
      return User.fromJson(jsonDecode(userJson));
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateUser(User user) async {
    await prefs.setString(AppConfig.userDataKey, jsonEncode(user.toJson()));
  }

  static Future<void> clearAuthData() async {
    await prefs.remove(AppConfig.accessTokenKey);
    await prefs.remove('access_token');
    await prefs.remove(AppConfig.refreshTokenKey);
    await prefs.remove(AppConfig.userDataKey);
  }

  static Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    final guestUserId = await getGuestUserId();
    return (token != null && token.isNotEmpty) || guestUserId != null;
  }

  // ==================== GUEST USER DATA ====================

  static Future<void> saveGuestUser({
    required int userId,
    required String username,
    String? avatar,
    required String deviceId,
  }) async {
    await prefs.setInt(AppConfig.guestUserIdKey, userId);
    await prefs.setString(AppConfig.guestUsernameKey, username);
    if (avatar != null) {
      await prefs.setString('guest_avatar', avatar);
    }
    await prefs.setString('guest_device_id', deviceId);
    await prefs.setBool('is_guest', true);
  }

  static Future<int?> getGuestUserId() async {
    return prefs.getInt(AppConfig.guestUserIdKey);
  }

  static Future<String?> getGuestUsername() async {
    return prefs.getString(AppConfig.guestUsernameKey);
  }

  static Future<bool> isGuest() async {
    return prefs.getBool('is_guest') ?? false;
  }

  static Future<void> clearGuestUser() async {
    await prefs.remove(AppConfig.guestUserIdKey);
    await prefs.remove(AppConfig.guestUsernameKey);
    await prefs.remove('guest_avatar');
    await prefs.remove('guest_device_id');
    await prefs.remove('is_guest');
  }

  // ==================== THEME & LANGUAGE ====================

  static Future<void> saveDarkMode(bool isDarkMode) async {
    await prefs.setBool(AppConfig.darkModeKey, isDarkMode);
  }

  static Future<bool> getDarkMode() async {
    return prefs.getBool(AppConfig.darkModeKey) ?? AppConfig.defaultDarkMode;
  }

  static Future<void> saveLanguage(String languageCode) async {
    await prefs.setString(AppConfig.languageKey, languageCode);
  }

  static Future<String> getLanguage() async {
    return prefs.getString(AppConfig.languageKey) ?? AppConfig.defaultLanguage;
  }

  // ==================== CLEAR ALL ====================

  static Future<void> clearAll() async {
    await prefs.clear();
  }
}
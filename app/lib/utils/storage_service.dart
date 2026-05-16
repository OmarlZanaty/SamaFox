import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/user.dart';

class StorageService {
  // Tokens live in encrypted secure storage; everything else in SharedPreferences.
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Migrate any tokens previously stored in SharedPreferences.
    await _migrateTokensToSecureStorage();
  }

  static Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // One-time migration: move tokens out of SharedPreferences into secure storage.
  static Future<void> _migrateTokensToSecureStorage() async {
    final p = await _getPrefs();
    final legacyAccess = p.getString(AppConfig.accessTokenKey) ?? p.getString('access_token');
    final legacyRefresh = p.getString(AppConfig.refreshTokenKey);

    if (legacyAccess != null && legacyAccess.isNotEmpty) {
      await _secure.write(key: AppConfig.accessTokenKey, value: legacyAccess);
      await p.remove(AppConfig.accessTokenKey);
      await p.remove('access_token');
    }
    if (legacyRefresh != null && legacyRefresh.isNotEmpty) {
      await _secure.write(key: AppConfig.refreshTokenKey, value: legacyRefresh);
      await p.remove(AppConfig.refreshTokenKey);
    }
  }

  static String _cleanToken(String raw) {
    var t = raw.trim().replaceAll('"', '').replaceAll("'", '');
    if (t.startsWith('Bearer ')) t = t.substring(7).trim();
    return t;
  }

  // ==================== AUTH DATA ====================

  static Future<void> saveAuthData({
    required String accessToken,
    required String refreshToken,
    required User user,
  }) async {
    await saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    final p = await _getPrefs();
    await p.setString(AppConfig.userDataKey, jsonEncode(user.toJson()));
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final cleanAccess = _cleanToken(accessToken);
    final cleanRefresh = _cleanToken(refreshToken);
    await _secure.write(key: AppConfig.accessTokenKey, value: cleanAccess);
    await _secure.write(key: AppConfig.refreshTokenKey, value: cleanRefresh);
  }

  static Future<String?> getAccessToken() async {
    String? token = await _secure.read(key: AppConfig.accessTokenKey);
    if (token == null || token.isEmpty) return null;
    token = _cleanToken(token);
    if (token.split('.').length != 3) {
      await _secure.delete(key: AppConfig.accessTokenKey);
      return null;
    }
    return token;
  }

  static Future<String?> getRefreshToken() async {
    final token = await _secure.read(key: AppConfig.refreshTokenKey);
    if (token == null || token.isEmpty) return null;
    return _cleanToken(token);
  }

  static Future<void> deleteAccessToken() async {
    await _secure.delete(key: AppConfig.accessTokenKey);
  }

  static Future<void> deleteRefreshToken() async {
    await _secure.delete(key: AppConfig.refreshTokenKey);
  }

  static Future<void> clearTokens() async {
    await _secure.delete(key: AppConfig.accessTokenKey);
    await _secure.delete(key: AppConfig.refreshTokenKey);
  }

  static Future<User?> getCurrentUser() async {
    final p = await _getPrefs();
    final userJson = p.getString(AppConfig.userDataKey);
    if (userJson == null) return null;
    try {
      return User.fromJson(jsonDecode(userJson));
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateUser(User user) async {
    final p = await _getPrefs();
    await p.setString(AppConfig.userDataKey, jsonEncode(user.toJson()));
  }

  static Future<void> clearAuthData() async {
    await clearTokens();
    final p = await _getPrefs();
    await p.remove(AppConfig.userDataKey);
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
    final p = await _getPrefs();
    await p.setInt(AppConfig.guestUserIdKey, userId);
    await p.setString(AppConfig.guestUsernameKey, username);
    if (avatar != null) await p.setString('guest_avatar', avatar);
    await p.setString('guest_device_id', deviceId);
    await p.setBool('is_guest', true);
  }

  static Future<int?> getGuestUserId() async {
    final p = await _getPrefs();
    return p.getInt(AppConfig.guestUserIdKey);
  }

  static Future<String?> getGuestUsername() async {
    final p = await _getPrefs();
    return p.getString(AppConfig.guestUsernameKey);
  }

  static Future<bool> isGuest() async {
    final p = await _getPrefs();
    return p.getBool('is_guest') ?? false;
  }

  static Future<void> clearGuestUser() async {
    final p = await _getPrefs();
    await p.remove(AppConfig.guestUserIdKey);
    await p.remove(AppConfig.guestUsernameKey);
    await p.remove('guest_avatar');
    await p.remove('guest_device_id');
    await p.remove('is_guest');
  }

  // ==================== THEME & LANGUAGE ====================

  static Future<void> saveDarkMode(bool isDarkMode) async {
    final p = await _getPrefs();
    await p.setBool(AppConfig.darkModeKey, isDarkMode);
  }

  static Future<bool> getDarkMode() async {
    final p = await _getPrefs();
    return p.getBool(AppConfig.darkModeKey) ?? AppConfig.defaultDarkMode;
  }

  static Future<void> saveLanguage(String languageCode) async {
    final p = await _getPrefs();
    await p.setString(AppConfig.languageKey, languageCode);
  }

  static Future<String> getLanguage() async {
    final p = await _getPrefs();
    return p.getString(AppConfig.languageKey) ?? AppConfig.defaultLanguage;
  }

  // ==================== CLEAR ALL ====================

  static Future<void> clearAll() async {
    await _secure.deleteAll();
    final p = await _getPrefs();
    await p.clear();
  }
}
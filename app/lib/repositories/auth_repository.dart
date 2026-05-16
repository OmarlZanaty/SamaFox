// ============================================
// PHASE 1 - CORRECTED AUTH REPOSITORY
// ============================================
// File: lib/repositories/auth_repository.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'dart:io';
import '../services/api_service.dart';
import '../services/dio_client.dart';
import '../models/auth.dart';
import '../models/user.dart';
import '../utils/storage_service.dart';
import '../utils/result.dart';
import '../services/socket_service.dart';
import '../config/app_config.dart';

class AuthRepository {
  late final ApiService _apiService;
  late final GoogleSignIn _googleSignIn = _buildGoogleSignIn();

  AuthRepository() {
    _apiService = ApiService(DioClient.dio);
  }

  String _mapGoogleSignInError(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'sign_in_canceled':
          return 'Google Sign-In cancelled';
        case 'network_error':
          return 'Network error. Please check your connection and try again.';
        case 'sign_in_failed':
          return 'Google Sign-In failed. Please retry.';
      }
    }
    return error.toString();
  }

  GoogleSignIn _buildGoogleSignIn() {
    if (kIsWeb) {
      return GoogleSignIn(
        scopes: ['email', 'profile'],
        clientId: AppConfig.googleWebClientId,
      );
    }
    return GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: AppConfig.googleServerClientId,
    );
  }

  // ============================================
  // GUEST LOGIN
  // ============================================

  Future<Result<GuestLoginResponse>> guestLogin(String deviceId) async {
    try {
      print('🔐 [AUTH REPO] Guest login with device ID: $deviceId');
      final response = await _apiService.guestLogin(
        GuestLoginRequest(deviceId: deviceId),
      );
      await StorageService.saveAuthData(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );
      SocketService().updateToken(response.accessToken);
      await StorageService.saveGuestUser(
        userId: response.user.id,
        username: response.user.name,
        avatar: response.user.avatarUrl,
        deviceId: deviceId,
      );
      print('✅ [AUTH REPO] Guest login successful');
      return Result.success(response);
    } catch (e) {
      print('❌ [AUTH REPO] Guest login error: $e');
      return Result.error(e.toString());
    }
  }

  Future<User> getMe() async {
    return await _apiService.getCurrentUser();
  }

  // ============================================
  // EMAIL/PHONE LOGIN
  // ============================================

  Future<Result<AuthResponse>> login(String email, String password) async {
    try {
      print('🔐 [AUTH REPO] Logging in with email: $email');
      final response = await _apiService.login(
        LoginRequest(email: email, password: password),
      );
      await StorageService.saveAuthData(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );
      print('✅ [AUTH REPO] Login successful');
      return Result.success(response);
    } catch (e) {
      print('❌ [AUTH REPO] Login error: $e');
      return Result.error(e.toString());
    }
  }

  // ============================================
  // REGISTRATION
  // ============================================

  Future<Result<AuthResponse>> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    String? countryCode,
    String? country,
  }) async {
    try {
      print('📝 [AUTH REPO] Registering user: $name');
      if (gender != null &&
          !['male', 'female', 'other'].contains(gender.toLowerCase())) {
        return Result.error('Invalid gender');
      }
      final response = await _apiService.register(
        RegisterRequest(
          name: name,
          email: email,
          password: password,
          gender: gender?.toLowerCase(),
          countryCode: countryCode,
          country: country,
        ),
      );
      await StorageService.saveAuthData(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );
      print('✅ [AUTH REPO] Registration successful');
      return Result.success(response);
    } catch (e) {
      print('❌ [AUTH REPO] Registration error: $e');
      return Result.error(e.toString());
    }
  }

  // ============================================
  // DEVICE ID
  // ============================================

  Future<String> getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown';
      }
      return 'unknown';
    } catch (e) {
      print('❌ [AUTH REPO] Error getting device ID: $e');
      return 'unknown';
    }
  }

  // ============================================
  // AUTHENTICATION STATUS
  // ============================================

  Future<bool> isAuthenticated() async {
    return await StorageService.isAuthenticated();
  }

  Future<User?> getCurrentUser() async {
    return await StorageService.getCurrentUser();
  }

  Future<Result<User>> fetchCurrentUser() async {
    try {
      print('👤 [AUTH REPO] Fetching current user from API...');
      final user = await _apiService.getCurrentUser();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(user.toJson()));
      print('✅ [AUTH REPO] User fetched successfully');
      return Result.success(user);
    } catch (e) {
      print('❌ [AUTH REPO] Error fetching user: $e');
      return Result.error(e.toString());
    }
  }

  // ============================================
  // LOGOUT
  // ============================================

  Future<void> logout() async {
    try {
      print('🚪 [AUTH REPO] Logging out...');
      await StorageService.clearAuthData();
      await StorageService.clearGuestUser();
      print('✅ [AUTH REPO] Logged out successfully');
    } catch (e) {
      print('❌ [AUTH REPO] Logout error: $e');
    }
  }

  // ============================================
  // GOOGLE SIGN-IN
  // ============================================

  Future<Result<AuthResponse>> signInWithGoogle() async {
    try {
      print('🔐 [AUTH REPO] Starting Google Sign-In...');
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      GoogleSignInAccount? googleUser;
      try {
        googleUser = await _googleSignIn.signIn();
      } on PlatformException catch (e) {
        if (e.code == 'sign_in_failed') {
          print('⚠️ [AUTH REPO] sign_in_failed, trying disconnect + retry...');
          try {
            await _googleSignIn.disconnect();
          } catch (_) {}
          try {
            googleUser = await _googleSignIn.signIn();
          } catch (retryError) {
            print('❌ [AUTH REPO] Retry also failed: $retryError');
            return Result.error(_mapGoogleSignInError(retryError));
          }
        } else {
          rethrow;
        }
      }
      if (googleUser == null) {
        print('❌ [AUTH REPO] Google Sign-In cancelled by user');
        return Result.error('Google Sign-In cancelled');
      }
      print('✅ [AUTH REPO] Google user signed in: ${googleUser.email}');
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      if (idToken == null) {
        print('❌ [AUTH REPO] No ID token from Google');
        return Result.error('Failed to get Google ID token');
      }
      print('✅ [AUTH REPO] ID token received');
      final response = await _apiService.googleLogin(
        GoogleLoginRequest(idToken: idToken),
      );
      await StorageService.saveAuthData(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );
      print('✅ [AUTH REPO] Google Sign-In successful');
      return Result.success(response);
    } catch (e) {
      print('❌ [AUTH REPO] Google Sign-In error: $e');
      return Result.error(_mapGoogleSignInError(e));
    }
  }

  Future<void> signOutGoogle() async {
    try {
      print('🚪 [AUTH REPO] Signing out from Google...');
      await _googleSignIn.signOut();
      print('✅ [AUTH REPO] Signed out from Google');
    } catch (e) {
      print('❌ [AUTH REPO] Google sign-out error: $e');
    }
  }

  // ============================================
  // FACEBOOK SIGN-IN
  // ============================================

  Future<Result<AuthResponse>> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status != LoginStatus.success || result.accessToken == null) {
        return Result.error(result.message ?? 'فشل تسجيل الدخول عبر فيسبوك');
      }

      final String accessToken = result.accessToken!.token;

      // ✅ SEND TO YOUR BACKEND
      final response = await _apiService.facebookLogin(
        FacebookLoginRequest(facebookToken: accessToken),
      );

      await StorageService.saveAuthData(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );

      return Result.success(response);

    } catch (e) {
      return Result.error(e.toString());
    }
  }

  // ============================================
  // SNAPCHAT SIGN-IN
  // ============================================

  Future<Result<AuthResponse>> signInWithSnapchat() async {
    try {
      // 🔴 TODO: Implement Snapchat OAuth flow
      return Result.error('يرجى ربط الخادم (Backend) بتسجيل الدخول عبر سناب شات');
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  // ============================================
  // TOKEN REFRESH
  // ============================================

  Future<Result<AuthResponse>> refreshAccessToken() async {
    try {
      print('🔄 [AUTH REPO] Refreshing access token...');
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null) {
        print('❌ [AUTH REPO] No refresh token found');
        return Result.error('No refresh token available');
      }
      final response = await _apiService.refreshToken({'refreshToken': refreshToken});
      await StorageService.saveAuthData(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );
      print('✅ [AUTH REPO] Token refreshed successfully');
      return Result.success(response);
    } catch (e) {
      print('❌ [AUTH REPO] Token refresh error: $e');
      return Result.error(e.toString());
    }
  }

  // ============================================
  // PROFILE UPDATE
  // ============================================

  Future<Result<User>> updateProfile({
    String? name,
    String? bio,
    String? gender,
    String? countryCode,
    String? country,
    String? avatarUrl,
  }) async {
    try {
      print('✏️ [AUTH REPO] Updating profile...');
      if (gender != null &&
          !['male', 'female', 'other'].contains(gender.toLowerCase())) {
        return Result.error('Invalid gender');
      }
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (bio != null) data['bio'] = bio;
      if (gender != null) data['gender'] = gender.toLowerCase();
      if (countryCode != null) data['countryCode'] = countryCode;
      if (country != null) data['country'] = country;
      if (avatarUrl != null) data['avatarUrl'] = avatarUrl;
      final user = await _apiService.updateProfile(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(user.toJson()));
      print('✅ [AUTH REPO] Profile updated successfully');
      return Result.success(user);
    } catch (e) {
      print('❌ [AUTH REPO] Profile update error: $e');
      return Result.error(e.toString());
    }
  }

  Future<Result<User>> updateGenderAndCountry({
    required String gender,
    required String countryCode,
    String? country,
  }) async {
    try {
      print('🌍 [AUTH REPO] Updating gender and country...');
      if (!['male', 'female', 'other'].contains(gender.toLowerCase())) {
        return Result.error('Invalid gender');
      }
      final data = {
        'gender': gender.toLowerCase(),
        'countryCode': countryCode,
        if (country != null) 'country': country,
      };
      final user = await _apiService.updateProfile(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(user.toJson()));
      print('✅ [AUTH REPO] Gender and country updated');
      return Result.success(user);
    } catch (e) {
      print('❌ [AUTH REPO] Update error: $e');
      return Result.error(e.toString());
    }
  }

  // ============================================
  // USER SEARCH
  // ============================================

  Future<Result<List<User>>> searchUsers(String query) async {
    try {
      print('🔍 [AUTH REPO] Searching users: $query');
      final response = await _apiService.searchUsers(query);
      print('✅ [AUTH REPO] Search completed');
      return Result.success(response.users ?? []);
    } catch (e) {
      print('❌ [AUTH REPO] Search error: $e');
      return Result.error(e.toString());
    }
  }

  Future<Result<List<User>>> getUsersByCountry(String countryCode) async {
    try {
      print('🌍 [AUTH REPO] Fetching users from $countryCode...');
      final response = await _apiService.getUsersByCountry(countryCode);
      print('✅ [AUTH REPO] Users fetched');
      return Result.success(response.users ?? []);
    } catch (e) {
      print('❌ [AUTH REPO] Error: $e');
      return Result.error(e.toString());
    }
  }
} // ✅ AuthRepository class ends here
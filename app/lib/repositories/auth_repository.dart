// ============================================
// PHASE 1 - CORRECTED AUTH REPOSITORY
// ============================================
// File: lib/repositories/auth_repository.dart
// UPDATED VERSION - Integrates with existing code
// Replace your existing auth_repository.dart with this version

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
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: AppConfig.googleServerClientId,
  );


  AuthRepository() {
    _apiService = ApiService(DioClient.dio);
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

      // Save auth data
      await StorageService.saveAuthData(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        user: response.user,
      );

      SocketService().updateToken(response.accessToken);

      // Save guest user data
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

  /// Login with email and password
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
  // REGISTRATION (ENHANCED WITH GENDER/COUNTRY)
  // ============================================

  /// Register new user with optional gender and country
  Future<Result<AuthResponse>> register({
    required String name,
    required String email,
    required String password,
    String? gender, // NEW: "male", "female", "other"
    String? countryCode, // NEW: ISO code
    String? country, // NEW: Country name
  }) async {
    try {
      print('📝 [AUTH REPO] Registering user: $name');

      // Validate gender if provided
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

  /// Get unique device ID
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

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    return await StorageService.isAuthenticated();
  }

  /// Get current user from local storage
  Future<User?> getCurrentUser() async {
    return await StorageService.getCurrentUser();
  }

  /// Fetch current user from API (fresh data from backend)
  Future<Result<User>> fetchCurrentUser() async {
    try {
      print('👤 [AUTH REPO] Fetching current user from API...');

      final user = await _apiService.getCurrentUser();

      // Update local storage with fresh data
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

  /// Logout user
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
  // GOOGLE SIGN-IN (ENHANCED)
  // ============================================

  /// Google Sign-In - Enhanced with better error handling
  Future<Result<AuthResponse>> signInWithGoogle() async {
    try {
      print('🔐 [AUTH REPO] Starting Google Sign-In...');

      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print('❌ [AUTH REPO] Google Sign-In cancelled by user');
        return Result.error('Google Sign-In cancelled');
      }

      print('✅ [AUTH REPO] Google user signed in: ${googleUser.email}');

      // Get Google authentication
      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        print('❌ [AUTH REPO] No ID token from Google');
        return Result.error('Failed to get Google ID token');
      }

      print('✅ [AUTH REPO] ID token received');

      // Send to backend
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
      return Result.error(e.toString());
    }
  }

  /// Google Sign-Out
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
  // TOKEN REFRESH
  // ============================================

  /// Refresh access token
  Future<Result<AuthResponse>> refreshAccessToken() async {
    try {
      print('🔄 [AUTH REPO] Refreshing access token...');

      final refreshToken = await StorageService.getRefreshToken();

      if (refreshToken == null) {
        print('❌ [AUTH REPO] No refresh token found');
        return Result.error('No refresh token available');
      }

      // Call refresh endpoint
      final response = await _apiService.refreshToken({'refreshToken': refreshToken});

      // Update tokens
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
  // PROFILE UPDATE (NEW FOR PHASE 1)
  // ============================================

  /// Update user profile including gender and country
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

      // Validate gender if provided
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

      // Call update endpoint
      final user = await _apiService.updateProfile(data);

      // Update local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(user.toJson()));

      print('✅ [AUTH REPO] Profile updated successfully');

      return Result.success(user);
    } catch (e) {
      print('❌ [AUTH REPO] Profile update error: $e');
      return Result.error(e.toString());
    }
  }

  /// Update only gender and country
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

      // Update local storage
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
  // USER SEARCH (NEW FOR PHASE 1)
  // ============================================

  /// Search users by name or email
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

  /// Get users by country
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
}

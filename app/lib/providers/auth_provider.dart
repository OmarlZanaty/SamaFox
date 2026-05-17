import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../repositories/auth_repository.dart';
import '../services/socket_service.dart';
import '../utils/storage_service.dart';
/// Auth Repository Provider
final authRepositoryProvider = Provider((ref) => AuthRepository());

/// Auth State Provider
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider));
});

// ============================================
// AUTH STATE
// ============================================

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  /// clearUser=true allows setting user to null intentionally
  AuthState copyWith({
    User? user,
    bool clearUser = false,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

// ============================================
// AUTH NOTIFIER
// ============================================

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(AuthState()) {
    checkAuthStatus();
  }

  Future<void> _forceLogoutLocal({String? error}) async {
    // Clear stored session (tokens + user json + guest)
    await StorageService.clearTokens();
    await StorageService.clearAuthData();
    await StorageService.clearGuestUser();

    // Disconnect socket to avoid “still connected” behavior
    SocketService().disconnect();

    // Reset state
    state = state.copyWith(
      isLoading: false,
      isAuthenticated: false,
      clearUser: true,
      error: error,
    );
  }

  void updateCoinsBalance(int newBalance) {
    final current = state.user;
    if (current == null) return;
    state = state.copyWith(user: current.copyWith(coinsBalance: newBalance));
  }

  Future<void> checkAuthStatus() async {
    try {
      final isAuth = await _repository.isAuthenticated();
      if (!isAuth) {
        await _forceLogoutLocal();
        return;
      }

      final user = await _repository.getCurrentUser();

      final token = await StorageService.getAccessToken();
      if (token != null && token.isNotEmpty) {
        SocketService().connect(token);
      }

      state = state.copyWith(
        isAuthenticated: true,
        user: user,
      );
    } catch (e) {
      debugPrint('❌ [AUTH NOTIFIER] Error checking auth status: $e');
      // Don't leave the app in a half-initialised state — clear session on error.
      await _forceLogoutLocal(error: e.toString());
    }
  }



  /// Refresh user data from API
  Future<void> refreshUser() async {
    try {
      final result = await _repository.fetchCurrentUser();
      if (result.isSuccess && result.data != null) {
        // ✅ FIX: also persist to storage so frame survives app restart
        await StorageService.updateUser(result.data!);
        state = state.copyWith(user: result.data);
      }
    } catch (_) {}
  }

  /// Guest Login
  Future<void> guestLogin() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      isAuthenticated: false,
      clearUser: true,
    );

    try {
      final deviceId = await _repository.getDeviceId();
      final result = await _repository.guestLogin(deviceId);

      if (result.isSuccess && result.data != null) {
        await StorageService.saveAuthData(
          accessToken: result.data!.accessToken,
          refreshToken: result.data!.refreshToken,
          user: result.data!.user,
        );

        SocketService().connect(result.data!.accessToken);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: result.data!.user,
          error: null,
        );
      } else {
        await _forceLogoutLocal(error: result.error);
      }
    } catch (e) {
      await _forceLogoutLocal(error: e.toString());
    }
  }


  /// Email Login
  Future<void> login(String email, String password) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      isAuthenticated: false,
      clearUser: true,
    );

    try {
      final result = await _repository.login(email, password);

      if (result.isSuccess && result.data != null) {
        // ✅ token already saved inside AuthRepository.login()

        // ✅ connect socket using the token that is now persisted
        final token = await StorageService.getAccessToken();
        if (token != null && token.isNotEmpty) {
          SocketService().connect(token);
        }

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: result.data!.user,
          error: null,
        );
      } else {
        await _forceLogoutLocal(error: result.error);
      }
    } catch (e) {
      await _forceLogoutLocal(error: e.toString());
    }
  }
  /// Register
  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    String? countryCode,
    String? country,
  }) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      isAuthenticated: false,
      clearUser: true,
    );

    try {
      final result = await _repository.register(
        name: name,
        email: email,
        password: password,
        gender: gender,
        countryCode: countryCode,
        country: country,
      );

      if (result.isSuccess && result.data != null) {
        SocketService().connect(result.data!.accessToken);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: result.data!.user,
          error: null,
        );
      } else {
        await _forceLogoutLocal(error: result.error);
      }
    } catch (e) {
      await _forceLogoutLocal(error: e.toString());
    }
  }

  /// Logout
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      SocketService().disconnect(); // ✅ important
      await _repository.logout();
      await _repository.signOutGoogle();
      state = AuthState();
    } catch (e) {
      debugPrint('❌ [AUTH NOTIFIER] Logout error: $e');
      state = AuthState();
    }
  }

  Future<void> refreshMe() async {
    try {
      state = state.copyWith(isLoading: true);

      final user = await _repository.getMe();

      state = state.copyWith(
        user: user,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }




  /// Google Sign-In
  Future<void> signInWithGoogle() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      isAuthenticated: false,
      clearUser: true,
    );

    try {
      final result = await _repository.signInWithGoogle();

      if (result.isSuccess && result.data != null) {
        SocketService().connect(result.data!.accessToken);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: result.data!.user,
          error: null,
        );
      } else {
        await _forceLogoutLocal(error: result.error);
      }
    } catch (e) {
      await _forceLogoutLocal(error: e.toString());
    }
  }

  /// Update Profile
  Future<void> updateProfile({
    String? name,
    String? bio,
    String? gender,
    String? countryCode,
    String? country,
    String? avatarUrl,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.updateProfile(
        name: name,
        bio: bio,
        gender: gender,
        countryCode: countryCode,
        country: country,
        avatarUrl: avatarUrl,
      );

      if (result.isSuccess) {
        state = state.copyWith(isLoading: false, user: result.data);
      } else {
        state = state.copyWith(isLoading: false, error: result.error);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Facebook Sign-In
  Future<void> signInWithFacebook() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      isAuthenticated: false,
      clearUser: true,
    );

    try {
      final result = await _repository.signInWithFacebook();

      if (result.isSuccess && result.data != null) {
        SocketService().connect(result.data!.accessToken);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: result.data!.user,
          error: null,
        );
      } else {
        await _forceLogoutLocal(error: result.error);
      }
    } catch (e) {
      await _forceLogoutLocal(error: e.toString());
    }
  }

  /// Snapchat Sign-In (not yet implemented — shows error without touching auth state)
  Future<void> signInWithSnapchat() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.signInWithSnapchat();
      // Not yet implemented: just surface the error without clearing the session.
      state = state.copyWith(isLoading: false, error: result.error);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Update Gender and Country
  Future<void> updateGenderAndCountry({
    required String gender,
    required String countryCode,
    String? country,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.updateGenderAndCountry(
        gender: gender,
        countryCode: countryCode,
        country: country,
      );

      if (result.isSuccess) {
        state = state.copyWith(isLoading: false, user: result.data);
      } else {
        state = state.copyWith(isLoading: false, error: result.error);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Set user manually
  void setUser(User user) {
    state = state.copyWith(user: user, isAuthenticated: true);
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';

// ====================================================================
// Localization State Notifier
// ====================================================================

class LocalizationNotifier extends StateNotifier<Locale> {
  LocalizationNotifier(this._prefs) : super(const Locale('ar')) {
    _loadLocale();
  }

  final SharedPreferences _prefs;
  static const String _localeKey = 'app_locale';

  /// Load the saved locale from storage
  void _loadLocale() {
    final savedLocale = _prefs.getString(_localeKey);
    if (savedLocale != null) {
      state = Locale(savedLocale);
    } else {
      // Set Arabic as default if no saved locale
      state = const Locale('ar');
      _prefs.setString(_localeKey, 'ar');
    }
  }

  /// Change the app's locale and save it to storage
  Future<void> setLocale(Locale locale) async {
    if (state != locale) {
      state = locale;
      await _prefs.setString(_localeKey, locale.languageCode);
    }
  }

  /// Get the current AppStrings based on the locale
  AppStrings get strings {
    return state.languageCode == 'ar' ? AppStringsAr() : AppStringsEn();
  }
}

// ====================================================================
// SharedPreferences Provider
// ====================================================================

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

// ====================================================================
// Localization Provider
// ====================================================================

final localizationProvider = StateNotifierProvider<LocalizationNotifier, Locale>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LocalizationNotifier(prefs);
});

// ====================================================================
// AppStrings Provider
// ====================================================================

/// Provides easy access to the current language's strings
///
/// Usage:
/// final strings = ref.watch(appStringsProvider);
/// Text(strings.welcomeBack)
final appStringsProvider = Provider<AppStrings>((ref) {
  return ref.watch(localizationProvider.notifier).strings;
});

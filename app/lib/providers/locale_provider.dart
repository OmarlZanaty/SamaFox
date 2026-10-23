import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_strings.dart';
import '../l10n/tr.dart';
import '../utils/storage_service.dart';

/// Locale state class
class LocaleState {
  final Locale locale;
  final AppStrings strings;

  LocaleState({
    required this.locale,
    required this.strings,
  });

  LocaleState copyWith({
    Locale? locale,
    AppStrings? strings,
  }) {
    return LocaleState(
      locale: locale ?? this.locale,
      strings: strings ?? this.strings,
    );
  }
}

/// Locale provider for managing app language
class LocaleNotifier extends StateNotifier<LocaleState> {
  LocaleNotifier()
      : super(LocaleState(
    // Arabic until the saved choice loads — the app's default language.
    locale: const Locale('ar'),
    strings: AppStringsAr(),
  )) {
    _loadSavedLocale();
  }

  /// Load saved locale from storage
  Future<void> _loadSavedLocale() async {
    final savedLanguage = await StorageService.getLanguage();
    if (savedLanguage != null) {
      setLocale(savedLanguage);
    }
  }

  /// Set app locale
  Future<void> setLocale(String languageCode) async {
    final locale = Locale(languageCode);
    final strings = _getStringsForLocale(languageCode);

    final changed = AppLang.code != languageCode;
    AppLang.code = languageCode;
    state = LocaleState(
      locale: locale,
      strings: strings,
    );
    if (changed) rebuildAllWidgets();

    await StorageService.saveLanguage(languageCode);
  }

  /// Get strings for locale
  AppStrings _getStringsForLocale(String languageCode) {
    switch (languageCode) {
      case 'ar':
        return AppStringsAr();
      case 'en':
      default:
        return AppStringsEn();
    }
  }

  /// Toggle between English and Arabic
  Future<void> toggleLanguage() async {
    final newLanguage = state.locale.languageCode == 'en' ? 'ar' : 'en';
    await setLocale(newLanguage);
  }
}

/// Locale provider
final localeProvider = StateNotifierProvider<LocaleNotifier, LocaleState>((ref) {
  return LocaleNotifier();
});

/// Convenience provider for accessing strings directly
final stringsProvider = Provider<AppStrings>((ref) {
  return ref.watch(localeProvider).strings;
});

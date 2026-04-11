import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/storage_service.dart';

/// Theme mode provider for managing dark/light mode
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadSavedTheme();
  }

  /// Load saved theme from storage
  Future<void> _loadSavedTheme() async {
    final isDarkMode = await StorageService.getDarkMode();
    state = isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  /// Toggle between dark and light mode
  Future<void> toggleTheme() async {
    final isDark = state == ThemeMode.dark;
    state = isDark ? ThemeMode.light : ThemeMode.dark;
    await StorageService.saveDarkMode(!isDark);
  }

  /// Set specific theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await StorageService.saveDarkMode(mode == ThemeMode.dark);
  }

  /// Check if current theme is dark
  bool get isDarkMode => state == ThemeMode.dark;
}

/// Theme provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

/// Convenience provider for checking if dark mode is active
final isDarkModeProvider = Provider<bool>((ref) {
  return ref.watch(themeProvider) == ThemeMode.dark;
});

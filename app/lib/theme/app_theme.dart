import 'package:flutter/material.dart';

class AppTheme {
  // ==================== DARK MODE COLORS ====================
  static const Color primaryPurple = Color(0xFF6B4CE6);
  static const Color secondaryPink = Color(0xFFFF6B9D);
  static const Color secondaryBlue = Color(0xFF4ECDC4);
  static const Color backgroundDarkPurple = Color(0xFF1A0E3E);
  static const Color accentGold = Color(0xFFFFD700);
  static const Color accentGreen = Color(0xFF4CAF50);
  static const Color accentRed = Color(0xFFFF5252);
  static const Color darkCardBackground = Color(0xFF2A1A5E);
  static const lightPrimary = Color(0xFF00A3FF); // Bright blue


  // ==================== LIGHT MODE COLORS ====================
  // Extracted from the uploaded image
  static const Color lightPrimaryBlue = Color(0xFF00A3FF); // Bright blue
  static const Color lightBackgroundWhite = Color(0xFFFAFAFA); // Off-white background
  static const Color lightCardWhite = Color(0xFFFFFFFF); // Pure white cards
  static const Color lightAccentBlue = Color(0xFFE8F4FF); // Soft blue accent
  static const Color lightAccentBlueDark = Color(0xFFD0EBFF); // Darker blue accent
  static const Color lightTextPrimary = Color(0xFF1A1A1A); // Dark text
  static const Color lightTextSecondary = Color(0xFF6B7280); // Gray text
  static const Color lightBorderColor = Color(0xFFE5E7EB); // Light border
  static const Color lightShadowColor = Color(0x1A000000); // Subtle shadow

  // ==================== DEFAULT THEME MODE ====================
  static bool get defaultDarkMode => true; // Dark mode is default

  // ==================== DARK THEME ====================
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryPurple,
    scaffoldBackgroundColor: backgroundDarkPurple,
    colorScheme: const ColorScheme.dark(
      primary: primaryPurple,
      secondary: secondaryPink,
      tertiary: secondaryBlue,
      background: backgroundDarkPurple,
      surface: darkCardBackground,
      error: accentRed,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundDarkPurple,
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: darkCardBackground,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCardBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 2),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: backgroundDarkPurple,
      selectedItemColor: accentGold,
      unselectedItemColor: Colors.white54,
      type: BottomNavigationBarType.fixed,
    ),
  );

  // ==================== LIGHT THEME ====================
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: lightPrimaryBlue,
    scaffoldBackgroundColor: lightBackgroundWhite,
    colorScheme: const ColorScheme.light(
      primary: lightPrimaryBlue,
      secondary: lightAccentBlueDark,
      tertiary: lightAccentBlue,
      background: lightBackgroundWhite,
      surface: lightCardWhite,
      error: accentRed,
      onPrimary: Colors.white,
      onSecondary: lightTextPrimary,
      onBackground: lightTextPrimary,
      onSurface: lightTextPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightCardWhite,
      elevation: 0,
      centerTitle: true,
      foregroundColor: lightTextPrimary,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: lightCardWhite,
      elevation: 2,
      shadowColor: lightShadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(
          color: lightBorderColor,
          width: 1,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: lightPrimaryBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: lightPrimaryBlue,
        side: const BorderSide(color: lightPrimaryBlue, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightBackgroundWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightPrimaryBlue, width: 2),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightCardWhite,
      selectedItemColor: lightPrimaryBlue,
      unselectedItemColor: lightTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(
      color: lightBorderColor,
      thickness: 1,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.bold),
      displaySmall: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.bold),
      headlineLarge: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: lightTextPrimary),
      bodyMedium: TextStyle(color: lightTextPrimary),
      bodySmall: TextStyle(color: lightTextSecondary),
      labelLarge: TextStyle(color: lightTextPrimary, fontWeight: FontWeight.w500),
      labelMedium: TextStyle(color: lightTextSecondary),
      labelSmall: TextStyle(color: lightTextSecondary),
    ),
  );
}

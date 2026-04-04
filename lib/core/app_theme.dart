import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  static ThemeData getTheme(String themeName, bool isDark) {
    final colors = AppConstants.themes[themeName] ?? AppConstants.themes['Espo']!;
    final primary = colors['primary']!;
    final secondary = colors['secondary']!;
    
    if (isDark) {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: primary,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.dark(
          primary: secondary,
          secondary: secondary,
          surface: const Color(0xFF2C2C2C),
          background: const Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2C2C2C),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF2C2C2C),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: const Color(0xFF2C2C2C),
          selectedItemColor: secondary,
          unselectedItemColor: Colors.white54,
        ),
      );
    } else {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: primary,
        scaffoldBackgroundColor: AppConstants.backgroundColor,
        colorScheme: ColorScheme.light(
          primary: primary,
          secondary: secondary,
          surface: Colors.white,
          background: AppConstants.backgroundColor,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: primary,
          unselectedItemColor: Colors.grey,
        ),
      );
    }
  }

  // Backwards compatibility for main.dart
  static ThemeData get lightTheme => getTheme('Espo', false);
  static ThemeData get darkTheme => getTheme('Espo', true);
}

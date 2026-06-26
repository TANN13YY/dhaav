import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ── Dhaav Clean Color Palette ──────────────────────────────────────────────
/// Minimal: white, grey, black. Semantic accents only for RP, errors, territories.
abstract final class AppColors {
  // ── Semantic accents (theme-independent) ──────────────────────────────────
  static const Color gold = Color(0xFFFFAB00);
  static const Color errorRed = Color(0xFFFF1744);
  static const Color successGreen = Color(0xFF00E676);

  // ── Territory colors (theme-independent) ──────────────────────────────────
  static const Color territoryOwn = Color(0xFF00F0FF);   // Cyan — own territory
  static const Color territoryOther = Color(0xFFFF2D55);  // Red — others' territory
}

/// ── App Theme Data ─────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      cardColor: const Color(0xFFF2F2F2),
      dividerColor: const Color(0xFFE0E0E0),
      hintColor: const Color(0xFF9E9E9E),
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        secondary: Color(0xFF757575),
        surface: Colors.white,
        error: AppColors.errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.black,
        onError: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Color(0xFF9E9E9E),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      useMaterial3: true,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),
      dividerColor: const Color(0xFF2C2C2C),
      hintColor: const Color(0xFF9E9E9E),
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Color(0xFF9E9E9E),
        surface: Color(0xFF121212),
        error: AppColors.errorRed,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: Colors.white,
        onError: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        selectedItemColor: Colors.white,
        unselectedItemColor: Color(0xFF9E9E9E),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      useMaterial3: true,
    );
  }
}

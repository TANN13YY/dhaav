import 'package:flutter/material.dart';

/// ── Dhaav Neon-Cyber Color Palette ──────────────────────────────────────────
/// Vibrant, saturated colors only. No olive green. No muddy earth tones.
abstract final class AppColors {
  // ── Core brand colors ────────────────────────────────────────────────────
  static const Color radarCyan = Color(0xFF00F0FF);
  static const Color radarCyanDim = Color(0xFF007A82);
  static const Color crimson = Color(0xFFFF2D55);
  static const Color amber = Color(0xFFFFAB00);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color electricPurple = Color(0xFFBF40FF);

  // ── Surface / background ─────────────────────────────────────────────────
  static const Color surfaceDark = Color(0xFF0A0A0F);
  static const Color surfaceCard = Color(0x33141422);
  static const Color surfaceCardSolid = Color(0xFF141422);
  static const Color surfaceOverlay = Color(0xCC0A0A0F); // 80% opacity

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F0FF);
  static const Color textMuted = Color(0xFF6B7A8D);
  static const Color textCyanMuted = Color(0xFF4DCDD6);

  // ── Status / accents ─────────────────────────────────────────────────────
  static const Color successGreen = Color(0xFF00E676);
  static const Color warningOrange = Color(0xFFFF6D00);
  static const Color errorRed = Color(0xFFFF1744);

  // ── Gradients ────────────────────────────────────────────────────────────

  /// Crimson → Orange — used for wanted-level stars, danger elements
  static const LinearGradient crimsonToOrange = LinearGradient(
    colors: [Color(0xFFFF2D55), Color(0xFFFF6D00), Color(0xFFFFAB00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Purple → Violet — territory control, prestige elements
  static const LinearGradient purpleToViolet = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFBF40FF), Color(0xFFE040FB)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Cyan scan-line — HUD borders, radar sweep highlights
  static const LinearGradient cyanScanLine = LinearGradient(
    colors: [
      Color(0x0000F0FF),
      Color(0xFF00F0FF),
      Color(0xFF00F0FF),
      Color(0x0000F0FF),
    ],
    stops: [0.0, 0.35, 0.65, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Cyan → Violet border — login sheet, premium card borders
  static const LinearGradient cyanToViolet = LinearGradient(
    colors: [Color(0xFF00F0FF), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Shimmer gradient — used by the radar sweep ShaderMask
  static LinearGradient shimmerGradient(double position) {
    return LinearGradient(
      colors: const [
        Color(0x00FFFFFF),
        Color(0x33FFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [
        (position - 0.15).clamp(0.0, 1.0),
        position.clamp(0.0, 1.0),
        (position + 0.15).clamp(0.0, 1.0),
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }

  /// Create account / sign-up button gradient
  static const LinearGradient signUpButton = LinearGradient(
    colors: [Color(0xFFFF2D55), Color(0xFFFF6D00)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Log-in button gradient
  static const LinearGradient loginButton = LinearGradient(
    colors: [Color(0xFF00C9DB), Color(0xFF00F0FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

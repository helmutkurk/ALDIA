import 'package:flutter/material.dart';

/// Design tokens shared with the portal. See documentation/design-tokens.md.
class AldiaColors {
  const AldiaColors._();

  static const Color primary = Color(0xFF0F766E);
  static const Color primaryDark = Color(0xFF115E59);
  static const Color accent = Color(0xFFF59E0B);
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF1F5F9);
  static const Color text = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF475569);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AldiaColors.primary,
    primary: AldiaColors.primary,
    secondary: AldiaColors.accent,
    error: AldiaColors.danger,
    surface: AldiaColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AldiaColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AldiaColors.primary,
      foregroundColor: Colors.white,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AldiaColors.primary,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AldiaColors.primary,
        minimumSize: const Size.fromHeight(48),
      ),
    ),
  );
}

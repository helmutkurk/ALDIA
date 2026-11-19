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

/// Spacing scale (dp). Screens use these steps only.
class AldiaSpace {
  const AldiaSpace._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Minimum touch target.
  static const double target = 48;

  /// Room under scrolling content for the floating report button.
  static const double fabClearance = 88;
}

/// Light theme (default).
ThemeData buildTheme() => _build(Brightness.light);

/// Dark theme, derived from the same seed through [ColorScheme].
ThemeData buildDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AldiaColors.primary,
    brightness: brightness,
    primary: dark ? null : AldiaColors.primary,
    secondary: AldiaColors.accent,
    error: dark ? null : AldiaColors.danger,
    surface: dark ? null : AldiaColors.surface,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: dark ? scheme.surface : AldiaColors.background,
    // Type scale: four sizes carry the app (title, subtitle, body, caption).
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
      extendedTextStyle: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AldiaSpace.target),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AldiaSpace.target),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AldiaSpace.target, AldiaSpace.target),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

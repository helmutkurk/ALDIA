import 'package:flutter/material.dart';

/// Design tokens shared with the portal. See documentation/design-tokens.md.
class AldiaColors {
  const AldiaColors._();

  static const Color primary = Color(0xFF1F2937);
  static const Color primaryDark = Color(0xFF111827);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F5F4);
  static const Color border = Color(0xFFE5E7EB);
  static const Color text = Color(0xFF111827);
  static const Color textMuted = Color(0xFF4B5563);
  static const Color focus = Color(0xFF111827);

  // Functional colors only. Status text sits on an opaque surface: closed
  // passes 4.5:1 on white, but not on the warm-gray page background.
  static const Color open = Color(0xFFB45309);
  static const Color inWork = Color(0xFF4B5563);
  static const Color success = Color(0xFF15803D);
  static const Color closed = Color(0xFF6B7280);
  static const Color danger = Color(0xFFB91C1C);

  static const Color darkBackground = Color(0xFF1C1C1B);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkContainer = Color(0xFF30343B);
  static const Color darkTextMuted = Color(0xFFD1D5DB);
  static const Color darkOpen = Color(0xFFD6B391);
  static const Color darkInWork = Color(0xFFB9C1CC);
  static const Color darkSuccess = Color(0xFFA3C4AA);
  static const Color darkClosed = Color(0xFFB6B8BC);
  static const Color darkDanger = Color(0xFFDCA7A7);
  static const Color darkErrorContainer = Color(0xFF492A2A);
  static const Color lightErrorContainer = Color(0xFFFEE2E2);

  /// Use together with the citizen/verifier word and icon, never color alone.
  static Color status(String? state, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (state) {
      'resuelto' || 'verified' => dark ? darkSuccess : success,
      'rechazado_verificador' || 'rejected' => dark ? darkDanger : danger,
      'programado' || 'en_proceso' => dark ? darkInWork : inWork,
      'no_procede' ||
      'fuera_de_competencia' ||
      'duplicado' ||
      'oculto' => dark ? darkClosed : closed,
      _ => dark ? darkOpen : open,
    };
  }
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

/// Dark theme: inverted neutral surfaces/text and legible muted status colors.
ThemeData buildDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  // Explicit roles prevent seed-generated brand hues in Material components.
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? AldiaColors.border : AldiaColors.primary,
    onPrimary: dark ? AldiaColors.primary : AldiaColors.onPrimary,
    primaryContainer: dark ? AldiaColors.primary : AldiaColors.border,
    onPrimaryContainer: dark ? AldiaColors.surface : AldiaColors.text,
    secondary: dark ? AldiaColors.darkTextMuted : AldiaColors.textMuted,
    onSecondary: dark ? AldiaColors.text : AldiaColors.surface,
    secondaryContainer: dark ? AldiaColors.primary : AldiaColors.border,
    onSecondaryContainer: dark ? AldiaColors.surface : AldiaColors.text,
    tertiary: dark ? AldiaColors.darkTextMuted : AldiaColors.textMuted,
    onTertiary: dark ? AldiaColors.text : AldiaColors.surface,
    tertiaryContainer: dark ? AldiaColors.primary : AldiaColors.border,
    onTertiaryContainer: dark ? AldiaColors.surface : AldiaColors.text,
    error: dark ? AldiaColors.darkDanger : AldiaColors.danger,
    onError: dark ? AldiaColors.text : AldiaColors.surface,
    errorContainer: dark
        ? AldiaColors.darkErrorContainer
        : AldiaColors.lightErrorContainer,
    onErrorContainer: dark ? AldiaColors.surface : AldiaColors.danger,
    surface: dark ? AldiaColors.darkSurface : AldiaColors.surface,
    onSurface: dark ? AldiaColors.surface : AldiaColors.text,
    onSurfaceVariant: dark ? AldiaColors.darkTextMuted : AldiaColors.textMuted,
    surfaceDim: dark ? AldiaColors.darkSurface : AldiaColors.border,
    surfaceBright: dark ? AldiaColors.darkContainer : AldiaColors.surface,
    surfaceContainerLowest: dark
        ? AldiaColors.darkSurface
        : AldiaColors.surface,
    surfaceContainerLow: dark
        ? AldiaColors.darkSurface
        : AldiaColors.background,
    surfaceContainer: dark ? AldiaColors.primary : AldiaColors.background,
    surfaceContainerHigh: dark ? AldiaColors.primary : AldiaColors.border,
    surfaceContainerHighest: dark
        ? AldiaColors.darkContainer
        : AldiaColors.border,
    outline: dark ? AldiaColors.darkInWork : AldiaColors.textMuted,
    outlineVariant: dark ? AldiaColors.textMuted : AldiaColors.border,
    inverseSurface: dark ? AldiaColors.background : AldiaColors.primary,
    onInverseSurface: dark ? AldiaColors.text : AldiaColors.surface,
    inversePrimary: dark ? AldiaColors.primary : AldiaColors.border,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? AldiaColors.darkBackground
        : AldiaColors.background,
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
      labelTextStyle: WidgetStatePropertyAll(
        text.labelMedium?.copyWith(color: scheme.onSurface),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
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
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AldiaSpace.target, AldiaSpace.target),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: dark ? AldiaColors.border : AldiaColors.focus,
          width: 2,
        ),
      ),
    ),
  );
}

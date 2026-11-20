import 'package:flutter/material.dart';

/// Design tokens shared with the portal. See documentation/design-tokens.md.
///
/// Status colors paint dots and pins only. The status word is always set in
/// the normal text color beside the dot (never color alone, 4.5:1 for text).
class AldiaColors {
  const AldiaColors._();

  // Light tokens.
  static const Color bar = Color(0xFF3A3F44);
  static const Color onBar = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF0F7A99);
  static const Color primaryDark = Color(0xFF0B6079);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFE8731A);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFD9DEE3);
  static const Color text = Color(0xFF1F2933);
  static const Color textMuted = Color(0xFF52606D);
  static const Color focus = Color(0xFF0B6079);
  static const Color primaryContainer = Color(0xFFD6EEF5);
  static const Color onPrimaryContainer = Color(0xFF0B4458);

  // Status dot and pin colors (documentation/design-tokens.md).
  static const Color open = Color(0xFFE8731A);
  static const Color inWork = Color(0xFF3F9A47);
  static const Color resolved = Color(0xFF2D8CD0);
  static const Color closed = Color(0xFF6B7280);
  static const Color danger = Color(0xFFB91C1C);
  static const Color lightErrorContainer = Color(0xFFFDE8E8);

  // Dark mode keeps the hues on darker surfaces.
  static const Color darkBar = Color(0xFF23292E);
  static const Color darkBackground = Color(0xFF12181D);
  static const Color darkSurface = Color(0xFF1B2329);
  static const Color darkContainer = Color(0xFF26313A);
  static const Color darkBorder = Color(0xFF313C45);
  static const Color darkText = Color(0xFFF3F4F6);
  static const Color darkTextMuted = Color(0xFFC5CDD5);
  static const Color darkPrimary = Color(0xFF4FB8D6);
  static const Color darkOnPrimary = Color(0xFF0B2630);
  static const Color darkClosed = Color(0xFF9CA3AF);
  static const Color darkDanger = Color(0xFFF2A5A5);
  static const Color darkErrorContainer = Color(0xFF4A2323);

  /// Dot or pin color for a citizen or verifier state. Pending states are
  /// drawn hollow by [statusIsHollow]. Use together with the word.
  static Color status(String? state, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (state) {
      'resuelto' => resolved,
      'verified' || 'programado' || 'en_proceso' => inWork,
      'rechazado_verificador' || 'rejected' => dark ? darkDanger : danger,
      'pendiente_verificacion' || 'pending' => dark ? darkTextMuted : textMuted,
      'no_procede' ||
      'fuera_de_competencia' ||
      'duplicado' ||
      'oculto' => dark ? darkClosed : closed,
      _ => open,
    };
  }

  /// Pending verification is an outlined (hollow) dot instead of a fill.
  static bool statusIsHollow(String? state) =>
      state == 'pendiente_verificacion' || state == 'pending';

  static Color barOfBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? darkBar : bar;

  /// Dark top bar color for the current theme.
  static Color barOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkBar : bar;
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
  const c = AldiaColors.border;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? AldiaColors.darkPrimary : AldiaColors.primary,
    onPrimary: dark ? AldiaColors.darkOnPrimary : AldiaColors.onPrimary,
    primaryContainer: dark
        ? AldiaColors.onPrimaryContainer
        : AldiaColors.primaryContainer,
    onPrimaryContainer: dark
        ? AldiaColors.primaryContainer
        : AldiaColors.onPrimaryContainer,
    secondary: dark ? AldiaColors.darkTextMuted : AldiaColors.textMuted,
    onSecondary: dark ? AldiaColors.darkOnPrimary : AldiaColors.surface,
    secondaryContainer: dark ? AldiaColors.darkContainer : c,
    onSecondaryContainer: dark ? AldiaColors.darkText : AldiaColors.text,
    tertiary: dark ? AldiaColors.darkPrimary : AldiaColors.primaryDark,
    onTertiary: dark ? AldiaColors.darkOnPrimary : AldiaColors.surface,
    tertiaryContainer: dark
        ? AldiaColors.onPrimaryContainer
        : AldiaColors.primaryContainer,
    onTertiaryContainer: dark
        ? AldiaColors.primaryContainer
        : AldiaColors.onPrimaryContainer,
    error: dark ? AldiaColors.darkDanger : AldiaColors.danger,
    onError: dark ? AldiaColors.darkOnPrimary : AldiaColors.surface,
    errorContainer: dark
        ? AldiaColors.darkErrorContainer
        : AldiaColors.lightErrorContainer,
    onErrorContainer: dark ? const Color(0xFFFBD5D5) : AldiaColors.danger,
    surface: dark ? AldiaColors.darkSurface : AldiaColors.surface,
    onSurface: dark ? AldiaColors.darkText : AldiaColors.text,
    onSurfaceVariant: dark ? AldiaColors.darkTextMuted : AldiaColors.textMuted,
    surfaceDim: dark ? AldiaColors.darkBackground : c,
    surfaceBright: dark ? AldiaColors.darkContainer : AldiaColors.surface,
    surfaceContainerLowest: dark
        ? AldiaColors.darkSurface
        : AldiaColors.surface,
    surfaceContainerLow: dark
        ? AldiaColors.darkSurface
        : AldiaColors.background,
    surfaceContainer: dark ? AldiaColors.darkContainer : AldiaColors.background,
    surfaceContainerHigh: dark ? AldiaColors.darkContainer : c,
    surfaceContainerHighest: dark ? AldiaColors.darkBorder : c,
    outline: dark ? AldiaColors.darkTextMuted : AldiaColors.textMuted,
    outlineVariant: dark ? AldiaColors.darkBorder : c,
    inverseSurface: dark ? AldiaColors.border : AldiaColors.text,
    onInverseSurface: dark ? AldiaColors.text : AldiaColors.background,
    inversePrimary: dark ? AldiaColors.primaryDark : const Color(0xFF7CCBE3),
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme;
  final linkColor = dark ? AldiaColors.darkPrimary : AldiaColors.primaryDark;
  const radius = 12.0;
  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? AldiaColors.darkBackground
        : AldiaColors.background,
    // Type hierarchy: headline, title, body, caption; bold only for titles.
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    splashFactory: InkRipple.splashFactory,
    focusColor: scheme.primary.withValues(alpha: 0.16),
    // Default app bar: sheet header (white). Explorar and the shell use the
    // dark `bar` through [AldiaColors.barOf].
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      titleTextStyle: text.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: AldiaColors.accent,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.labelLarge?.copyWith(letterSpacing: 1),
      unselectedLabelStyle: text.labelLarge?.copyWith(letterSpacing: 1),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
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
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    // Full-width teal-blue primary button; darker when pressed.
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(AldiaSpace.target),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return null;
              if (states.contains(WidgetState.pressed)) {
                return dark ? AldiaColors.primary : AldiaColors.primaryDark;
              }
              return scheme.primary;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return null;
              if (states.contains(WidgetState.pressed) && dark) {
                return AldiaColors.onPrimary;
              }
              return scheme.onPrimary;
            }),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AldiaSpace.target),
        foregroundColor: linkColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AldiaSpace.target, AldiaSpace.target),
        foregroundColor: linkColor,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(AldiaSpace.target, AldiaSpace.target),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: dark ? AldiaColors.darkPrimary : AldiaColors.focus,
          width: 2,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.outlineVariant,
    ),
  );
}

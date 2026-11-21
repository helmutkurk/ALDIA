import 'dart:math' as math;

import 'package:aldia_app/core/citizen_states.dart';
import 'package:aldia_app/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// WCAG relative luminance: linearize sRGB, then weight its three channels.
double _luminance(Color color) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

double _contrast(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  test('WCAG formula has the reference black/white ratio', () {
    expect(_contrast(Colors.black, Colors.white), closeTo(21, 0.0001));
    expect(_contrast(Colors.white, Colors.black), closeTo(21, 0.0001));
    expect(_contrast(Colors.white, Colors.white), 1);
  });

  test('light palette matches the approved Guatemala sky-blue tokens', () {
    final theme = buildTheme();
    final scheme = theme.colorScheme;
    expect(AldiaColors.bar, const Color(0xFF235E8F));
    expect(AldiaColors.brand, const Color(0xFF4997D0));
    expect(AldiaColors.accent, const Color(0xFFFF7A59));
    expect(scheme.primary, const Color(0xFF2A6FA8));
    expect(scheme.onPrimary, Colors.white);
    expect(scheme.surface, Colors.white);
    expect(scheme.surfaceContainerLow, const Color(0xFFEAF4FB));
    expect(theme.scaffoldBackgroundColor, Colors.white);
    expect(scheme.outlineVariant, const Color(0xFFC5D9E8));
    expect(scheme.onSurface, const Color(0xFF1F2933));
    expect(scheme.onSurfaceVariant, const Color(0xFF52606D));
    expect(theme.tabBarTheme.indicatorColor, AldiaColors.accent);
    for (final (state, color) in [
      ('nuevo', const Color(0xFFB26A00)),
      ('en_revision', const Color(0xFFB26A00)),
      ('programado', const Color(0xFF7E57C2)),
      ('en_proceso', const Color(0xFF7E57C2)),
      ('resuelto', const Color(0xFF17735A)),
      ('no_procede', const Color(0xFF6B7280)),
      ('rechazado_verificador', const Color(0xFFB91C1C)),
    ]) {
      expect(AldiaColors.status(state, Brightness.light), color, reason: state);
    }
    expect(AldiaColors.statusIsHollow('pendiente_verificacion'), isTrue);
    expect(AldiaColors.statusIsHollow('nuevo'), isFalse);
  });

  test('buttons and chips are pills; cards use the large radius', () {
    final theme = buildTheme();
    expect(
      theme.filledButtonTheme.style!.shape!.resolve({}),
      isA<StadiumBorder>(),
    );
    expect(
      theme.outlinedButtonTheme.style!.shape!.resolve({}),
      isA<StadiumBorder>(),
    );
    expect(theme.chipTheme.shape, isA<StadiumBorder>());
    final card = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(card.borderRadius, BorderRadius.circular(AldiaRadius.card));
  });

  for (final theme in [buildTheme(), buildDarkTheme()]) {
    test('${theme.brightness.name} text token pairs meet 4.5:1', () {
      final s = theme.colorScheme;
      final pairs = <String, (Color, Color)>{
        'button': (s.onPrimary, s.primary),
        'tonal button / selected tab': (
          s.onSecondaryContainer,
          s.secondaryContainer,
        ),
        'primary container': (s.onPrimaryContainer, s.primaryContainer),
        'secondary': (s.onSecondary, s.secondary),
        'tertiary': (s.onTertiary, s.tertiary),
        'tertiary container': (s.onTertiaryContainer, s.tertiaryContainer),
        'error badge': (s.onError, s.error),
        'error container': (s.onErrorContainer, s.errorContainer),
        'snackbar': (s.onInverseSurface, s.inverseSurface),
        'snackbar action': (s.inversePrimary, s.inverseSurface),
        'cluster pin': (AldiaColors.onPrimary, AldiaColors.primary),
        'pressed action': (AldiaColors.onPrimary, AldiaColors.primaryDark),
        'top bar': (
          AldiaColors.onBar,
          AldiaColors.barOfBrightness(theme.brightness),
        ),
        'tab label on bar': (
          AldiaColors.onBarMuted,
          AldiaColors.barOfBrightness(theme.brightness),
        ),
        'text on coral': (AldiaColors.onAccent, AldiaColors.accent),
        'text on dark coral': (AldiaColors.onAccent, AldiaColors.darkAccent),
        'fab': (
          theme.floatingActionButtonTheme.foregroundColor!,
          theme.floatingActionButtonTheme.backgroundColor!,
        ),
        'pin letter': (AldiaColors.text, Colors.white),
        for (final background in [
          theme.scaffoldBackgroundColor,
          s.surface,
          s.surfaceDim,
          s.surfaceBright,
          s.surfaceContainerLowest,
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ]) ...{
          'body on $background': (s.onSurface, background),
          'secondary text on $background': (s.onSurfaceVariant, background),
          'text button on $background': (
            theme.textButtonTheme.style!.foregroundColor!.resolve({})!,
            background,
          ),
          'error on $background': (s.error, background),
        },
      };
      for (final entry in pairs.entries) {
        final (foreground, background) = entry.value;
        expect(foreground.a, 1, reason: entry.key);
        expect(background.a, 1, reason: entry.key);
        final ratio = _contrast(foreground, background);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  }

  for (final theme in [buildTheme(), buildDarkTheme()]) {
    test('${theme.brightness.name} status dots are visible (3:1 non-text)', () {
      for (final state in [
        ...citizenStates.keys,
        'pending',
        'verified',
        'rejected',
        null,
        'unknown',
      ]) {
        final dot = AldiaColors.status(state, theme.brightness);
        for (final background in [
          theme.colorScheme.surface,
          theme.colorScheme.surfaceContainerLow,
        ]) {
          final ratio = _contrast(dot, background);
          expect(ratio, greaterThanOrEqualTo(3), reason: '$state $ratio');
        }
      }
    });
  }
}

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Meaning of a [AldiaBanner]; the icon and the words carry it, the
/// background only supports it.
enum BannerKind { info, warning, error }

/// Rounded message box with an icon and wrapping text (design-direction §8).
/// Use for notices inside screens; snackbars stay for short confirmations.
class AldiaBanner extends StatelessWidget {
  const AldiaBanner(
    this.text, {
    super.key,
    this.kind = BannerKind.info,
    this.icon,
  });

  final String text;
  final BannerKind kind;

  /// Overrides the default icon of [kind].
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final (background, iconColor, defaultIcon) = switch (kind) {
      BannerKind.info => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.info_outline,
      ),
      BannerKind.warning => (
        dark ? AldiaColors.darkWarningContainer : AldiaColors.warningContainer,
        dark ? AldiaColors.darkOpen : AldiaColors.open,
        Icons.warning_amber_rounded,
      ),
      BannerKind.error => (
        scheme.errorContainer,
        scheme.error,
        Icons.error_outline,
      ),
    };
    final textColor = kind == BannerKind.info
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Semantics(
      container: true,
      liveRegion: kind == BannerKind.error,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AldiaRadius.input),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AldiaSpace.l,
            vertical: AldiaSpace.m,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(icon ?? defaultIcon, color: iconColor),
              ),
              const SizedBox(width: AldiaSpace.m),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

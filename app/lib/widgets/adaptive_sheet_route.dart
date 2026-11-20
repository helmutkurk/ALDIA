import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

import 'routes.dart';

extension WidgetX on Widget {
  /// A modern sheet: glass on iOS, the package's plain sheet elsewhere, and
  /// an instant page when the system asks to reduce motion.
  ///
  /// The content gets a transparent [Material] so text fields and ink work
  /// inside it. The glass sheet paints its own surface; the plain sheet gets
  /// the theme surface through [SheetBackground], as the package recommends.
  Route<T> asAdaptiveSheetRoute<T>({bool reduceMotion = false}) {
    final Widget content = Material(
      type: MaterialType.transparency,
      child: this,
    );

    if (reduceMotion) {
      return AldiaRoute<T>(
        builder: (context) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(child: this),
        ),
        reduceMotion: true,
      );
    }

    final bool isIos = defaultTargetPlatform == TargetPlatform.iOS;

    if (isIos) {
      return StupidSimpleGlassSheetRoute<T>(
        child: content,
        blurBehindBarrier: false,
      );
    } else {
      return StupidSimpleSheetRoute<T>(
        child: SafeArea(
          // Only the top inset belongs to the route; the content handles the
          // bottom itself.
          bottom: false,
          left: false,
          right: false,
          child: SheetBackground(child: content),
        ),
      );
    }
  }
}

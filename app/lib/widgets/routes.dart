import 'package:flutter/material.dart';

/// Page route that skips its transition when the system asks to reduce motion.
class AldiaRoute<T> extends MaterialPageRoute<T> {
  AldiaRoute({required super.builder, required this.reduceMotion});

  /// Pushes [page] on the nearest navigator, honoring reduced motion.
  static Future<T?> open<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(
        AldiaRoute<T>(
          builder: (_) => page,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
        ),
      );

  final bool reduceMotion;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : super.reverseTransitionDuration;
}

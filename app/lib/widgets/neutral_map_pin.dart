import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Same graphite fill for every state; the child carries its icon or count.
/// A light outline separates the marker from the map in either theme.
class NeutralMapPin extends StatelessWidget {
  const NeutralMapPin({super.key, required this.child, this.size = 40});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AldiaColors.primary,
      shape: BoxShape.circle,
      border: Border.all(color: AldiaColors.onPrimary, width: 2),
    ),
    alignment: Alignment.center,
    child: IconTheme.merge(
      data: const IconThemeData(color: AldiaColors.onPrimary, size: 22),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          color: AldiaColors.onPrimary,
          fontWeight: FontWeight.bold,
        ),
        child: child,
      ),
    ),
  );
}

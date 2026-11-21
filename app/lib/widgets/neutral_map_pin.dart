import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Same primary fill for every state; the child carries its icon or count.
/// A white outline separates the marker from the map in either theme.
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

/// Report pin: disc in the status color with a white outline and the
/// category icon in the middle. The state word is shown by the caller below
/// the pin and announced in its semantics (never color alone).
class StatusMapPin extends StatelessWidget {
  const StatusMapPin({
    super.key,
    required this.state,
    required this.icon,
    this.size = 40,
  });

  final String? state;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AldiaColors.status(state, brightness);
    final hollow = AldiaColors.statusIsHollow(state);
    // White on the light status colors; dark ink on the lighter dark-mode ones.
    final ink = hollow
        ? color
        : brightness == Brightness.dark
        ? AldiaColors.darkSurface
        : Colors.white;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hollow ? Colors.white : color,
        shape: BoxShape.circle,
        border: Border.all(color: hollow ? color : Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
      ),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        child: Icon(icon, size: size * 0.5, color: ink),
      ),
    );
  }
}

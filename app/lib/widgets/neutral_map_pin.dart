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

/// Report pin: disc in the status color with a white outline and a white
/// center holding the state letter (text color on white, 4.5:1). The state
/// word is announced by the caller's semantics and shown in the label below.
class StatusMapPin extends StatelessWidget {
  const StatusMapPin({
    super.key,
    required this.state,
    required this.letter,
    this.size = 40,
  });

  final String? state;
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AldiaColors.status(state, Theme.of(context).brightness);
    final hollow = AldiaColors.statusIsHollow(state);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hollow ? Colors.white : color,
        shape: BoxShape.circle,
        border: Border.all(color: hollow ? color : Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3)],
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.56,
        height: size * 0.56,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            color: AldiaColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

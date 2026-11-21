import 'package:flutter/widgets.dart';

/// Breathing room at the end of a scrollable: as tall as the bottom system
/// bar, or [minimum] when the device has none.
class BottomPadding extends StatelessWidget {
  const BottomPadding({super.key});

  static double of(BuildContext context, {double minimum = 16}) {
    // Get size of the bottom system bar
    final double viewPadding = MediaQuery.viewPaddingOf(context).bottom;

    // Use the system bar size if it's bigger than the minimum,
    // otherwise fall back to the minimum.
    final double height = viewPadding > minimum ? viewPadding : minimum;

    return height;
  }

  @override
  Widget build(BuildContext context) {
    final double height = of(context);

    // Return a box of that height.
    return SizedBox(height: height);
  }
}

# Fix: The map layers sheet slides in mechanically and can't be flung away

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/smooth-draggable-bottom-sheets
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

The "Capas del mapa" sheet, opened from the map in Explorar and in Reportar's location step, opens and closes with Material's fixed, mechanical motion. A spring-driven sheet keeps the speed of the citizen's fling and settles naturally, and dragging it moves the sheet directly under the finger.

## Where

Material's `showModalBottomSheet` opens the small, non-scrolling layers sheet:

```dart
// lib/widgets/map_layers_button.dart:1-58 — current (whole build)
import 'package:flutter/material.dart';

/// The street base stays visible; the citizen can toggle the data overlay.
class MapLayersButton extends StatelessWidget {
  const MapLayersButton({
    super.key,
    required this.overlay,
    required this.visible,
    required this.onChanged,
  });
  final String overlay;
  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Capas del mapa',
    icon: const Icon(Icons.layers_outlined),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
```

The sheet's look today comes from the theme: surface color, 16 rounded top corners and a drag handle (`lib/core/theme.dart:304-311`).

## The fix

The article's `showSpringBottomSheet` and `SpringSheetRoute`, as a new file `lib/widgets/spring_bottom_sheet.dart`. Three adaptations to this app:

- `SheetContainer` uses the theme's sheet color (`colorScheme.surface`), the theme's 16 corner radius and a drag handle, so it looks like today's sheets instead of the article's hard-coded white.
- When the system asks to reduce motion, `showSpringBottomSheet` falls back to the current `showModalBottomSheet` with no animation, as the app does today.
- The dot shorthands are written out (`MaterialType.transparency`, `BorderRadius.vertical`) to match this codebase.

The article says not to put a scrollable inside a spring sheet, because it steals the drag. The layers sheet is short (a title and two rows), so its `SingleChildScrollView` is removed.

New file `lib/widgets/spring_bottom_sheet.dart`, exactly:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Shows a modal sheet anchored to the bottom edge of the screen.
///
/// A spring-driven replacement for showModalBottomSheet. The sheet enters
/// and exits on smooth springs, and dragging it drives the route animation
/// directly, so the velocity of a released fling is carried into the open
/// or close spring.
///
/// For small sheets that don't scroll: build the content on a Column with
/// mainAxisSize: MainAxisSize.min, and don't put a scrollable inside.
///
/// The sheet surface comes from [SheetContainer]; the widget returned by
/// [builder] brings only its content and padding. With reduced motion the
/// plain Material sheet is shown without animation.
///
/// Returns a [Future] that resolves to the value passed to [Navigator.pop]
/// when the sheet is closed.
Future<T?> showSpringBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return showModalBottomSheet<T>(
      context: context,
      sheetAnimationStyle: AnimationStyle.noAnimation,
      builder: builder,
    );
  }

  return Navigator.of(context).push(
    SpringSheetRoute<T>(
      builder: builder,
    ),
  );
}

/// A route that shows a spring-driven modal sheet at the bottom of the
/// screen.
class SpringSheetRoute<T> extends PopupRoute<T> {
  SpringSheetRoute({
    required this.builder,
    super.settings,
  });

  /// Builds the content of the sheet.
  final WidgetBuilder builder;

  // SwiftUI's .smooth spring written out as plain numbers: critically
  // damped, stiffness 4pi^2 / duration^2, at 300ms in and 200ms out.
  static const SpringDescription _enterSpring = SpringDescription(
    mass: 1,
    stiffness: 438.6,
    damping: 41.9,
  );
  static const SpringDescription _exitSpring = SpringDescription(
    mass: 1,
    stiffness: 987.0,
    damping: 62.8,
  );

  // Resistance applied when dragging past fully open.
  static const double _overdragResistance = 100;

  // Thresholds past which a released drag closes the sheet: fling speed in
  // sheet heights per second, or resting position as a fraction of height.
  static const double _closeVelocity = 0.9;
  static const double _closePosition = 0.5;

  // Release velocity in sheet heights per second (positive is downward),
  // carried from the drag into the close simulation.
  double? _releaseVelocity;

  bool _popped = false;

  @override
  Color? get barrierColor => const Color(0x8A000000);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  // The scrim fades with the clamped animation so that dragging past fully
  // open does not push the barrier curve out of range. The slide reads the
  // raw controller.
  @override
  Animation<double>? get animation {
    final Animation<double>? raw = super.animation;
    if (raw == null) return null;

    return _ClampedAnimation(raw);
  }

  @override
  AnimationController createAnimationController() {
    return AnimationController.unbounded(
      duration: transitionDuration,
      reverseDuration: reverseTransitionDuration,
      vsync: navigator!,
    );
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    final double velocity = _releaseVelocity ?? 0;
    _releaseVelocity = null;

    return SpringSimulation(
      forward ? _enterSpring : _exitSpring,
      controller?.value ?? 0,
      forward ? 1 : 0,
      -velocity,
      snapToEnd: true,
    );
  }

  @override
  bool didPop(T? result) {
    _popped = true;

    return super.didPop(result);
  }

  void _dragBy(double relativeDelta) {
    if (_popped) return;

    final AnimationController controller = this.controller!;

    double delta = relativeDelta;
    if (controller.value > 1) {
      final double overshoot = controller.value - 1;
      delta *= 1 / (1 + overshoot * _overdragResistance);
    }
    controller.value -= delta;
  }

  void _endDrag(double relativeVelocity) {
    if (_popped) return;
    final AnimationController controller = this.controller!;
    final double value = controller.value;

    if (value > 1) {
      // Dragged past fully open. Settle back, damping the velocity by the
      // same resistance that was applied while dragging.
      final double overshoot = value - 1;
      final double damped =
          relativeVelocity / (1 + overshoot * _overdragResistance);
      controller.animateWith(
        SpringSimulation(_enterSpring, value, 1, -damped, snapToEnd: true),
      );

      return;
    }

    final bool close = switch (relativeVelocity) {
      > _closeVelocity => true,
      < -_closeVelocity => false,
      _ => value < _closePosition,
    };

    if (close) {
      _releaseVelocity = relativeVelocity;
      navigator?.pop();
    } else {
      controller.animateWith(
        SpringSimulation(
          _enterSpring,
          value,
          1,
          -relativeVelocity,
          snapToEnd: true,
        ),
      );
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: controller!,
        builder: (context, child) {
          return FractionalTranslation(
            translation: Offset(0, 1 - controller!.value),
            child: child,
          );
        },
        child: Builder(
          builder: (context) {
            // Drag deltas are normalized by the sheet's own height, so the
            // gesture and the route animation share one coordinate space.
            double height() => context.size?.height ?? 1;

            return GestureDetector(
              excludeFromSemantics: true,
              onVerticalDragUpdate: (details) {
                _dragBy(details.primaryDelta! / height());
              },
              onVerticalDragEnd: (details) {
                _endDrag(details.velocity.pixelsPerSecond.dy / height());
              },
              onVerticalDragCancel: () {
                _endDrag(0);
              },
              child: SizedBox(
                width: double.infinity,
                child: SheetContainer(
                  child: builder(context),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The surface for sheets shown with [showSpringBottomSheet]: the theme's
/// sheet color, 16 rounded top corners and a drag handle, matching the
/// bottom sheet theme in lib/core/theme.dart.
class SheetContainer extends StatelessWidget {
  const SheetContainer({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
        child: ColoredBox(
          color: cs.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// An animation that forwards [parent] with its value clamped to the range
/// 0.0 to 1.0, for consumers such as the modal barrier that should not see
/// values past fully open.
class _ClampedAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _ClampedAnimation(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value => parent.value.clamp(0.0, 1.0);
}
```

Target in `lib/widgets/map_layers_button.dart` (from `onPressed:` to the end of `Column(`'s opening; the `children:` list stays as it is):

```dart
    onPressed: () => showSpringBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
```

## Steps

1. Create `lib/widgets/spring_bottom_sheet.dart` with the exact content from "The fix".
2. `lib/widgets/map_layers_button.dart`:
   - Add `import 'spring_bottom_sheet.dart';` after `import 'package:flutter/material.dart';`.
   - Replace `onPressed: () => showModalBottomSheet<void>(` with `onPressed: () => showSpringBottomSheet<void>(`.
   - Delete the three `sheetAnimationStyle:` lines (`sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)`, `? AnimationStyle.noAnimation`, `: null,`); `showSpringBottomSheet` handles reduced motion itself.
   - Replace `builder: (context) => SafeArea(` with `builder: (context) => SafeArea(` followed by `top: false,` on the next line.
   - Remove the `SingleChildScrollView(` wrapper: delete the line `child: SingleChildScrollView(`, change the following `child: Padding(` to stay as the `SafeArea`'s `child:`, and delete one matching closing `),` near the end of the method: after the `],` that closes `children:`, the file now has five `),` lines before `);`; it must have four.
   - If another plan already turned `onPressed:` into a block (`onPressed: () { FocusManager...; showModalBottomSheet<void>(...); }`) or added a haptic call, keep that shape and make the same replacements inside it.
3. Run `mise exec -- dart format lib/widgets/spring_bottom_sheet.dart lib/widgets/map_layers_button.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "showModalBottomSheet" lib/widgets/map_layers_button.dart` → 0
4. `grep -c "showSpringBottomSheet<void>(" lib/widgets/map_layers_button.dart` → 1
5. `grep -c "SingleChildScrollView" lib/widgets/map_layers_button.dart` → 0
6. `grep -c "class SpringSheetRoute" lib/widgets/spring_bottom_sheet.dart` → 1

## Don't touch

- The report summary sheet from map pins (`home_screen.dart:788-821`): it holds a full report card with a 190-tall photo, and at large text it needs to scroll, so it isn't a small non-scrolling sheet.
- The filters sheet (`home_screen.dart:130-143`) and the phone login sheet (`login_sheet.dart:10-17`): they open with `isScrollControlled: true` as tall sheets and have their own plan.
- `bottomSheetTheme` in `lib/core/theme.dart`: the remaining Material sheets still use it.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed this button (an unfocus call, a haptic call, an import). That's expected; keep those changes.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the "Capas del mapa" sheet now opens and closes on a smooth spring, follows the finger when dragged, and closes when flung down, keeping the same look (surface color, rounded top, drag handle). With reduced motion it opens instantly as before. To see it, open Explorar → MAPA, tap the layers button, and fling the sheet down.

# Fix: The Linux desktop build animates pages like a phone

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/web-page-transitions
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

The app has a `linux/` desktop target. There, opening a report's detail or the report flow plays the mobile zoom transition, which looks cheap on a click-and-open desktop. Pages on desktop (and on web, if a web target is added later) should switch with no transition, while Android and iOS keep their native transitions.

## Where

The theme has no `pageTransitionsTheme` and nothing checks for web or desktop:

```dart
// lib/core/theme.dart:171-172 — current (inside base.copyWith( in _build)
    splashFactory: InkRipple.splashFactory,
    focusColor: scheme.primary.withValues(alpha: 0.16),
```

```dart
// lib/core/theme.dart:1 — current
import 'package:flutter/material.dart';
```

Every push goes through the theme: `AldiaRoute` (`lib/widgets/routes.dart`) extends `MaterialPageRoute`, and `report_flow_screen.dart:976` uses a plain `MaterialPageRoute`. Both read their transition and its duration from `pageTransitionsTheme`.

## The fix

The article's theme, with one adaptation: Android and iOS keep the builders Flutter uses today. In the installed Flutter 3.47 those defaults are `PredictiveBackPageTransitionsBuilder` (Android) and `CupertinoPageTransitionsBuilder` (iOS); the article's `ZoomPageTransitionsBuilder` would change the Android animation, which isn't the goal.

Add at the end of `lib/core/theme.dart`:

```dart
/// Native page transitions on Android and iOS (also in a mobile browser),
/// none on web and desktop, where pages are click and open.
const PageTransitionsTheme appPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: kIsWeb
        ? _NoPageTransitionsBuilder()
        : PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.iOS: kIsWeb
        ? _NoPageTransitionsBuilder()
        : CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: _NoPageTransitionsBuilder(),
    TargetPlatform.windows: _NoPageTransitionsBuilder(),
    TargetPlatform.linux: _NoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: _NoPageTransitionsBuilder(),
  },
);

class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
```

And assign it in `_build`:

```dart
    splashFactory: InkRipple.splashFactory,
    focusColor: scheme.primary.withValues(alpha: 0.16),
    pageTransitionsTheme: appPageTransitionsTheme,
```

## Steps

1. Before editing, confirm the mobile defaults: run `grep -n "_defaultBuilders" -A8 "$(dirname "$(dirname "$(readlink -f "$(mise exec -- which flutter)")")")/packages/flutter/lib/src/material/page_transitions_theme.dart"`. The output must list `TargetPlatform.android: PredictiveBackPageTransitionsBuilder()` and `TargetPlatform.iOS: CupertinoPageTransitionsBuilder()`. If the Flutter version lists different builders, use those two instead in the `kIsWeb ? ... : <builder>` branches.
2. In `lib/core/theme.dart`, add `import 'package:flutter/foundation.dart';` above `import 'package:flutter/material.dart';` (for `kIsWeb`).
3. In `lib/core/theme.dart`, inside `base.copyWith(` in `_build`, add `    pageTransitionsTheme: appPageTransitionsTheme,` right after `    focusColor: scheme.primary.withValues(alpha: 0.16),`. If another plan already added `textSelectionTheme:` there, put this line after that block.
4. Append the `appPageTransitionsTheme` constant and the `_NoPageTransitionsBuilder` class from "The fix" at the end of `lib/core/theme.dart`.
5. Run `mise exec -- dart format lib/core/theme.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!` (If it says `foundation.dart` is an unnecessary import, remove that import and run it again.)
2. `mise exec -- flutter test` → all tests pass (widget tests run as Android, so they keep the native transition).
3. `grep -c "pageTransitionsTheme: appPageTransitionsTheme" lib/core/theme.dart` → 1
4. `grep -c "class _NoPageTransitionsBuilder" lib/core/theme.dart` → 1

## Don't touch

- `AldiaRoute` in `lib/widgets/routes.dart`: it already reads the duration from the theme through `MaterialPageRoute`, and its reduce-motion override still wins.
- Bottom sheets and dialogs: they aren't page transitions.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added other lines to the same `copyWith(` (for example `textSelectionTheme:`). That's expected; keep them.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: on the Linux desktop build (and any future web or desktop build), pages now switch instantly with no mobile slide or zoom, while Android and iOS keep their native transitions. To see it, run `flutter run -d linux` and open a report's detail.

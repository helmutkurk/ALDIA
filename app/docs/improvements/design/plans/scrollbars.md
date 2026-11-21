# Fix: Long pages show no scrollbar on phones

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/scrollbars
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

On Android and iOS, Aldia's long pages (Lista, Mis reportes, Avisos, Perfil, the report detail and the report flow) show no scrollbar, so citizens can't tell where they are or how much is left. Flutter adds scrollbars automatically only on desktop. One app-wide setting adds them on phones too, without doubling them on desktop.

## Where

No scrollable is wrapped in `Scrollbar` and there's no `scrollBehavior` override (`grep -rnE "scrollBehavior|MaterialScrollBehavior|Scrollbar" lib` returns nothing). For example:

```dart
// lib/features/detail/report_detail_screen.dart:90 — current (one of many)
    return ListView(
```

The app-wide place for the fix:

```dart
// lib/app.dart:116-121 — current
      child: MaterialApp(
        title: S.appName,
        theme: buildTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
```

## The fix

The article's automatic approach: a scroll behavior whose `buildScrollbar` always wraps in a `Scrollbar`, set once on `MaterialApp`. It replaces Flutter's desktop-only scrollbar instead of adding a second one, and widgets that shouldn't have a scrollbar (single-line text fields, `PageView`, dropdowns) already opt out locally.

New file `lib/widgets/always_scrollbar_behavior.dart`, exactly:

```dart
import 'package:flutter/material.dart';

/// Scrollbars on every platform, not only desktop.
class AlwaysScrollbarBehavior extends MaterialScrollBehavior {
  const AlwaysScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      child: child,
    );
  }
}
```

Target in `lib/app.dart`:

```dart
      child: MaterialApp(
        title: S.appName,
        theme: buildTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        scrollBehavior: const AlwaysScrollbarBehavior(),
        debugShowCheckedModeBanner: false,
```

## Steps

1. Create `lib/widgets/always_scrollbar_behavior.dart` with the exact content from "The fix".
2. `lib/app.dart`: add `import 'widgets/always_scrollbar_behavior.dart';` after `import 'services/photo_service.dart';`. Add `scrollBehavior: const AlwaysScrollbarBehavior(),` right after `themeMode: ThemeMode.system,`.
3. Run `mise exec -- dart format lib/widgets/always_scrollbar_behavior.dart lib/app.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "scrollBehavior: const AlwaysScrollbarBehavior()" lib/app.dart` → 1
4. `grep -c "Scrollbar(" lib/widgets/always_scrollbar_behavior.dart` → 1

## Don't touch

- Don't wrap individual lists in `Scrollbar` as well: with the app-wide behavior, a second one clashes with it and both misbehave.
- The onboarding `PageView` and the map: they opt out or don't scroll.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added other arguments to `MaterialApp(` (for example `builder:`). That's expected; keep them.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: every vertical list in the app now shows a thin scrollbar while scrolling on phones too, so citizens can see where they are and how much is left; desktop keeps a single scrollbar as before. To see it, scroll Mis reportes or a report's detail on Android.

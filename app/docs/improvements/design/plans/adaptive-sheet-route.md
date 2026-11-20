# Fix: The login and filters sheets slide up mechanically

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/adaptive-sheet-route
- **Needs new dependency**: `stupid_simple_sheet`, which gives modern, fully rounded sheets that close with a pull down from the top (a glass sheet on iOS, a plain one on Android). The project rules (AGENTS.md) say to ask before adding a dependency, so get the developer's OK first.

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

The phone login ("Verificar mi número" in Perfil) and the Explorar filters open as tall bottom sheets with `showModalBottomSheet(isScrollControlled: true)`, which just slides up mechanically. A modern sheet route makes them smooth: rounded on all corners, following the finger, closing with a pull down from the top.

## Where

Every tall bottom modal:

```dart
// lib/features/citizen/login_sheet.dart:10-17 — current
Future<bool> showCitizenLogin(BuildContext context, AuthService auth) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CitizenLoginSheet(auth: auth),
    ) ??
    false;
```

```dart
// lib/features/home/home_screen.dart:130-136 — current
  Future<void> _editFilters() async {
    final result = await showModalBottomSheet<(String?, String?)>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(context),
      builder: (_) => _FiltersSheet(state: _state, category: _category),
    );
```

Both sheet bodies pop their result with `Navigator.pop(context, value)` (`login_sheet.dart:116` and `:258`, `home_screen.dart:579` and `:583`), so they work the same inside any route. Neither body paints its own background or provides a `Material` (the login's text fields need one); today the bottom sheet supplies both.

## The fix

The article's `asAdaptiveSheetRoute()` extension, as a new file `lib/widgets/adaptive_sheet_route.dart`: the glass sheet on iOS, the package's plain sheet on Android. One adaptation: when the system asks to reduce motion, it returns the app's existing `AldiaRoute` with no transition (`lib/widgets/routes.dart`), because the app honors reduced motion everywhere.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

import 'routes.dart';

extension WidgetX on Widget {
  /// A modern sheet: glass on iOS, the package's plain sheet elsewhere, and
  /// an instant page when the system asks to reduce motion.
  Route<T> asAdaptiveSheetRoute<T>({bool reduceMotion = false}) {
    if (reduceMotion) {
      return AldiaRoute<T>(builder: (_) => this, reduceMotion: true);
    }

    final bool isIos = defaultTargetPlatform == TargetPlatform.iOS;

    if (isIos) {
      return StupidSimpleGlassSheetRoute<T>(
        child: this,
        blurBehindBarrier: false,
      );
    } else {
      return StupidSimpleSheetRoute<T>(
        child: this,
      );
    }
  }
}
```

Each sheet body is wrapped in a `Material` with the theme's surface color, so it keeps its background and the text fields keep their `Material` ancestor.

```dart
// target — lib/features/citizen/login_sheet.dart
Future<bool> showCitizenLogin(BuildContext context, AuthService auth) async =>
    await Navigator.of(context).push<bool>(
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          bottom: false,
          child: CitizenLoginSheet(auth: auth),
        ),
      ).asAdaptiveSheetRoute<bool>(
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
    ) ??
    false;
```

```dart
// target — lib/features/home/home_screen.dart
  Future<void> _editFilters() async {
    final result = await Navigator.of(context).push<(String?, String?)>(
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: _FiltersSheet(state: _state, category: _category),
      ).asAdaptiveSheetRoute<(String?, String?)>(
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
    );
```

(`_FiltersSheet` already wraps its content in a `SafeArea`; the login sheet had `useSafeArea: true`, which is why it gets `SafeArea(bottom: false)` here.)

## Steps

1. Ask the developer to approve `stupid_simple_sheet`. If they say no, STOP.
2. Run `mise exec -- flutter pub add stupid_simple_sheet` (without mise: `flutter pub add stupid_simple_sheet`). Don't edit `pubspec.lock` by hand.
3. Open the package's `README.md` in the pub cache (`ls ~/.pub-cache/hosted/pub.dev | grep stupid_simple_sheet`) and confirm that `StupidSimpleSheetRoute` and `StupidSimpleGlassSheetRoute` exist, take a `child:`, and that the glass route takes `blurBehindBarrier:`. If any of that differs, STOP.
4. Create `lib/widgets/adaptive_sheet_route.dart` with the exact content from "The fix".
5. `lib/features/citizen/login_sheet.dart`: add `import '../../widgets/adaptive_sheet_route.dart';` after `import '../../services/identity_services.dart';`. Replace the `showCitizenLogin` function quoted in "Where" with the login target.
6. `lib/features/home/home_screen.dart`: add `import '../../widgets/adaptive_sheet_route.dart';` after `import '../../widgets/routes.dart';`. In `_editFilters`, replace the `final result = await showModalBottomSheet<(String?, String?)>( ... );` statement with the one from the home target. Keep any line another plan added above it (for example the unfocus call).
7. Run `mise exec -- dart format lib/widgets/adaptive_sheet_route.dart lib/features/citizen/login_sheet.dart lib/features/home/home_screen.dart`.
8. Run the app on Android (and iOS, if available), open Perfil → "Verificar mi número" and Explorar → filters, and confirm each sheet has a visible background, rounded corners and closes with a pull down. If the package already paints its own background and the `Material` shows square corners over it, report it instead of changing the code.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!` (`_sheetStyle` is still used by `_showSummary`, so it isn't unused.)
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "isScrollControlled" lib/features/citizen/login_sheet.dart` → 0
4. `grep -c "isScrollControlled" lib/features/home/home_screen.dart` → 0
5. `grep -c "asAdaptiveSheetRoute<bool>(" lib/features/citizen/login_sheet.dart` → 1
6. `grep -c "asAdaptiveSheetRoute<(String?, String?)>(" lib/features/home/home_screen.dart` → 1

## Don't touch

- `CitizenLoginSheet` and `_FiltersSheet` themselves: they keep popping their results as before.
- The full-screen login at app start (`CitizenLoginScreen`): it's a page, not a modal.
- The small sheets (map layers, report summary): they aren't full-screen modals.
- The article's tip to put a close (X) at the top left of full-screen modals: not part of this plan; the login already has "Cerrar" and the filters have "Aplicar" and "Quitar filtros".
- No new dependencies beyond `stupid_simple_sheet`.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed nearby lines (an unfocus call at the top of `_editFilters`, a haptic call, an import). That's expected; keep those changes.
- Step 3 shows a different API.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the phone login sheet and the Explorar filters now open as modern sheets (a glass sheet on iOS, a rounded sheet on Android) that follow the finger and close with a pull down from the top; with reduced motion they open instantly. To see it, open Perfil → "Verificar mi número".

# Fix: Text selection and the cursor use Flutter's default colors, not Aldia's

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/selection-color
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

When citizens type an address, a note or their phone number, the cursor, the selection highlight and the selection handles use Flutter's default tint instead of Aldia's primary color. Setting them once in the theme makes every field match the app.

## Where

The theme sets no `textSelectionTheme` (`grep -rn textSelectionTheme lib` returns nothing). Text fields exist in `lib/features/citizen/login_sheet.dart`, `lib/features/report/report_flow_screen.dart` and `lib/features/home/home_screen.dart`. The fix goes in the shared theme:

```dart
// lib/core/theme.dart:171-172 — current
    splashFactory: InkRipple.splashFactory,
    focusColor: scheme.primary.withValues(alpha: 0.16),
```

## The fix

Add `textSelectionTheme` to the `ThemeData` built in `_build`, using the scheme's primary color (the same token the focus ring already uses), so light and dark themes each get their own:

```dart
// target
    splashFactory: InkRipple.splashFactory,
    focusColor: scheme.primary.withValues(alpha: 0.16),
    // Selection sits behind text, so it gets opacity; cursor and handles are
    // small and stay at full color.
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: scheme.primary.withValues(alpha: 0.3),
      selectionHandleColor: scheme.primary,
      cursorColor: scheme.primary,
    ),
```

## Steps

1. In `lib/core/theme.dart`, inside `base.copyWith(` in `_build`, insert the four `textSelectionTheme` lines (with the comment) from "The fix" right after `    focusColor: scheme.primary.withValues(alpha: 0.16),`.
2. Run `mise exec -- dart format lib/core/theme.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "textSelectionTheme: TextSelectionThemeData(" lib/core/theme.dart` → 1

## Don't touch

- The search field in Home's dark app bar (`home_screen.dart:236-250`) sets `cursorColor: AldiaColors.onBar` on purpose, because the bar is dark. Leave it.
- The color tokens in `AldiaColors`: no new colors.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added other lines to the same `copyWith(` (for example `pageTransitionsTheme:`). That's expected; keep them.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the cursor, text selection and selection handles in every text field now use Aldia's primary color, in both light and dark mode. To see it, open "Reportar", type in "Buscar dirección" and long-press a word.

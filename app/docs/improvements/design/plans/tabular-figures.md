# Fix: The resend countdown jitters as its digits change

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/tabular-figures
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

After requesting a login code, the "Reenviar en 60 s" button counts down every second. In most fonts a `1` is narrower than an `8`, so the button text shifts left and right as the seconds change. Tabular figures give every digit the same width, so the countdown stays still.

## Where

`tabularFigures` isn't used anywhere (`grep -rn tabularFigures lib` returns nothing). The only number that changes on screen:

```dart
// lib/features/citizen/login_sheet.dart:231-236 — current
            TextButton(
              onPressed: _busy || _seconds > 0 ? null : _request,
              child: Text(
                _seconds > 0 ? 'Reenviar en $_seconds s' : 'Reenviar código',
              ),
            ),
```

## The fix

The article's font feature on the countdown text:

```dart
// target
            TextButton(
              onPressed: _busy || _seconds > 0 ? null : _request,
              child: Text(
                _seconds > 0 ? 'Reenviar en $_seconds s' : 'Reenviar código',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
```

The style only adds the font feature; color, size and weight still come from the button theme.

## Steps

1. In `lib/features/citizen/login_sheet.dart`, replace the `TextButton(` block quoted in "Where" with the target.
2. Run `mise exec -- dart format lib/features/citizen/login_sheet.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!` If it says `FontFeature` isn't defined, add `import 'dart:ui' show FontFeature;` after `import 'dart:async';` in that file and run it again.
2. `mise exec -- flutter test` → all tests pass (the login test still finds `'Reenviar en 60 s'`).
3. `grep -c "FontFeature.tabularFigures()" lib/features/citizen/login_sheet.dart` → 1

## Don't touch

- Numbers that don't change while shown, such as the resolved count on Inicio and the cluster pins: they don't jitter.
- The countdown logic in `_cooldown()`.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed nearby lines in this file. That's expected; keep those changes.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the "Reenviar en N s" countdown on the phone login now keeps every digit the same width, so the text stays still while it counts down. To see it, request a code and watch the resend button.

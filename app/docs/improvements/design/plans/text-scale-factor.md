# Fix: Nothing limits how far the system text size can scale the app

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/text-scale-factor
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

> **Read this first.** This plan conflicts with a written project requirement.
> `documentation/prompts/job-app-ui-parity.md` says to "keep … text scale 2.0
> safety", `documentation/log/omarchy.md` records the login sheet tested "at
> 390px and 200% text", and `test/widgets/large_text_test.dart` checks
> screens at large text. The app already adapts to large text (for example,
> the navigation bar grows when text is scaled, `home_screen.dart:327`).
> Capping text at 1.1× would take that larger text away from the citizens who
> need it. **Before Step 1, ask the developer (and Helmut, who owns the design
> decisions) to confirm in writing that they want the cap. If they don't, STOP
> and don't change anything.**

## Why

Some citizens raise their phone's text size for accessibility, and at very high scales layouts can overflow. The article's fix doesn't ignore the user's setting; it caps it app-wide at 1.1×, so text still grows a little but layouts stay intact. After the fix, run the app at the capped scale to confirm nothing breaks.

## Where

Nothing limits `textScaler` app-wide: there's no `builder:` on `MaterialApp`, and the only `textScaler` uses are per-widget opt-outs on map pins (`neutral_map_pin.dart:75`, `home_screen.dart:996` and `:1031`).

```dart
// lib/app.dart:116-129 — current
      child: MaterialApp(
        title: S.appName,
        theme: buildTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es', 'GT'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es', 'GT'), Locale('es')],
        home: _onboarding
```

## The fix

The article's `MaterialApp.builder`, which clamps the system text scale at 1.1× for the whole app:

```dart
// target — insert after supportedLocales
        supportedLocales: const [Locale('es', 'GT'), Locale('es')],
        builder: (context, child) {
          final MediaQueryData mediaQueryData = MediaQuery.of(context);

          return MediaQuery(
            data: mediaQueryData.copyWith(
              textScaler: mediaQueryData.textScaler.clamp(
                maxScaleFactor: 1.1,
              ),
            ),
            child: child!,
          );
        },
        home: _onboarding
```

## Steps

1. Confirm the developer approved the cap in writing (see "Read this first"). If not, STOP.
2. In `lib/app.dart`, insert the `builder:` block from the target right after `supportedLocales: const [Locale('es', 'GT'), Locale('es')],` and before `home: _onboarding`.
3. Run `mise exec -- dart format lib/app.dart`.
4. Run the app on a phone or emulator with the system font size at its maximum and open Inicio, Explorar (MAPA and LISTA), Reportar (every step), Mis reportes, Avisos, Perfil and the phone login. Note any overflow (yellow-black stripes) or cut-off text.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass. (`large_text_test.dart` builds its own `MaterialApp` without `AldiaApp`, so it still tests 2.0× and is unaffected.)
3. `grep -c "maxScaleFactor: 1.1" lib/app.dart` → 1

## Don't touch

- The per-widget `TextScaler.noScaling` on map pins: they have fixed-size markers.
- The navigation bar height logic at `home_screen.dart:327` and the large-text tests: leave them as they are, even if they now rarely trigger in the real app.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The developer hasn't approved the cap in writing.
- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added other arguments to `MaterialApp(` (for example `scrollBehavior:`). That's expected; keep them.
- `MaterialApp(` already has a `builder:` (added by someone else): merge the clamp into it instead of adding a second one, and report that you did.
- Step 4 shows an overflow: report the screens instead of changing layouts.
- A check fails twice.

## When you're done

Tell the developer: the app now follows the phone's text size up to 1.1× and stops there, so layouts can't overflow at extreme sizes. Also say plainly that citizens who set larger text now get at most 1.1×, which goes against the 2.0× text requirement in the project docs. To see it, set the phone's font size to maximum and open Perfil.

# Fix: Tapping the current bottom tab again does nothing

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/bottom-nav-reselect
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

Native app users expect that tapping the bottom tab they're already on scrolls that page back to the top. In Aldia, tapping Inicio, Avisos, Mis reportes or Perfil a second time does nothing, so a citizen deep in a long list has to swipe all the way back up.

## Where

The tap handler has no same-tab branch:

```dart
// lib/features/home/home_screen.dart:331-344 — current
        onDestinationSelected: (i) {
          final tab = _Tab.values[i];
          if (tab == _Tab.report) {
            unawaited(_startReport());
            return;
          }
          setState(() {
            _tab = tab;
            _visited.add(tab);
          });
          if (tab == _Tab.notices || tab == _Tab.mine) {
            unawaited(_observeMine());
          }
        },
```

The scrollables behind each tab, none with a controller:

```dart
// lib/features/home/home_screen.dart:396-398 — current (Inicio, landing)
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AldiaSpace.xl),
```

```dart
// lib/features/home/home_screen.dart:662-663 — current (Inicio → Explorar → LISTA)
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
```

```dart
// lib/features/citizen/citizen_screens.dart:47-49 — current (Avisos)
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AldiaSpace.l),
```

```dart
// lib/features/mine/my_reports_screen.dart:124-125 — current (Mis reportes)
              return ListView(
                padding: const EdgeInsets.fromLTRB(
```

```dart
// lib/features/citizen/citizen_screens.dart:212-213 — current (Perfil)
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(AldiaSpace.xl),
```

## The fix

The article's pattern: one stored `ScrollController` per tab page, and a reselect branch in the tap handler that scrolls the current page to the top. In Inicio, the landing page and the Explorar list never show at the same time, so each gets its own controller and the branch picks the one on screen. The Reportar tab opens the report flow and has no page, so it's left out. Aldia has no always-present search field, so the article's optional "focus search when already at top" step doesn't apply. The scroll honors the system's reduce-motion setting like the rest of the app (`MediaQuery.disableAnimationsOf`).

New file `lib/features/home/bottom_navigation_reselect.dart`, exactly:

```dart
import 'package:flutter/material.dart';

/// Scroll controllers for the pages behind the bottom navigation, so tapping
/// the tab that is already selected scrolls its page back to the top.
///
/// They live as long as the app, because the bottom navigation is always on
/// screen. Never dispose them while a page uses them.
class BottomNavigationReselect {
  BottomNavigationReselect._();

  static final ScrollController landingScrollController = ScrollController();
  static final ScrollController exploreListScrollController =
      ScrollController();
  static final ScrollController noticesScrollController = ScrollController();
  static final ScrollController mineScrollController = ScrollController();
  static final ScrollController profileScrollController = ScrollController();

  /// Scrolls [scroller] to the top, instantly when motion is reduced.
  static void scrollToTop(
    ScrollController scroller, {
    required bool reduceMotion,
  }) {
    final bool atTop = !scroller.hasClients || scroller.offset <= 0;
    if (atTop) return;

    if (reduceMotion) {
      scroller.jumpTo(0);
      return;
    }

    scroller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}
```

Target tap handler:

```dart
        onDestinationSelected: (i) {
          final tab = _Tab.values[i];
          if (tab == _Tab.report) {
            unawaited(_startReport());
            return;
          }
          if (tab == _tab) {
            BottomNavigationReselect.scrollToTop(
              switch (tab) {
                _Tab.home =>
                  _exploring
                      ? BottomNavigationReselect.exploreListScrollController
                      : BottomNavigationReselect.landingScrollController,
                _Tab.notices => BottomNavigationReselect.noticesScrollController,
                _Tab.mine => BottomNavigationReselect.mineScrollController,
                _ => BottomNavigationReselect.profileScrollController,
              },
              reduceMotion: MediaQuery.disableAnimationsOf(context),
            );
            return;
          }
          setState(() {
            _tab = tab;
            _visited.add(tab);
          });
          if (tab == _Tab.notices || tab == _Tab.mine) {
            unawaited(_observeMine());
          }
        },
```

## Steps

1. Create `lib/features/home/bottom_navigation_reselect.dart` with the exact content from "The fix".
2. `lib/features/home/home_screen.dart`:
   - Add `import 'bottom_navigation_reselect.dart';` after `import '../report/report_flow_screen.dart';`.
   - In `onDestinationSelected`, insert the whole `if (tab == _tab) { ... return; }` block from the target right after the `if (tab == _Tab.report) { ... }` block and before `setState(() {`.
   - In `_Landing.build`, add `controller: BottomNavigationReselect.landingScrollController,` as the first argument of `ListView(` (before `shrinkWrap: true,`).
   - In `_ReportList.build`, add `controller: BottomNavigationReselect.exploreListScrollController,` as the first argument of `ListView.separated(`.
3. `lib/features/citizen/citizen_screens.dart`:
   - Add `import '../home/bottom_navigation_reselect.dart';` after `import '../drafts/draft_store.dart';`.
   - In `_NoticesScreenState.build`, add `controller: BottomNavigationReselect.noticesScrollController,` as the first argument of `ListView(` (before `physics:`).
   - In `_ProfileScreenState.build`, add `controller: BottomNavigationReselect.profileScrollController,` as the first argument of the `ListView(` that follows `builder: (context, _) =>`.
4. `lib/features/mine/my_reports_screen.dart`:
   - Add `import '../home/bottom_navigation_reselect.dart';` after `import '../drafts/draft_store.dart';`.
   - In `build`, add `controller: widget.embedded ? BottomNavigationReselect.mineScrollController : null,` as the first argument of `return ListView(`. (Only the copy inside Home is embedded, so the shared controller is never attached twice.)
5. Run `mise exec -- dart format lib/features/home/bottom_navigation_reselect.dart lib/features/home/home_screen.dart lib/features/citizen/citizen_screens.dart lib/features/mine/my_reports_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "if (tab == _tab) {" lib/features/home/home_screen.dart` → 1
4. `grep -c "controller: BottomNavigationReselect\." lib/features/home/home_screen.dart` → 2
5. `grep -c "controller: BottomNavigationReselect\." lib/features/citizen/citizen_screens.dart` → 2
6. `grep -c "BottomNavigationReselect.mineScrollController" lib/features/mine/my_reports_screen.dart` → 1

## Don't touch

- The map (Explorar → MAPA): it isn't a list, so there's nothing to scroll to the top.
- The Reportar tab: it opens the report flow and keeps doing so.
- Lists outside the bottom navigation (report detail, report flow).
- Known trade-off: on iOS, tapping the status bar scrolls only lists that use the primary scroll controller. These five lists now have their own controllers, so the status-bar tap won't move them; tapping the current tab does the same job. Don't try to fix that here.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added lines here (a haptic call after `final tab = ...`, `keyboardDismissBehavior:` on the list, a changed `padding:`). That's expected; keep them.
- A test fails with "ScrollController attached to multiple scroll views": a shared controller is attached to two lists at once. Report which test.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: tapping the bottom tab you're already on (Inicio, Avisos, Mis reportes or Perfil) now scrolls that page back to the top, instantly when the phone asks for reduced motion. To see it, scroll down in Mis reportes and tap "Mis reportes" again.

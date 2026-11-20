# Fix: The keyboard stays open while the user scrolls

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/dismiss-keyboard-on-scroll
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

After typing an address, a category search or a phone number, citizens scroll down to see the rest of the page, but the keyboard stays and covers half the screen. Scrolling means they're done with the field, so the keyboard should close on its own. Aldia has no chat screens, where the opposite applies.

## Where

No scrollable sets `keyboardDismissBehavior` (`grep -rn keyboardDismissBehavior lib` returns nothing). Every scrollable that holds or serves a text field:

1. The phone login (phone, code and name fields):

```dart
// lib/features/citizen/login_sheet.dart:138-139 — current
    child: SingleChildScrollView(
      child: Column(
```

2. The report flow (address search, latitude and longitude, category search, note):

```dart
// lib/features/report/report_flow_screen.dart:178-179 — current
            child: ListView(
              padding: const EdgeInsets.all(16),
```

3. The "Explorar → LISTA" results, searched from the field in the app bar ("Buscar reportes"): the user types, then scrolls the results.

```dart
// lib/features/home/home_screen.dart:662-663 — current
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
```

## The fix

The article's one-line change on each scrollable:

```dart
// target
  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
```

placed as the first argument of each `SingleChildScrollView(`, `ListView(` and `ListView.separated(` above.

## Steps

1. `lib/features/citizen/login_sheet.dart`: add `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,` as the first argument of the `SingleChildScrollView(` in `_CitizenLoginSheetState.build`. If another plan already restructured that method so it starts with `Widget build(BuildContext context) => SingleChildScrollView(`, add the argument to that `SingleChildScrollView(`; there's still only one in the file.
2. `lib/features/report/report_flow_screen.dart`: add `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,` as the first argument of the `ListView(` in `_FlowViewState.build` (the one whose next line is the `padding:` quoted above).
3. `lib/features/home/home_screen.dart`: add `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,` as the first argument of the `ListView.separated(` in `_ReportList.build`.
4. Run `mise exec -- dart format lib/features/citizen/login_sheet.dart lib/features/report/report_flow_screen.dart lib/features/home/home_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "ScrollViewKeyboardDismissBehavior.onDrag" lib/features/citizen/login_sheet.dart` → 1
4. `grep -c "ScrollViewKeyboardDismissBehavior.onDrag" lib/features/report/report_flow_screen.dart` → 1
5. `grep -c "ScrollViewKeyboardDismissBehavior.onDrag" lib/features/home/home_screen.dart` → 1

## Don't touch

- The filters sheet's `SingleChildScrollView` (`home_screen.dart:529`): it holds dropdowns, not text fields.
- Scrollables with no text field (detail, avisos, perfil, empty states, onboarding).
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added arguments to these scrollables (`padding:` moved in, `controller:`) or changed their `padding:` line. That's expected; keep them.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the keyboard now closes as soon as the citizen starts scrolling in the phone login, the report flow and the Explorar results list. To see it, open "Reportar", type in "Buscar dirección", then drag the page.

# Fix: The system navigation bar covers or cuts off the end of scrolling pages

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/safe-area-replacement
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

On phones with a gesture bar or button bar at the bottom, the last part of some pages sits under that bar or gets cut off at its edge: the end of the report detail, the result of a submitted report, and the phone login. The fix leaves space as tall as the bar at the end of the list, so the content scrolls under the bar and still ends with breathing room above it. A fixed padding isn't enough, because the bar's height changes by device. `SafeArea` around a scrollable isn't a fix either: it shrinks the scrolling area, so items get cut off at the bar line instead of sliding under it.

## Where

1. Report detail: the page has no bottom bar, and the list ends with a fixed 16 padding, so the last section sits under the system bar.

```dart
// lib/features/detail/report_detail_screen.dart:90-91 — current
    return ListView(
      padding: const EdgeInsets.all(16),
```

2. Report flow: the list is wrapped in `SafeArea`. When the report is done (result screen), the page has no bottom buttons, so `SafeArea` cuts the list off at the system bar line.

```dart
// lib/features/report/report_flow_screen.dart:173-179 — current
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(16),
```

3. Phone login (used as a sheet and as the full-screen login at app start): the padding sits outside the scroll view, with a fixed 24 at the bottom, so it shrinks the scrolling area like `SafeArea` does.

```dart
// lib/features/citizen/login_sheet.dart:130-140 — current
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
```

```dart
// lib/features/citizen/login_sheet.dart:256-265 — current (end of the same build method)
          if (!widget.standalone)
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cerrar'),
            ),
        ],
      ),
    ),
  );
}
```

```dart
// lib/features/citizen/login_sheet.dart:274-275 — current (CitizenLoginScreen)
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
```

## The fix

The article's `BottomPadding` widget, as a new file `lib/widgets/bottom_padding.dart`, exactly:

```dart
import 'package:flutter/widgets.dart';

/// Breathing room at the end of a scrollable: as tall as the bottom system
/// bar, or [minimum] when the device has none.
class BottomPadding extends StatelessWidget {
  const BottomPadding({super.key});

  static double of(
    BuildContext context, {
    double minimum = 16,
  }) {
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
```

Each scrollable then ends with `BottomPadding.of(context)` as its bottom padding, and `SafeArea` around a scrollable keeps its top and side insets but drops the bottom one (`bottom: false`).

When a `Scaffold` has a `bottomNavigationBar` (the report flow's buttons, Home's navigation bar), Flutter already removes the system bar inset from the body, so `BottomPadding.of` returns its minimum there. That keeps those pages looking exactly as they do now.

## Steps

1. Create `lib/widgets/bottom_padding.dart` with the exact content from "The fix".
2. `lib/features/detail/report_detail_screen.dart`:
   - Add `import '../../widgets/bottom_padding.dart';` after `import '../../data/report_repository.dart';`.
   - Replace

     ```dart
         return ListView(
           padding: const EdgeInsets.all(16),
     ```
     with

     ```dart
         return ListView(
           padding: const EdgeInsets.all(16).copyWith(
             bottom: BottomPadding.of(context),
           ),
     ```
3. `lib/features/report/report_flow_screen.dart`:
   - Add `import '../../widgets/bottom_padding.dart';` after `import '../../services/photo_service.dart';`.
   - Replace `      body: SafeArea(\n        child: Align(` with:

     ```dart
           body: SafeArea(
             bottom: false,
             child: Align(
     ```
   - In the same block, replace `              padding: const EdgeInsets.all(16),` (line 179, the `ListView`'s padding) with:

     ```dart
                   padding: const EdgeInsets.all(16).copyWith(
                     bottom: BottomPadding.of(context),
                   ),
     ```
4. `lib/features/citizen/login_sheet.dart`:
   - Add `import '../../widgets/bottom_padding.dart';` after `import '../../services/identity_services.dart';`.
   - Move the padding into the scroll view. Replace

     ```dart
       Widget build(BuildContext context) => Padding(
         padding: EdgeInsets.fromLTRB(
           24,
           24,
           24,
           24 + MediaQuery.viewInsetsOf(context).bottom,
         ),
         child: SingleChildScrollView(
           child: Column(
     ```
     with

     ```dart
       Widget build(BuildContext context) => SingleChildScrollView(
         padding: EdgeInsets.fromLTRB(
           24,
           24,
           24,
           BottomPadding.of(context, minimum: 24) +
               MediaQuery.viewInsetsOf(context).bottom,
         ),
         child: Column(
     ```
     If another plan already added arguments to that `SingleChildScrollView(` (for example `keyboardDismissBehavior:`), keep them as arguments of the new `SingleChildScrollView(`.
   - Because one wrapper is gone, remove one closing `),` at the end of this `build`. Replace

     ```dart
             ],
           ),
         ),
       );
     }

     /// Shown at app start when the deployment requires a citizen account.
     ```
     with

     ```dart
             ],
           ),
       );
     }

     /// Shown at app start when the deployment requires a citizen account.
     ```
   - In `CitizenLoginScreen`, replace `    body: SafeArea(` with:

     ```dart
         body: SafeArea(
           bottom: false,
     ```
5. Run `mise exec -- dart format lib/widgets/bottom_padding.dart lib/features/detail/report_detail_screen.dart lib/features/report/report_flow_screen.dart lib/features/citizen/login_sheet.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "BottomPadding.of(context)" lib/features/detail/report_detail_screen.dart` → 1
4. `grep -c "BottomPadding.of(context)" lib/features/report/report_flow_screen.dart` → 1
5. `grep -c "bottom: false" lib/features/report/report_flow_screen.dart` → 1
6. `grep -c "BottomPadding.of(context, minimum: 24)" lib/features/citizen/login_sheet.dart` → 1
7. `grep -c "Widget build(BuildContext context) => Padding(" lib/features/citizen/login_sheet.dart` → 0

## Don't touch

- The report flow's bottom buttons (`bottomNavigationBar: ... SafeArea(` at `report_flow_screen.dart:141-143`): that `SafeArea` wraps fixed buttons, not a scrollable, so it's correct.
- The lists inside Home's tabs (Inicio, Avisos, Mis reportes, Perfil): Home's `NavigationBar` already keeps them clear of the system bar.
- The small bottom sheets (`map_layers_button.dart`, the filters and summary sheets in `home_screen.dart`): other plans change how those open.
- The onboarding screen: its scrollable doesn't reach the bottom; the "Siguiente" button sits below it.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added lines next to the quoted ones (an extra argument such as `keyboardDismissBehavior:` or `controller:`, an import). That's expected; keep them.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the report detail, the report result and the phone login now end with space as tall as the phone's bottom bar, so the last line scrolls clear of it instead of hiding under it or getting cut off. To see it, open any report's detail on an Android phone with gesture navigation and scroll to the end.

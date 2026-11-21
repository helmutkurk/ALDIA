# Fix: Taps, results and errors happen with no haptic feedback

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/haptic-feedback
- **Needs new dependency**: `haptic_feedback`, which offers more haptic types (success, warning, error, light, …) than Flutter's built-in `HapticFeedback`. The project rules (AGENTS.md) say to ask before adding a dependency, so get the developer's OK first.

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

Switching tabs, sending a report, verifying a phone number and hitting an error all happen in silence, so the app feels flat in the hand. A subtle vibration at those moments makes Aldia feel responsive: light for taps and toggles, success when something worked, error when it didn't, heavy when local data is wiped.

## Where

The app has no haptics at all (`grep -rnE "HapticFeedback|Haptics\." lib` returns nothing). Every key moment:

```dart
// lib/features/home/home_screen.dart:331-332 — current (bottom navigation tap)
        onDestinationSelected: (i) {
          final tab = _Tab.values[i];
```

```dart
// lib/features/home/home_screen.dart:728-731 — current (location unavailable)
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.locationUnavailable)));
    }
```

```dart
// lib/features/home/home_screen.dart:831-834 — current (cluster report failed to load)
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text(S.loadError)));
        }
```

```dart
// lib/features/detail/report_detail_screen.dart:231-234 — current
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.loadError)));
      }
```

```dart
// lib/features/citizen/citizen_screens.dart:95-99 — current (notice failed to open)
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text(S.loadError)),
                          );
                        }
```

```dart
// lib/features/citizen/citizen_screens.dart:138-141 — current (sign-out failed)
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
```

```dart
// lib/features/citizen/citizen_screens.dart:183-189 — current (local data wiped / failed)
      widget.onCleared();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Datos locales borrados.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
```

```dart
// lib/widgets/report_tile.dart:117-128 — current (follow button and its error)
                      onPressed: () async {
                        try {
                          if (followed) {
                            await repository.local.setFollow(report.id, false);
                          } else {
                            await repository.follow(report);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text(S.storageError)),
                            );
```

```dart
// lib/widgets/report_tile.dart:138-141 — current (share fell back to copying the link)
                  onPressed: () async {
                    final shared = await ShareService.shareReport(report.id);
                    if (!shared && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
```

```dart
// lib/widgets/map_layers_button.dart:46-49 — current (layer toggle)
                  value: visible,
                  onChanged: (value) {
                    onChanged(value);
                    Navigator.pop(context);
```

```dart
// lib/features/citizen/login_sheet.dart:81-92 — current (code requested / failed)
      setState(() {
        _sent = true;
        _code.clear();
        _cooldown();
      });
    } on CitizenAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo solicitar el código. Inténtalo de nuevo.',
        );
```

```dart
// lib/features/citizen/login_sheet.dart:111-123 — current (number verified / failed)
      if (!widget.auth.isSignedIn) {
        throw const CitizenAuthException(
          'No se pudo verificar el número. Inténtalo de nuevo.',
        );
      }
      if (mounted && !widget.standalone) Navigator.pop(context, true);
    } on CitizenAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo verificar el número. Inténtalo de nuevo.',
        );
```

```dart
// lib/features/citizen/login_sheet.dart:208-210 — current (show-my-name switch)
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _aliasPublic = value),
```

```dart
// lib/features/report/report_flow_screen.dart:72-80 — current (runs once per step or submit-state change)
  void _focusHeading() {
    final c = _controller!;
    final key = '${c.step.name}:${c.submitState.name}';
    if (_lastHeading == key) return;
    _lastHeading = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _heading.requestFocus();
    });
  }
```

## The fix

The article's helper, as a new file `lib/services/haptics.dart`. One change from the article: the plugin calls are wrapped in `try`, because Linux desktop builds and widget tests have no haptics plugin and would otherwise throw.

```dart
import 'package:haptic_feedback/haptic_feedback.dart';

/// One place for haptics, so the canVibrate check isn't repeated.
class HapticsHelper {
  HapticsHelper._();

  static bool? _canVibrate;

  static Future<void> _vibrate(HapticsType type) async {
    try {
      _canVibrate ??= await Haptics.canVibrate();

      if (_canVibrate ?? false) {
        await Haptics.vibrate(type);
      }
    } catch (_) {
      // Linux desktop and widget tests have no haptics plugin.
      _canVibrate = false;
    }
  }

  // Declarative shorthand for each type
  static Future<void> success() => _vibrate(HapticsType.success);
  static Future<void> warning() => _vibrate(HapticsType.warning);
  static Future<void> error() => _vibrate(HapticsType.error);
  static Future<void> light() => _vibrate(HapticsType.light);
  static Future<void> medium() => _vibrate(HapticsType.medium);
  static Future<void> heavy() => _vibrate(HapticsType.heavy);
  static Future<void> selection() => _vibrate(HapticsType.selection);
}
```

Every call is fire-and-forget with `unawaited(...)`, the style this codebase already uses (see `home_screen.dart:67`). The pairings follow the article: **light** for a tab tap, a toggle or a like-style follow; **success** for a completed submit, a sent code, a verified number or a copied link; **error** for failures; **heavy** for clearing all data.

## Steps

1. Ask the developer to approve `haptic_feedback`. If they say no, STOP.
2. Run `mise exec -- flutter pub add haptic_feedback` (without mise: `flutter pub add haptic_feedback`). Don't edit `pubspec.lock` by hand.
3. Create `lib/services/haptics.dart` with the exact content from "The fix".
4. `lib/features/home/home_screen.dart` (already imports `dart:async`): add `import '../../services/haptics.dart';` after `import '../../services/location_service.dart';`. Then:
   - Right after `final tab = _Tab.values[i];` in `onDestinationSelected`, add `unawaited(HapticsHelper.light());`.
   - In `locate()`, inside `} else {` and before `ScaffoldMessenger.of(context)`, add `unawaited(HapticsHelper.error());`.
   - In `_tapCluster`, inside `if (mounted) {` and before `ScaffoldMessenger.of(context)`, add `unawaited(HapticsHelper.error());`.
5. `lib/features/detail/report_detail_screen.dart`: add `import 'dart:async';` as the first line, followed by a blank line, and add `import '../../services/haptics.dart';` after `import '../../data/report_repository.dart';`. In `_DuplicateHint._open`, inside `if (context.mounted) {` in the `catch`, before `ScaffoldMessenger.of(context)`, add `unawaited(HapticsHelper.error());`.
6. `lib/features/citizen/citizen_screens.dart`: add `import 'dart:async';` as the first line, followed by a blank line, and add `import '../../services/haptics.dart';` after `import '../../services/citizen_auth_service.dart';`. Then:
   - In the notice `onTap` `catch`, inside `if (context.mounted) {`, before `ScaffoldMessenger.of(context).showSnackBar(`, add `unawaited(HapticsHelper.error());`.
   - In `_signOut`, inside `if (message != null) {`, before `ScaffoldMessenger.of(context)`, add `unawaited(HapticsHelper.error());`.
   - In `_clear`, right after `widget.onCleared();` (the line before `ScaffoldMessenger.of(` with 'Datos locales borrados.'), add `unawaited(HapticsHelper.heavy());`.
   - In `_clear`'s `catch (_) {`, inside `if (mounted) {`, before `ScaffoldMessenger.of(context).showSnackBar(`, add `unawaited(HapticsHelper.error());`.
7. `lib/widgets/report_tile.dart`: add `import 'dart:async';` as the first line, followed by a blank line, and add `import '../services/haptics.dart';` after `import '../services/share_service.dart';`. Then:
   - In the follow button, right after `onPressed: () async {` and before `try {`, add `unawaited(HapticsHelper.light());`.
   - In its `catch (_) {`, inside `if (context.mounted) {`, before `ScaffoldMessenger.of(context).showSnackBar(`, add `unawaited(HapticsHelper.error());`.
   - In the share button, inside `if (!shared && context.mounted) {`, before `ScaffoldMessenger.of(context).showSnackBar(`, add `unawaited(HapticsHelper.success());`.
8. `lib/widgets/map_layers_button.dart`: add `import 'dart:async';` as the first line, followed by a blank line, and add `import '../services/haptics.dart';` after `import 'package:flutter/material.dart';`. In the `SwitchListTile`'s `onChanged: (value) {`, add `unawaited(HapticsHelper.light());` before `onChanged(value);`.
9. `lib/features/citizen/login_sheet.dart` (already imports `dart:async`): add `import '../../services/haptics.dart';` after `import '../../services/identity_services.dart';`. Then:
   - In `_request`, after the `setState(() { _sent = true; ... });` block closes (after its `});`), add `unawaited(HapticsHelper.success());`.
   - In `_request`'s `on CitizenAuthException catch (e) {`, add `unawaited(HapticsHelper.error());` before `if (mounted) setState(() => _error = e.message);`. In its `catch (_) {`, add `unawaited(HapticsHelper.error());` before `if (mounted) {`.
   - In `_verify`, right before `if (mounted && !widget.standalone) Navigator.pop(context, true);`, add `unawaited(HapticsHelper.success());`.
   - In `_verify`'s `on CitizenAuthException catch (e) {` and `catch (_) {`, add `unawaited(HapticsHelper.error());` as the first statement of each, as in `_request`.
   - Replace

     ```dart
                   : (value) => setState(() => _aliasPublic = value),
     ```
     with

     ```dart
                   : (value) {
                       unawaited(HapticsHelper.light());
                       setState(() => _aliasPublic = value);
                     },
     ```
10. `lib/features/report/report_flow_screen.dart` (already imports `dart:async`): add `import '../../services/haptics.dart';` after `import '../../services/photo_service.dart';`. In `_focusHeading`, right after `_lastHeading = key;`, add:

    ```dart
        switch (c.submitState) {
          case SubmitState.done:
            unawaited(
              c.result?.status == 'rejected'
                  ? HapticsHelper.error()
                  : HapticsHelper.success(),
            );
          case SubmitState.queued ||
              SubmitState.manualSaved ||
              SubmitState.followed:
            unawaited(HapticsHelper.success());
          case SubmitState.failed:
            unawaited(HapticsHelper.error());
          default:
            break;
        }
    ```
11. Run `mise exec -- dart format lib/services/haptics.dart lib/features/home/home_screen.dart lib/features/detail/report_detail_screen.dart lib/features/citizen/citizen_screens.dart lib/widgets/report_tile.dart lib/widgets/map_layers_button.dart lib/features/citizen/login_sheet.dart lib/features/report/report_flow_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!` If it reports that `SubmitState.failed` doesn't exist, STOP (see below).
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "HapticsHelper\." lib/features/home/home_screen.dart` → 3
4. `grep -c "HapticsHelper\." lib/features/detail/report_detail_screen.dart` → 1
5. `grep -c "HapticsHelper\." lib/features/citizen/citizen_screens.dart` → 4
6. `grep -c "HapticsHelper\." lib/widgets/report_tile.dart` → 3
7. `grep -c "HapticsHelper\." lib/widgets/map_layers_button.dart` → 1
8. `grep -c "HapticsHelper\." lib/features/citizen/login_sheet.dart` → 7
9. `grep -c "HapticsHelper\." lib/features/report/report_flow_screen.dart` → 4

## Don't touch

- `ReportFlowController` (`report_flow_controller.dart`): the haptic belongs in the screen, which already reacts to submit-state changes.
- Snackbars that are only information, such as the outbox's "Esperando red" notices.
- The test fakes in `test/`: the helper already swallows the missing plugin.
- No new dependencies beyond `haptic_feedback`.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed nearby lines (a reselect branch in `onDestinationSelected`, an unfocus call, an import). That's expected; keep those changes and put the haptic call where this plan says.
- `SubmitState` has no `failed`, `done`, `queued`, `manualSaved` or `followed` value (check `lib/features/report/report_flow_controller.dart:19`).
- After `pub add`, the package has no `Haptics.canVibrate`, `Haptics.vibrate` or `HapticsType` (check its `lib/` in the pub cache).
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: Aldia now gives a subtle vibration at key moments: a light tap on tab switches, toggles and follows; a success pulse when a report is sent, a code goes out or a number is verified; an error pulse on failures; and a firm one when local data is wiped. To feel it, switch tabs on a phone, or send a report.

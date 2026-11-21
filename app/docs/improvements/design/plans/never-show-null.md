# Fix: Empty or "null" values from the server can reach the screen

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/never-show-null
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

Notes, municipal messages, place names and the masked phone number come from the server or the geocoder. Today the app checks for `null` or empty in scattered ways, and none of them catch the case where the backend sends the literal string `"null"`. A citizen would then read the word "null" under a report, or see a blank line where a place name should be. One shared helper covers all three cases (`null`, `"null"` and empty) and shows "—" or hides the line instead.

## Where

No shared guard exists (`grep -rnE "orPlaceholder|isUsable|!= 'null'" lib` returns nothing). Every place that shows such a value:

```dart
// lib/widgets/report_tile.dart:80-84 — current
                        if (report.note?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(report.note!),
                          ),
```

```dart
// lib/features/detail/report_detail_screen.dart:117-118 — current
        if (report.note?.isNotEmpty == true) Text(report.note!),
        if (report.publicNote?.isNotEmpty == true) ...[
```

```dart
// lib/features/detail/report_detail_screen.dart:207-208 — current
                  if (event.publicNote?.isNotEmpty == true)
                    Text(event.publicNote!),
```

```dart
// lib/features/home/home_screen.dart:805-808 — current
                if (report.publicNote?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(report.publicNote!),
```

```dart
// lib/features/report/report_flow_screen.dart:264-268 — current
    final place =
        c.placeLabel ??
        (c.locationConfirmed
            ? '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}'
            : 'Elige el lugar del problema');
```

```dart
// lib/features/report/report_flow_screen.dart:540 — current (address results from the geocoder)
            title: Text(address.label),
```

```dart
// lib/features/report/report_flow_screen.dart:844-847 — current
        Text(
          c.placeLabel ??
              '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}',
        ),
```

```dart
// lib/features/citizen/citizen_screens.dart:233-235 — current
                  (repository.testAccount?.active ?? false)
                      ? 'Cuenta de prueba'
                      : auth.maskedPhone ?? 'Sin verificar. Verifica tu número para consultar tus reportes desde tu cuenta.',
```

## The fix

The article's extension, as a new file `lib/core/text_x.dart`. The placeholder is "—", the dash the app already shows for a missing number on Home (`home_screen.dart:422`):

```dart
/// Display guards for text that comes from the API or the geocoder.
extension StringX on String? {
  /// False for null, empty, and the literal string "null".
  bool get isUsable {
    return this != null && this!.isNotEmpty && this != 'null';
  }

  /// The text itself, or [placeholder] when it isn't usable.
  String orPlaceholder([String placeholder = '—']) {
    if (!isUsable) return placeholder;

    return this!;
  }
}
```

Lines that are hidden when empty switch to `isUsable`; text that always shows uses `orPlaceholder()` or falls back with `isUsable ? value! : fallback`.

## Steps

1. Create `lib/core/text_x.dart` with the exact content from "The fix".
2. `lib/widgets/report_tile.dart`: add `import '../core/text_x.dart';` after `import '../core/theme.dart';`. Replace `if (report.note?.isNotEmpty == true)` with `if (report.note.isUsable)`.
3. `lib/features/detail/report_detail_screen.dart`: add `import '../../core/text_x.dart';` after `import '../../core/strings.dart';`. Then:
   - `if (report.note?.isNotEmpty == true) Text(report.note!),` → `if (report.note.isUsable) Text(report.note!),`
   - `if (report.publicNote?.isNotEmpty == true) ...[` → `if (report.publicNote.isUsable) ...[`
   - `if (event.publicNote?.isNotEmpty == true)` → `if (event.publicNote.isUsable)`
4. `lib/features/home/home_screen.dart`: add `import '../../core/text_x.dart';` after `import '../../core/theme.dart';`. Replace `if (report.publicNote?.isNotEmpty == true)` with `if (report.publicNote.isUsable)`.
5. `lib/features/report/report_flow_screen.dart`: add `import '../../core/text_x.dart';` after `import '../../core/theme.dart';`. Then:
   - Replace the `final place =` block quoted in "Where" with:

     ```dart
         final place = c.placeLabel.isUsable
             ? c.placeLabel!
             : (c.locationConfirmed
                   ? '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}'
                   : 'Elige el lugar del problema');
     ```
   - Replace `title: Text(address.label),` with `title: Text(address.label.orPlaceholder()),`.
   - Replace the review-step `Text(` block quoted in "Where" with:

     ```dart
             Text(
               c.placeLabel.isUsable
                   ? c.placeLabel!
                   : '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}',
             ),
     ```
6. `lib/features/citizen/citizen_screens.dart`: add `import '../../core/text_x.dart';` after `import '../../core/theme.dart';`. Replace the three lines quoted in "Where" with:

   ```dart
                     (repository.testAccount?.active ?? false)
                         ? 'Cuenta de prueba'
                         : auth.maskedPhone.isUsable
                         ? auth.maskedPhone!
                         : 'Sin verificar. Verifica tu número para consultar tus reportes desde tu cuenta.',
   ```
7. Run `mise exec -- dart format lib/core/text_x.dart lib/widgets/report_tile.dart lib/features/detail/report_detail_screen.dart lib/features/home/home_screen.dart lib/features/report/report_flow_screen.dart lib/features/citizen/citizen_screens.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "isNotEmpty == true" lib/widgets/report_tile.dart` → 0
4. `grep -c "isNotEmpty == true" lib/features/detail/report_detail_screen.dart` → 0
5. `grep -c "publicNote?.isNotEmpty" lib/features/home/home_screen.dart` → 0
6. `grep -c "placeLabel ??" lib/features/report/report_flow_screen.dart` → 0
7. `grep -c "address.label.orPlaceholder()" lib/features/report/report_flow_screen.dart` → 1
8. `grep -c "maskedPhone.isUsable" lib/features/citizen/citizen_screens.dart` → 1

## Don't touch

- `Text(c.note)` in the review step (`report_flow_screen.dart:857`): that's the citizen's own typing, not a server value.
- The JSON parsing in `lib/data/report.dart`: the guard belongs where text is displayed.
- Search and filter logic that reads `r.note ?? ''` in `home_screen.dart:635`: it doesn't display anything.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed nearby lines (an import, an image or date line). That's expected; keep those changes.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: notes, municipal messages, place names and the masked phone number now go through one shared guard, so an empty value or a literal "null" from the server is hidden or shown as "—", never as the word "null". To see it, open any report's detail: a report without a note simply has no note line.

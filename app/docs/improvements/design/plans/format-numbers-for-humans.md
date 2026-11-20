# Fix: Counts and sizes are shown as raw digits

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/format-numbers-for-humans
- **Needs new dependency**: none (`intl` is already a direct dependency)

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

The big "reportes resueltos" number on Inicio, the report counts on map clusters, the upload size and the GPS accuracy are printed as raw digits: "12345" instead of "12,345". Guatemala groups digits with commas and uses a dot for decimals, so every "how much" number should be shown that way. Cluster pins have little room, so they show the short form ("1.2 k").

## Where

No number formatting exists (`grep -rnE "NumberFormat|decimalPattern|compact\(" lib` returns nothing). Every number a user reads as "how much":

```dart
// lib/features/home/home_screen.dart:421-422 — current (resolved count on Inicio)
                    Text(
                      snapshot.data?.toString() ?? '—',
```

```dart
// lib/features/home/home_screen.dart:1029-1031 — current (cluster pin)
          child: single
              ? const Icon(Icons.location_on)
              : Text('${cluster.count}', textScaler: TextScaler.noScaling),
```

```dart
// lib/core/strings.dart:155-156 — current
  static String uploadSize(int bytes) =>
      'Tamaño estimado de envío: ${(bytes / 1024).ceil()} KB';
```

```dart
// lib/core/strings.dart:164-165 — current
  static String accuracy(double value) => 'Precisión GPS: ${value.round()} m';
  static String clusterCount(int count) => '$count reportes';
```

## The fix

The article's `NumX` extension, as a new file `lib/core/number_format.dart`. `intl` 0.20 has no `es_GT` number data, so it uses `es_419` (Latin American Spanish), which has the same separators as Guatemala: `,` for thousands and `.` for decimals. It's passed explicitly because the app never sets `Intl.defaultLocale`.

```dart
import 'package:intl/intl.dart';

/// Guatemala writes 1,234.5. intl has no es_GT number symbols, so the Latin
/// American Spanish set (same separators) is used.
const _numberLocale = 'es_419';

extension NumX on num {
  /// 12345 → "12,345".
  String humanizedCount({int? decimalDigits}) {
    return NumberFormat.decimalPatternDigits(
      locale: _numberLocale,
      decimalDigits: decimalDigits,
    ).format(this);
  }

  /// 1234 → "1.2 k", for tight spots such as map pins.
  String humanizedCompact() {
    return NumberFormat.compact(locale: _numberLocale).format(this);
  }
}
```

Targets:

```dart
// lib/features/home/home_screen.dart
                      snapshot.data?.humanizedCount() ?? '—',
...
              : Text(
                  cluster.count.humanizedCompact(),
                  textScaler: TextScaler.noScaling,
                ),
```

```dart
// lib/core/strings.dart
  static String uploadSize(int bytes) =>
      'Tamaño estimado de envío: ${(bytes / 1024).ceil().humanizedCount()} KB';
...
  static String accuracy(double value) =>
      'Precisión GPS: ${value.round().humanizedCount()} m';
  static String clusterCount(int count) => '${count.humanizedCount()} reportes';
```

## Steps

1. Create `lib/core/number_format.dart` with the exact content from "The fix".
2. `lib/core/strings.dart`: add `import 'number_format.dart';` as the first line of the file, followed by a blank line, before the `/// All user-facing text` comment. Replace the `uploadSize`, `accuracy` and `clusterCount` lines quoted in "Where" with the `strings.dart` targets.
3. `lib/features/home/home_screen.dart`: add `import '../../core/number_format.dart';` after `import '../../core/config.dart';`. Replace `snapshot.data?.toString() ?? '—',` with `snapshot.data?.humanizedCount() ?? '—',`. Replace `: Text('${cluster.count}', textScaler: TextScaler.noScaling),` with the cluster-pin target.
4. Run `mise exec -- dart format lib/core/number_format.dart lib/core/strings.dart lib/features/home/home_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass. If a test fails only because it expects an unformatted number of 1000 or more, update that expectation to the formatted text, nothing else.
3. `grep -c "humanizedCount()" lib/core/strings.dart` → 3
4. `grep -c "snapshot.data?.toString()" lib/features/home/home_screen.dart` → 0
5. `grep -c "cluster.count.humanizedCompact()" lib/features/home/home_screen.dart` → 1

## Don't touch

- The filter badge count `Text('$filterCount')` (`home_screen.dart:282`): it's never more than 2.
- `S.age` ("Hace N días"): the list window is 90 days, so it never reaches four digits.
- `S.stepProgress`, `S.onboardingPage` and report ids: those are "which one", not "how much".
- Coordinates shown with `toStringAsFixed(5)`: they're positions, not amounts.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed nearby lines (an import, a style). That's expected; keep those changes.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: counts and sizes now read like Guatemala writes them, for example "12,345 reportes resueltos" and "1,240 KB", and big map clusters show a short "1.2 k". To see it, check the resolved count on Inicio or a large cluster on the map.

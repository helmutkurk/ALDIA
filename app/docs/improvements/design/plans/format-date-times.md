# Fix: Dates are shown as raw numbers like 3/11/2026

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/format-date-times
- **Needs new dependency**: none (`intl` is already a direct dependency)

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

Report cards, notices and the report detail print dates as bare numbers, such as `3/11/2026` or `3/11/2026 14:44`, built by hand or with a numeric pattern. Numeric dates are easy to misread (day or month first?). Spanish month names read better: `3 nov 2026` in lists and `3 de noviembre de 2026, 14:44` on the detail page. One shared helper keeps every date consistent, and a missing date shows "—" instead of breaking.

## Where

1. The report card, hand-built from day/month/year:

```dart
// lib/widgets/report_tile.dart:86-89 — current
                        Text(
                          '${report.createdAt.day}/${report.createdAt.month}/${report.createdAt.year} · ${S.age(report.createdAt, DateTime.now())}',
                          style: theme.textTheme.bodySmall,
                        ),
```

2. The notices list (Avisos), hand-built:

```dart
// lib/features/citizen/citizen_screens.dart:86-88 — current
                    subtitle: Text(
                      '${citizenStateFor(notice.state).label}\n${notice.at.day}/${notice.at.month}/${notice.at.year} · ${S.reference(notice.reportId)}',
                    ),
```

3. The report detail and its timeline, a numeric pattern with no locale:

```dart
// lib/features/detail/report_detail_screen.dart:14 — current
final _dateFormat = DateFormat('d/M/y HH:mm');
```

```dart
// lib/features/detail/report_detail_screen.dart:116 — current
        Text(_dateFormat.format(report.createdAt.toLocal())),
```

```dart
// lib/features/detail/report_detail_screen.dart:205-206 — current
                  if (event.at != null)
                    Text(_dateFormat.format(event.at!.toLocal())),
```

4. Startup, where the locale data must be loaded:

```dart
// lib/main.dart:26-27 — current
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
```

## The fix

The article's `DateTimeX` extension on `DateTime?`, as a new file `lib/core/date_format.dart`, with the two formats this app needs and Spanish patterns (Spanish puts "de" between day, month and year in full dates). The helper converts to local time itself, and a null date returns "—", the dash the app already uses for missing values.

```dart
import 'package:intl/intl.dart';

/// Language of every date on screen.
const appLanguageCode = 'es';

extension DateTimeX on DateTime? {
  // 3 de noviembre de 2026, 14:44 — where the date is the point (detail).
  String formattedDateTime([String languageCode = appLanguageCode]) {
    if (this == null) return '—';

    return DateFormat(
      "d 'de' MMMM 'de' y, HH:mm",
      languageCode,
    ).format(this!.toLocal());
  }

  // 3 nov 2026 — dense lists.
  String formattedDate([String languageCode = appLanguageCode]) {
    if (this == null) return '—';

    return DateFormat('d MMM y', languageCode).format(this!.toLocal());
  }
}
```

The article loads the locale data once in `main` with `initializeDateFormatting()`. Widget tests don't run `main` and the test harness (`test/widgets/harness.dart`) has no localization delegates, so the plan loads it for tests too, in a `test/flutter_test_config.dart` that Flutter runs before every test file:

```dart
import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';

/// Loads Spanish date data before every test file, like main() does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeDateFormatting('es');
  await testMain();
}
```

## Steps

1. Create `lib/core/date_format.dart` with the exact content from "The fix".
2. `lib/main.dart`: add `import 'package:intl/date_symbol_data_local.dart';` after `import 'package:http/http.dart' as http;`, and `import 'core/date_format.dart';` after `import 'core/config.dart';`. Right after `WidgetsFlutterBinding.ensureInitialized();` add `await initializeDateFormatting(appLanguageCode);`.
3. `lib/widgets/report_tile.dart`: add `import '../core/date_format.dart';` after `import '../core/citizen_states.dart';`. Replace the `Text(` block quoted in "Where" (item 1) with:

   ```dart
                           Text(
                             '${report.createdAt.formattedDate()} · ${S.age(report.createdAt, DateTime.now())}',
                             style: theme.textTheme.bodySmall,
                           ),
   ```
4. `lib/features/citizen/citizen_screens.dart`: add `import '../../core/date_format.dart';` after `import '../../core/citizen_states.dart';`. Replace the `subtitle: Text(` block quoted in "Where" (item 2) with:

   ```dart
                       subtitle: Text(
                         '${citizenStateFor(notice.state).label}\n${notice.at.formattedDate()} · ${S.reference(notice.reportId)}',
                       ),
   ```
5. `lib/features/detail/report_detail_screen.dart`:
   - Replace `import 'package:intl/intl.dart';` with nothing (delete the line), and add `import '../../core/date_format.dart';` after `import '../../core/citizen_states.dart';`.
   - Delete the line `final _dateFormat = DateFormat('d/M/y HH:mm');` and the blank line after it.
   - Replace `Text(_dateFormat.format(report.createdAt.toLocal())),` with `Text(report.createdAt.formattedDateTime()),`.
   - Replace `Text(_dateFormat.format(event.at!.toLocal())),` with `Text(event.at.formattedDateTime()),`.
6. Create `test/flutter_test_config.dart` with the exact test-config content from "The fix".
7. Run `mise exec -- dart format lib/core/date_format.dart lib/main.dart lib/widgets/report_tile.dart lib/features/citizen/citizen_screens.dart lib/features/detail/report_detail_screen.dart test/flutter_test_config.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass. If a test fails only because it expects the old numeric date text, update that expectation to the new format, nothing else.
3. `grep -c "createdAt.day" lib/widgets/report_tile.dart` → 0
4. `grep -c "notice.at.day" lib/features/citizen/citizen_screens.dart` → 0
5. `grep -c "_dateFormat" lib/features/detail/report_detail_screen.dart` → 0
6. `grep -c "formattedDateTime()" lib/features/detail/report_detail_screen.dart` → 2
7. `grep -c "initializeDateFormatting(appLanguageCode)" lib/main.dart` → 1

## Don't touch

- `S.age` ("Hace 3 días"): relative ages stay as they are.
- Dates sent to the server or stored (`toIso8601String()` in `local_citizen_store.dart`, `draft_record.dart`): those are for machines, never shown.
- `locale: const Locale('es', 'GT')` on `MaterialApp`.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed nearby lines (imports, an `ErrorWidget.builder` or changelog line in `main`, an image or note line in the card). That's expected; keep those changes.
- A `test/flutter_test_config.dart` already exists with other content: add the `initializeDateFormatting('es')` call inside its existing `testExecutable` instead, before `await testMain();`.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: dates now read in Spanish everywhere: "3 nov 2026" on report cards and in Avisos, and "3 de noviembre de 2026, 14:44" on the report detail and its timeline, always in local time. To see it, open any report's detail.

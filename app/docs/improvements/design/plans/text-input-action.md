# Fix: The keyboard's action key doesn't move through forms or submit them

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/text-input-action
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

In the phone login and in the report flow's coordinates, the keyboard's action key just closes the keyboard. Citizens then have to tap the next field or the button by hand. With the right action on each field, the key moves to the next field and, on the last one, does what the form's button does: request the code, verify the number, or apply the coordinates.

## Where

1. Phone login. Before the code is sent, only the phone field is active; after that, the phone field is disabled and the code and name fields appear. None sets `textInputAction`.

```dart
// lib/features/citizen/login_sheet.dart:159-164 — current (phone)
          TextField(
            key: const Key('citizen-phone'),
            controller: _phone,
            enabled: !_busy && !_sent,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
```

```dart
// lib/features/citizen/login_sheet.dart:180-185 — current (code)
            TextField(
              key: const Key('citizen-code'),
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
```

```dart
// lib/features/citizen/login_sheet.dart:195-198 — current (display name)
            TextField(
              controller: _alias,
              enabled: !_busy,
              maxLength: 60,
```

The button below them calls `_sent ? _verify : _request` (`login_sheet.dart:227`), and is disabled while `_busy`.

2. Report flow, location step: latitude and longitude, applied by the "Usar estas coordenadas" button (`_apply`). The address search above them already uses `TextInputAction.search`.

```dart
// lib/features/report/report_flow_screen.dart:655-670 — current
        TextField(
          controller: _lat,
          decoration: const InputDecoration(labelText: S.latitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
        ),
        TextField(
          controller: _lon,
          decoration: const InputDecoration(labelText: S.longitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
        ),
```

## The fix

The article's pattern: `TextInputAction.next` on every field but the last, and `TextInputAction.done` on the last with a submit handler that calls the same method as the form's button. These are `TextField`s, so the handler is `onSubmitted` (the article's `onFieldSubmitted` is the `TextFormField` name). The login handlers keep the button's guard (`_busy`, `_sent`), so the key never fires a second request.

```dart
// target — phone (the only active field before the code is sent)
          TextField(
            key: const Key('citizen-phone'),
            controller: _phone,
            enabled: !_busy && !_sent,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_busy && !_sent) unawaited(_request());
            },
            autofillHints: const [AutofillHints.telephoneNumberNational],
```

```dart
// target — code
            TextField(
              key: const Key('citizen-code'),
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.oneTimeCode],
```

```dart
// target — display name (last field after the code is sent)
            TextField(
              controller: _alias,
              enabled: !_busy,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) unawaited(_verify());
              },
```

```dart
// target — coordinates
        TextField(
          controller: _lat,
          decoration: const InputDecoration(labelText: S.latitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          controller: _lon,
          decoration: const InputDecoration(labelText: S.longitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _apply(),
        ),
```

## Steps

1. `lib/features/citizen/login_sheet.dart` (already imports `dart:async` for `unawaited`): in the phone `TextField`, add the `textInputAction:` and `onSubmitted:` lines from the phone target right after `keyboardType: TextInputType.phone,`.
2. Same file, code `TextField`: add `textInputAction: TextInputAction.next,` right after `keyboardType: TextInputType.number,`.
3. Same file, display-name `TextField`: add the `textInputAction:` and `onSubmitted:` lines from the display-name target right after `maxLength: 60,`.
4. `lib/features/report/report_flow_screen.dart`: in the latitude `TextField`, add `textInputAction: TextInputAction.next,` after its `keyboardType: ... ),` argument. In the longitude `TextField`, add `textInputAction: TextInputAction.done,` and `onSubmitted: (_) => _apply(),` after its `keyboardType: ... ),` argument.
5. Run `mise exec -- dart format lib/features/citizen/login_sheet.dart lib/features/report/report_flow_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "textInputAction:" lib/features/citizen/login_sheet.dart` → 3
4. `grep -c "onSubmitted:" lib/features/citizen/login_sheet.dart` → 2
5. `grep -c "onSubmitted: (_) => _apply()," lib/features/report/report_flow_screen.dart` → 1
6. `grep -c "TextInputAction.next" lib/features/report/report_flow_screen.dart` → 1

## Don't touch

- The note field in the report flow (`TextFormField` with `maxLines: 8`): multiline, so its return key must keep inserting a new line.
- The address search and the category search: single-field searches; the address one already uses `TextInputAction.search`.
- The search field in Home's app bar: already `TextInputAction.search`.
- `_request`, `_verify` and `_apply`: called as they are.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed these fields (their `inputFormatters:` list, for example). That's expected; keep those changes.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the keyboard's action key now drives both forms. In the login it requests the code from the phone field, moves from the code to the name, and verifies from the name. In Reportar it moves from latitude to longitude and then applies the coordinates. To see it, open the login and press the keyboard's "done" key after typing the number.

# Fix: The phone number field is one long run of digits

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/format-phone-numbers
- **Needs new dependency**: `mask_text_input_formatter`, which groups the digits while the user types. The project rules (AGENTS.md) say to ask before adding a dependency, so get the developer's OK first.

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

At login, citizens type their 8-digit Guatemalan number as one block, `55551234`, which is hard to check and easy to mistype. Guatemala writes numbers in two groups of four, `5555 1234`, so the field should insert the space while they type.

## Where

No mask or phone formatter exists (`grep -rnE "MaskTextInputFormatter|maskPhoneNumber|phone_numbers_parser" lib` returns nothing). The only place a phone number is typed:

```dart
// lib/features/citizen/login_sheet.dart:159-173 — current
          TextField(
            key: const Key('citizen-phone'),
            controller: _phone,
            enabled: !_busy && !_sent,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: 'Número de teléfono',
              prefixText: '+502 ',
              helperText: 'Guatemala · 8 dígitos',
            ),
          ),
```

```dart
// lib/features/citizen/login_sheet.dart:39-42 — current
class _CitizenLoginSheetState extends State<CitizenLoginSheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _alias = TextEditingController();
```

The only place a phone number is shown, Perfil (`citizen_screens.dart:235`), displays `auth.maskedPhone`, which the server already sends grouped (`+502 •••• ••22`). It needs no change.

## The fix

The article's single-country approach: a `MaskTextInputFormatter` in `eager` mode, which inserts the space as the user types. The mask is `#### ####`, and it limits input to 8 digits on its own, so it replaces both current formatters. A mask formatter keeps state, so each login sheet gets its own instance as a field of the `State` instead of the article's global. No unmask step is needed when sending: `normalizeCitizenPhone` (`lib/services/citizen_auth_service.dart:18-20`) already strips spaces before validating 8 digits.

```dart
// target — fields
class _CitizenLoginSheetState extends State<CitizenLoginSheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _alias = TextEditingController();
  // Guatemala: 8 digits in two groups, typed after the fixed +502 prefix.
  final _phoneFormatter = MaskTextInputFormatter(
    mask: '#### ####',
    filter: {'#': RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.eager,
  );
```

```dart
// target — the field's formatters
            inputFormatters: [_phoneFormatter],
```

## Steps

1. Ask the developer to approve `mask_text_input_formatter`. If they say no, STOP.
2. Run `mise exec -- flutter pub add mask_text_input_formatter` (without mise: `flutter pub add mask_text_input_formatter`). Don't edit `pubspec.lock` by hand.
3. `lib/features/citizen/login_sheet.dart`: add `import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';` after `import 'package:flutter/services.dart';`.
4. In `_CitizenLoginSheetState`, add the comment and the `_phoneFormatter` field from the target right after `final _alias = TextEditingController();`.
5. In the phone `TextField` (the one with `key: const Key('citizen-phone')`), replace

   ```dart
               inputFormatters: [
                 FilteringTextInputFormatter.digitsOnly,
                 LengthLimitingTextInputFormatter(8),
               ],
   ```
   with `inputFormatters: [_phoneFormatter],`. If another plan already put a `StripDialCodeFormatter()` first in that list, keep it first: `inputFormatters: [StripDialCodeFormatter(), _phoneFormatter],`.
6. Run `mise exec -- dart format lib/features/citizen/login_sheet.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!` (`flutter/services.dart` is still needed by the code field's formatters.)
2. `mise exec -- flutter test` → all tests pass. The login tests type `22222222`; the field shows `2222 2222`, and `normalizeCitizenPhone` strips the space.
3. `grep -c "MaskTextInputFormatter(" lib/features/citizen/login_sheet.dart` → 1
4. `grep -c "LengthLimitingTextInputFormatter(8)" lib/features/citizen/login_sheet.dart` → 0
5. `grep -c "LengthLimitingTextInputFormatter(6)" lib/features/citizen/login_sheet.dart` → 1 (the code field is unchanged)

## Don't touch

- The verification code field (`key: const Key('citizen-code')`): it's a code, not a phone number.
- `normalizeCitizenPhone` in `citizen_auth_service.dart`: it already accepts spaces.
- The Perfil display of `maskedPhone`: the server formats it.
- `prefixText: '+502 '`, `helperText` and `autofillHints`.
- No new dependencies beyond `mask_text_input_formatter`.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed this field (a `StripDialCodeFormatter()` in the list, `textInputAction:`, `onSubmitted:`). That's expected; keep those changes.
- After `pub add`, `MaskTextInputFormatter` has no `mask`, `filter` or `type` parameter, or there's no `MaskAutoCompletionType.eager` (check the package's `lib/`).
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: the phone field at login now groups the number as the citizen types (`5555 1234` after the fixed `+502`) and still accepts only 8 digits. To see it, open the login and type a number.

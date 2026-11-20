# Fix: Pasting a number with +502 puts the wrong digits in the phone field

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/autofill-dial-code
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

The login phone field shows a fixed `+502 ` prefix, so citizens type only the 8 national digits. When they paste their number in international form (`+502 5555 1234`) or autofill inserts it, the field strips the symbols and keeps the first 8 digits, `50255551`: the dial code doubled and the end of the number cut off. They have to clear it and type it again. Catching the dial code on paste and autofill leaves just `55551234`.

## Where

The field shows the dial code as a separate prefix, and nothing in `inputFormatters` strips it:

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

## The fix

The article's `StripDialCodeFormatter`, adapted to Guatemala's dial code `502`, as a new file `lib/core/strip_dial_code_formatter.dart`. It only acts when the text grows by more than one character (paste or autofill), so typing is never touched, and it strips a leading `+502` or `00502`. It goes first in the field's `inputFormatters`, so the existing formatters then see only the national digits.

```dart
import 'package:flutter/services.dart';

/// Strips Guatemala's dial code from pasted or autofilled phone numbers, so
/// the field behind the fixed "+502 " prefix keeps only the national number.
class StripDialCodeFormatter extends TextInputFormatter {
  static const String _dialCode = '502';

  static final RegExp _nonDigits = RegExp(r'[^0-9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // A keystroke grows the text by one character.
    // Paste and autofill grow it by many.
    final bool bulk = newValue.text.length - oldValue.text.length > 1;
    if (!bulk) return newValue;

    final String digits = newValue.text.replaceAll(_nonDigits, '');

    String national = digits;
    if (digits.startsWith('00$_dialCode')) {
      national = digits.substring(2 + _dialCode.length);
    } else if (newValue.text.trimLeft().startsWith('+') &&
        digits.startsWith(_dialCode)) {
      national = digits.substring(_dialCode.length);
    }

    return TextEditingValue(
      text: national,
      selection: TextSelection.collapsed(offset: national.length),
    );
  }
}
```

```dart
// target — the field's formatters
            inputFormatters: [
              StripDialCodeFormatter(),
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
```

## Steps

1. Create `lib/core/strip_dial_code_formatter.dart` with the exact content from "The fix".
2. `lib/features/citizen/login_sheet.dart`: add `import '../../core/strip_dial_code_formatter.dart';` after `import '../../core/config.dart';`.
3. In the phone `TextField` (`key: const Key('citizen-phone')`), add `StripDialCodeFormatter(),` as the first entry of `inputFormatters: [`. If another plan already replaced the list with `[_phoneFormatter]`, the result is `inputFormatters: [StripDialCodeFormatter(), _phoneFormatter],`.
4. Run `mise exec -- dart format lib/core/strip_dial_code_formatter.dart lib/features/citizen/login_sheet.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass. The tests type `22222222` in one `enterText`, which counts as a bulk edit: it has no `+` and doesn't start with `00502`, so it passes through unchanged.
3. `grep -c "StripDialCodeFormatter()," lib/features/citizen/login_sheet.dart` → 1
4. `grep -c "_dialCode = '502'" lib/core/strip_dial_code_formatter.dart` → 1

## Don't touch

- `prefixText: '+502 '` and `autofillHints: const [AutofillHints.telephoneNumberNational]`: autofill stays on; the formatter only makes it safe.
- `normalizeCitizenPhone` in `citizen_auth_service.dart`: it already handles a `+502` that reaches it.
- The verification code field.
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed this field (a mask formatter instead of `digitsOnly` and the length limit, `textInputAction:`, `onSubmitted:`). That's expected; keep those changes and put `StripDialCodeFormatter()` first in the list.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: pasting or autofilling a number like `+502 5555 1234` into the login phone field now leaves only `55551234` after the fixed `+502` prefix, instead of a doubled dial code and a cut-off number. Typing digits one by one works as before. To see it, copy `+502 5555 1234` and paste it into the field.

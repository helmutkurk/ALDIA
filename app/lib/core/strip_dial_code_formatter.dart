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

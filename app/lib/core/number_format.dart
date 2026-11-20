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

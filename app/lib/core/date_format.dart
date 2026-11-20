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

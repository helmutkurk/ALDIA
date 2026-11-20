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

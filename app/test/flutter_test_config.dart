import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';

/// Loads Spanish date data before every test file, like main() does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeDateFormatting('es');
  await testMain();
}

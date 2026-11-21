import 'package:flutter/foundation.dart';

/// MVP test account: lets a tester enter the app without a server login
/// while the final login method (citizen ID or email) is undecided.
///
/// It is local to the device. Reports are sent without credentials, so the
/// API must allow anonymous submissions (REQUIRE_CITIZEN_LOGIN=false), and
/// "Mis reportes" uses the ids saved on this device.
class TestAccountSession extends ChangeNotifier {
  TestAccountSession({this._active = false, this.onChanged});

  /// Persists the state, for example in SharedPreferences.
  final Future<void> Function(bool active)? onChanged;
  bool _active;

  bool get active => _active;

  Future<void> start() => _set(true);
  Future<void> end() => _set(false);

  Future<void> _set(bool value) async {
    if (_active == value) return;
    _active = value;
    notifyListeners();
    await onChanged?.call(value);
  }
}

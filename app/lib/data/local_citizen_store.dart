import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'report.dart';

class CitizenNotice {
  const CitizenNotice({
    required this.reportId,
    required this.category,
    required this.state,
    required this.at,
  });
  final String reportId;
  final String category;
  final String state;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'id': reportId,
    'category': category,
    'state': state,
    'at': at.toIso8601String(),
  };
  factory CitizenNotice.fromJson(Map<String, Object?> json) => CitizenNotice(
    reportId: json['id'] as String,
    category: json['category'] as String,
    state: json['state'] as String,
    at: DateTime.parse(json['at'] as String),
  );
}

/// Device-only follows, observed states and inbox. No push or remote account.
/// Tests use the in-memory default; production injects preferences once.
class LocalCitizenStore extends ChangeNotifier {
  LocalCitizenStore({SharedPreferences? preferences})
    : _preferences = preferences {
    final raw = preferences?.getString(_key);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, Object?>;
        _followed.addAll((json['followed'] as List<Object?>).cast<String>());
        _states.addAll(
          (json['states'] as Map<String, Object?>).cast<String, String>(),
        );
        _notices.addAll(
          (json['notices'] as List<Object?>).map(
            (e) => CitizenNotice.fromJson(
              Map<String, Object?>.from(e as Map<Object?, Object?>),
            ),
          ),
        );
        showName = json['show_name'] as bool? ?? false;
      } on FormatException {
        /* A damaged inbox must not block reporting. */
      } on TypeError {
        /* Old/incomplete local records are optional. */
      }
    }
  }

  static const _key = 'citizen_local_v1';
  final SharedPreferences? _preferences;
  final _followed = <String>{};
  final _states = <String, String>{};
  final _notices = <CitizenNotice>[];
  Future<void> _pending = Future.value();
  bool showName = false;
  List<CitizenNotice> get notices => List.unmodifiable(_notices);
  bool follows(String id) => _followed.contains(id);
  List<String> get followedIds =>
      List.unmodifiable(_followed.toList().reversed);

  Future<void> _save() {
    final snapshot = jsonEncode({
      'followed': _followed.toList(),
      'states': _states,
      'notices': _notices.map((n) => n.toJson()).toList(),
      'show_name': showName,
    });
    final result = _pending.then((_) async {
      if (_preferences case final prefs?) {
        if (!await prefs.setString(_key, snapshot)) {
          throw StateError('Local storage unavailable');
        }
      }
    });
    _pending = result.catchError((Object _) {});
    notifyListeners();
    return result;
  }

  Future<void> setFollow(String id, bool value) {
    value ? _followed.add(id) : _followed.remove(id);
    return _save();
  }

  Future<void> setShowName(bool value) {
    showName = value;
    return _save();
  }

  Future<void> observe(List<Report> reports) async {
    var changed = false;
    for (final report in reports) {
      final previous = _states[report.id];
      if (previous == report.citizenState) continue;
      if (previous != null) {
        _notices.insert(
          0,
          CitizenNotice(
            reportId: report.id,
            category: report.category,
            state: report.citizenState,
            at: report.stateChangedAt ?? DateTime.now().toUtc(),
          ),
        );
      }
      _states[report.id] = report.citizenState;
      changed = true;
    }
    if (_notices.length > 100) _notices.removeRange(100, _notices.length);
    if (changed) await _save();
  }

  Future<void> clear() {
    _followed.clear();
    _states.clear();
    _notices.clear();
    showName = false;
    return _save();
  }
}

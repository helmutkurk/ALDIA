import 'package:shared_preferences/shared_preferences.dart';

/// Ids of the reports sent from this device. No account exists in v0, so the
/// device keeps its own list.
abstract class MyReportsStore {
  Future<List<String>> ids();
  Future<void> add(String id);
}

class PrefsMyReportsStore implements MyReportsStore {
  static const _key = 'my_report_ids';

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  @override
  Future<List<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  @override
  Future<void> add(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    if (!current.contains(id)) {
      await prefs.setStringList(_key, [id, ...current]);
    }
  }
}

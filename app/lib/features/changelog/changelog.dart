import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Languages the changelog is written in. Aldia ships Spanish (Guatemala).
enum AppLanguage { es }

/// What changed in each version, in user-facing Spanish.
///
/// Before each release, add an entry for the new version (the `version:`
/// in pubspec.yaml without the build number) with one short line per change.
const Map<String, Map<AppLanguage, List<String>>> _changelog = {
  '0.1.0': {
    AppLanguage.es: ['Primera versión de Aldia.'],
  },
};

const _lastSeenKey = 'last_seen_version';

/// Every change after [lastSeen] up to and including [current], so a jump
/// from 1.2.0 to 1.5.0 shows everything in between.
List<String> unseenChanges({
  required String lastSeen,
  required String current,
  required AppLanguage language,
}) {
  final Version lastSeenVersion = Version.parse(lastSeen);
  final Version currentVersion = Version.parse(current);

  final List<String> result = [];

  for (final entry in _changelog.entries) {
    final Version entryVersion = Version.parse(entry.key);

    if (entryVersion > lastSeenVersion && entryVersion <= currentVersion) {
      final changes = entry.value[language];
      if (changes != null) result.addAll(changes);
    }
  }

  return result;
}

/// Decides on app open whether the "Novedades" dialog is due.
class ChangelogController extends ChangeNotifier {
  ChangelogController({required SharedPreferences preferences})
    : _prefs = preferences;

  final SharedPreferences _prefs;
  String? _currentVersion;
  List<String>? _changes;

  /// Changes to show, or null when there is nothing new.
  List<String>? get changes => _changes;

  Future<void> initialize({AppLanguage language = AppLanguage.es}) async {
    final String current = (await PackageInfo.fromPlatform()).version;
    _currentVersion = current;

    final String? lastSeen = _prefs.getString(_lastSeenKey);

    // First install: nothing to show, save and move on.
    if (lastSeen == null) {
      await _prefs.setString(_lastSeenKey, current);
      return;
    }

    // Already up to date.
    if (lastSeen == current) return;

    final List<String> changes = unseenChanges(
      lastSeen: lastSeen,
      current: current,
      language: language,
    );

    if (changes.isEmpty) {
      await _prefs.setString(_lastSeenKey, current);
      return;
    }

    _changes = changes;
    notifyListeners();
  }

  /// Marks the current version as seen.
  Future<void> dismiss() async {
    final String? version = _currentVersion;
    if (version != null) await _prefs.setString(_lastSeenKey, version);
    _changes = null;
    notifyListeners();
  }
}

/// Shows the pending changes once, then marks the version as seen.
Future<void> showChangelogIfNeeded(
  BuildContext context,
  ChangelogController? changelog,
) async {
  final changes = changelog?.changes;
  if (changelog == null || changes == null) return;
  FocusManager.instance.primaryFocus?.unfocus();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Novedades de Aldia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $change'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
  await changelog.dismiss();
}

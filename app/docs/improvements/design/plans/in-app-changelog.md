# Fix: After an update, nothing tells users what's new

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/in-app-changelog
- **Needs new dependency**: `package_info_plus` (reads the installed version) and `pub_semver` (compares versions). Both are already in `pubspec.lock` as indirect dependencies, but they must become direct ones. The project rules (AGENTS.md) say to ask before adding a dependency, so get the developer's OK first.

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

After an update, citizens open Aldia and nothing tells them what changed, so a fixed bug or a new feature goes unnoticed. On the first open after an update, a short "Novedades de Aldia" dialog lists what's new since the version they last saw. A fresh install shows nothing, because there's nothing to catch up on.

## Where

The app has no changelog at all: `grep -rnE "changelog|whats_new|last_seen_version" lib` returns nothing. The fix is wired in here:

```dart
// lib/main.dart:26-28 — current
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
```

```dart
// lib/main.dart:71-83 — current
  runApp(
    AldiaApp(
      repository: repository,
      location: const GeolocatorLocationService(),
      photos: CameraPhotoService(),
      geocoder: NominatimGeocoder(client: client),
      drafts: drafts,
      outbox: outbox,
      connectivity: connectivity,
      clusters: HttpClustersApi(client: client),
      showOnboarding: !(prefs.getBool(_onboardingKey) ?? false),
      onOnboardingDone: () => unawaited(prefs.setBool(_onboardingKey, true)),
    ),
  );
```

```dart
// lib/app.dart:25-38 — current (AldiaApp constructor)
  const AldiaApp({
    super.key,
    required this.repository,
    required this.location,
    required this.photos,
    this.geocoder,
    this.drafts,
    this.outbox,
    this.connectivity,
    this.clusters,
    this.tileProvider,
    this.showOnboarding = false,
    this.onOnboardingDone,
  });
```

```dart
// lib/app.dart:55-56 — current
  /// Called once when the slides end or are skipped (to remember it).
  final VoidCallback? onOnboardingDone;
```

```dart
// lib/app.dart:143 — current
                    : const HomeScreen(),
```

```dart
// lib/features/home/home_screen.dart:38-40 — current
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

```

```dart
// lib/features/home/home_screen.dart:62-69 — current
  @override
  void initState() {
    super.initState();
    _list = _loadList();
    _resolved = _loadResolved();
    unawaited(_loadDraft());
    unawaited(_observeMine());
  }
```

## The fix

The article's approach, using this app's tools: a versioned changelog map in Dart, a function that collects every change between the last seen version and the current one (using `pub_semver`), a controller that reads the version with `package_info_plus` and stores the last seen one in `shared_preferences`, and a dialog shown once from Home. The app uses `ChangeNotifier` and `provider`, not Cubit, so the controller is a `ChangeNotifier`.

New file `lib/features/changelog/changelog.dart`, exactly:

```dart
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
```

## Steps

1. Ask the developer to approve the two dependencies. If they say no, STOP.
2. Run `mise exec -- flutter pub add package_info_plus pub_semver` (without mise: `flutter pub add package_info_plus pub_semver`). Don't edit `pubspec.lock` by hand. If `package_info_plus` is already a direct dependency in `pubspec.yaml` (the "app version" plan also adds it), add only `pub_semver`.
3. Create `lib/features/changelog/changelog.dart` with the exact content from "The fix".
4. In `lib/main.dart`, add `import 'features/changelog/changelog.dart';` after `import 'features/drafts/draft_store.dart';`. Right after the line `final prefs = await SharedPreferences.getInstance();` add:

   ```dart
     final changelog = ChangelogController(preferences: prefs);
     try {
       await changelog.initialize();
     } catch (_) {
       // An unreadable version never blocks the app; the dialog just stays away.
     }
   ```

   Then in the `AldiaApp(` call, add `changelog: changelog,` as the last argument, after `onOnboardingDone: ...`.
5. In `lib/app.dart`:
   - Add `import 'features/changelog/changelog.dart';` after `import 'core/theme.dart';`.
   - In the `AldiaApp` constructor, add `this.changelog,` after `this.onOnboardingDone,`.
   - After the field `final VoidCallback? onOnboardingDone;` add:

     ```dart

       /// Shows "Novedades" on the first open after an update.
       final ChangelogController? changelog;
     ```
   - Replace `: const HomeScreen(),` with `: HomeScreen(changelog: widget.changelog),`.
6. In `lib/features/home/home_screen.dart`:
   - Add `import '../changelog/changelog.dart';` after `import '../citizen/citizen_screens.dart';`.
   - Replace

     ```dart
     class HomeScreen extends StatefulWidget {
       const HomeScreen({super.key});
     ```
     with

     ```dart
     class HomeScreen extends StatefulWidget {
       const HomeScreen({super.key, this.changelog});

       /// Pending "Novedades" to show once. Null in tests.
       final ChangelogController? changelog;
     ```
   - In `_HomeScreenState.initState`, after `unawaited(_observeMine());`, add:

     ```dart
         WidgetsBinding.instance.addPostFrameCallback((_) {
           if (mounted) unawaited(showChangelogIfNeeded(context, widget.changelog));
         });
     ```
7. Run `mise exec -- dart format lib/features/changelog/changelog.dart lib/main.dart lib/app.dart lib/features/home/home_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "package_info_plus:\|pub_semver:" pubspec.yaml` → 2
4. `grep -c "ChangelogController(preferences: prefs)" lib/main.dart` → 1
5. `grep -c "HomeScreen(changelog: widget.changelog)" lib/app.dart` → 1
6. `grep -c "showChangelogIfNeeded" lib/features/home/home_screen.dart` → 1

## Don't touch

- The onboarding flow and its `onboarding_seen` key: a fresh install shows the slides, never the changelog.
- Tests that build `const HomeScreen()`: the new parameter is optional, so they keep working.
- Remote changelog fetching and more languages: out of scope for now.
- No new dependencies beyond the two in the header.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have added lines next to the quoted ones (an extra argument, an import). That's expected; keep them.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: Aldia now shows a short "Novedades de Aldia" dialog the first time it opens after an update, listing every change since the version the user last saw. To see it, add an entry for the next version to `_changelog` in `lib/features/changelog/changelog.dart`, raise `version:` in `pubspec.yaml`, and install over the old build.

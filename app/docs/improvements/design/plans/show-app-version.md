# Fix: The version shown in Perfil is typed by hand and goes stale

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/show-app-version
- **Needs new dependency**: `package_info_plus`, which reads the installed version and build number. It's already in `pubspec.lock` as an indirect dependency, but it must become a direct one. The project rules (AGENTS.md) say to ask before adding a dependency, so get the developer's OK first. Shorebird isn't used (it's not in `pubspec.yaml`), so there's no patch number to show.

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

When a citizen reports a bug, the first question is which version they're on. Perfil does show "Versión de Aldia", but the value is the string `'0.1.0+1'` typed into the code. It won't change when `pubspec.yaml` moves to a new version, so after the next release it answers that question wrong. Reading the real version and build number from the installed app keeps it accurate.

## Where

Nothing reads the app version (`grep -rnE "PackageInfo|package_info_plus|buildNumber" lib` returns nothing). The hard-coded line:

```dart
// lib/features/citizen/citizen_screens.dart:269-274 — current
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('Versión de Aldia'),
                subtitle: Text('0.1.0+1'),
              ),
```

## The fix

The article's drop-in `VersionIndicator`, without the Shorebird part, as a new file `lib/widgets/version_indicator.dart`. Two changes from the article: the color comes from the theme (`onSurfaceVariant`) because the app has no hard-coded colors, and the platform call is wrapped in `try`, because widget tests have no plugin and the line should simply stay hidden there. The ListTile title already says "Versión de Aldia", so the label is the version and build only, for example `0.1.0 (1)`.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed version and build number, read from the platform.
class VersionIndicator extends StatefulWidget {
  const VersionIndicator({super.key});

  @override
  State<VersionIndicator> createState() => _VersionIndicatorState();
}

class _VersionIndicatorState extends State<VersionIndicator> {
  String? _label;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();

      if (!mounted) return;

      setState(() {
        _label = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      // Widget tests have no platform plugin; the line stays hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_label == null) {
      return const SizedBox.shrink();
    }

    return Text(
      _label!,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
```

Target in Perfil:

```dart
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('Versión de Aldia'),
                subtitle: VersionIndicator(),
              ),
```

## Steps

1. Ask the developer to approve `package_info_plus`. If they say no, STOP.
2. Run `mise exec -- flutter pub add package_info_plus` (without mise: `flutter pub add package_info_plus`). Don't edit `pubspec.lock` by hand. If `package_info_plus` is already a direct dependency in `pubspec.yaml` (the changelog plan also adds it), skip this step.
3. Create `lib/widgets/version_indicator.dart` with the exact content from "The fix".
4. `lib/features/citizen/citizen_screens.dart`: add `import '../../widgets/version_indicator.dart';` after `import 'login_sheet.dart';`. Replace `subtitle: Text('0.1.0+1'),` with `subtitle: VersionIndicator(),`.
5. Run `mise exec -- dart format lib/widgets/version_indicator.dart lib/features/citizen/citizen_screens.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "package_info_plus:" pubspec.yaml` → 1
4. `grep -c "0.1.0+1" lib/features/citizen/citizen_screens.dart` → 0
5. `grep -c "subtitle: VersionIndicator()" lib/features/citizen/citizen_screens.dart` → 1

## Don't touch

- `version:` in `pubspec.yaml`: it stays the single source of the version.
- The other Perfil rows (number, public name, language).
- No new dependencies beyond `package_info_plus`; no Shorebird.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed other lines in this file (a list controller, a haptic call, an import). That's expected; keep them.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: Perfil → "Versión de Aldia" now shows the real installed version and build number, for example "0.1.0 (1)", read from the app itself, so it stays right after every release. To see it, open Perfil on a device.

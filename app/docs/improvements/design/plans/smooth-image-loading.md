# Fix: Report photos pop in with no placeholder

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/smooth-image-loading
- **Needs new dependency**: `image_fade`, which shows a placeholder while the photo loads, then cross-fades to the photo or to an error view. The project rules (AGENTS.md) say to ask before adding a dependency, so get the developer's OK first.

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

Report photos come from the server. Today the photo area is empty while a photo downloads, then the picture pops in all at once, and on the detail page a failed photo becomes a lone icon. With the fix, a plain grey box holds the place, the photo fades in when ready, and a failure shows a subtle icon on the same grey box.

## Where

1. The report card, used in Lista, Mis reportes, the map summary sheet, similar reports and duplicate results:

```dart
// lib/widgets/report_tile.dart:38-52 — current
                  Image.network(
                    repository.photoUrl(report),
                    height: 190,
                    fit: BoxFit.cover,
                    semanticLabel: S.photoLabel(category.label, state.label),
                    errorBuilder: (_, _, _) => Container(
                      height: 190,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        category.icon,
                        size: 56,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
```

2. The report detail photo:

```dart
// lib/features/detail/report_detail_screen.dart:98-109 — current
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.network(
            context.read<ReportRepository>().photoUrl(report),
            fit: BoxFit.contain,
            semanticLabel: S.photoLabel(category.label, state.label),
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image,
              semanticLabel: S.photoAlternative,
            ),
          ),
        ),
```

The `Image.memory` calls in `report_flow_screen.dart` show the photo just taken, from memory. They aren't network images, so they're out of scope.

## The fix

The article's `ImageFade` with a plain placeholder and a subtle error state, sized by the box the photo already sits in (190 tall on the card, 4:3 on the detail). The placeholder and error box use the theme's `surfaceContainerHighest`, the grey the card already uses for its failure state. The screen-reader label moves to a `Semantics` wrapper, so it's the same whatever `ImageFade` exposes.

```dart
// target — lib/widgets/report_tile.dart
                  SizedBox(
                    height: 190,
                    child: Semantics(
                      image: true,
                      label: S.photoLabel(category.label, state.label),
                      child: ExcludeSemantics(
                        child: ImageFade(
                          image: NetworkImage(repository.photoUrl(report)),
                          fit: BoxFit.cover,
                          placeholder: ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          errorBuilder: (context, exception) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              category.icon,
                              size: 56,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
```

```dart
// target — lib/features/detail/report_detail_screen.dart
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Semantics(
            image: true,
            label: S.photoLabel(category.label, state.label),
            child: ExcludeSemantics(
              child: ImageFade(
                image: NetworkImage(
                  context.read<ReportRepository>().photoUrl(report),
                ),
                fit: BoxFit.contain,
                placeholder: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorBuilder: (context, exception) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
```

(`theme` is already defined at the top of both `build` methods: `final theme = Theme.of(context);`.)

## Steps

1. Ask the developer to approve `image_fade`. If they say no, STOP.
2. Run `mise exec -- flutter pub add image_fade` (without mise: `flutter pub add image_fade`). Don't edit `pubspec.lock` by hand.
3. `lib/widgets/report_tile.dart`: add `import 'package:image_fade/image_fade.dart';` after `import 'package:flutter/material.dart';`. Replace the `Image.network(` block quoted in "Where" (item 1) with the report-tile target.
4. `lib/features/detail/report_detail_screen.dart`: add `import 'package:image_fade/image_fade.dart';` after `import 'package:flutter/material.dart';`. Replace the `AspectRatio(` block quoted in "Where" (item 2) with the detail target.
5. Run `mise exec -- dart format lib/widgets/report_tile.dart lib/features/detail/report_detail_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass. If a test fails only because it looked for an `Image` widget or for the photo's semantics label in a different place, update that finder to the new structure, nothing else.
3. `grep -c "Image.network" lib/widgets/report_tile.dart` → 0
4. `grep -c "ImageFade(" lib/widgets/report_tile.dart` → 1
5. `grep -c "Image.network" lib/features/detail/report_detail_screen.dart` → 0
6. `grep -c "ImageFade(" lib/features/detail/report_detail_screen.dart` → 1

## Don't touch

- The `Image.memory` previews in `lib/features/report/report_flow_screen.dart`: local bytes, no loading time.
- `repository.photoUrl(report)` and the thumbnail logic in `report_repository.dart`.
- No new dependencies beyond `image_fade`.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed nearby lines (an import, a date line in the card). That's expected; keep those changes.
- After `pub add`, `ImageFade` has no `image`, `placeholder`, `errorBuilder` or `fit` parameter, or `errorBuilder` doesn't take `(BuildContext, Object)` (check the package's `lib/` in the pub cache).
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: report photos now show a plain grey box while they load and fade in when ready; if one fails, a subtle icon appears on the same grey box instead of an empty space. To see it, open "Explorar mi ciudad" → "LISTA" on a slow connection.

# Fix: The keyboard comes back after closing a sheet or dialog

> Follow the steps in order. Run every check. If anything in "STOP if"
> happens, stop and report instead of improvising.

- **Link**: https://flutterpro.design/details/md/unfocus-before-modal
- **Needs new dependency**: none

All paths are relative to the `app/` folder. Run every command from `app/`.

## Why

When a text field is focused and something opens a sheet or dialog (the report flow's help, the map layers, the filters, a map pin summary), closing it puts the focus back on the field and the keyboard pops up again, even though the citizen was done typing. Clearing the focus right before opening keeps the keyboard away.

## Where

Nothing calls `FocusManager.instance.primaryFocus?.unfocus()` (the only unfocus is `FocusScope.of(context).unfocus()` after picking an address, `report_flow_screen.dart:544`, which isn't a modal opener). Every opener on a page with a text field:

1. Report flow help dialog (the page has the address search, latitude/longitude, category search and note fields):

```dart
// lib/features/report/report_flow_screen.dart:114-118 — current
          IconButton(
            tooltip: 'Ayuda para reportar',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
```

2. Map layers sheet, used in the report flow's location step and in Explorar → MAPA (where the app-bar search field can be focused):

```dart
// lib/widgets/map_layers_button.dart:16-20 — current
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Capas del mapa',
    icon: const Icon(Icons.layers_outlined),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
```

3. Filters sheet in Explorar (app-bar search field):

```dart
// lib/features/home/home_screen.dart:130-132 — current
  Future<void> _editFilters() async {
    final result = await showModalBottomSheet<(String?, String?)>(
      context: context,
```

4. Report summary sheet from a map pin or a single-report cluster in Explorar (app-bar search field):

```dart
// lib/features/home/home_screen.dart:788-790 — current
  Future<void> _showSummary(Report report) {
    return showModalBottomSheet<void>(
      context: context,
```

## The fix

The article's one line, `FocusManager.instance.primaryFocus?.unfocus();`, as the first thing each opener does. `FocusManager` holds the field that is actually focused; `FocusScope.of(context)` only looks for the nearest scope, so it's the wrong tool here.

```dart
// target 1 — report_flow_screen.dart
          IconButton(
            tooltip: 'Ayuda para reportar',
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              showDialog<void>(
                context: context,
                // … the rest of the existing showDialog call, unchanged …
              );
            },
          ),
```

```dart
// target 2 — map_layers_button.dart
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Capas del mapa',
    icon: const Icon(Icons.layers_outlined),
    onPressed: () {
      FocusManager.instance.primaryFocus?.unfocus();
      showModalBottomSheet<void>(
        context: context,
        // … the rest of the existing showModalBottomSheet call, unchanged …
      );
    },
  );
```

```dart
// target 3 — home_screen.dart
  Future<void> _editFilters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showModalBottomSheet<(String?, String?)>(
```

```dart
// target 4 — home_screen.dart
  Future<void> _showSummary(Report report) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<void>(
```

## Steps

1. `lib/features/report/report_flow_screen.dart`: change `onPressed: () => showDialog<void>(` of the "Ayuda para reportar" button into a block body: `onPressed: () {`, then `FocusManager.instance.primaryFocus?.unfocus();`, then the existing `showDialog<void>( … )` call followed by `;`, then `},`. Keep the whole `showDialog` call (title, content, actions) exactly as it is.
2. `lib/widgets/map_layers_button.dart`: the same change for `onPressed: () => showModalBottomSheet<void>(`: block body, the unfocus line first, then the existing call with `;`, then `},`. If another plan already replaced `showModalBottomSheet<void>(` with a different opener (for example `showSpringBottomSheet<void>(`), apply the same change to that call.
3. `lib/features/home/home_screen.dart`: add `FocusManager.instance.primaryFocus?.unfocus();` as the first line of `_editFilters()` and as the first line of `_showSummary(Report report)`.
4. Run `mise exec -- dart format lib/features/report/report_flow_screen.dart lib/widgets/map_layers_button.dart lib/features/home/home_screen.dart`.

## Check it

Run from `app/`:

1. `mise exec -- flutter analyze` → `No issues found!`
2. `mise exec -- flutter test` → all tests pass.
3. `grep -c "FocusManager.instance.primaryFocus?.unfocus();" lib/features/report/report_flow_screen.dart` → 1
4. `grep -c "FocusManager.instance.primaryFocus?.unfocus();" lib/widgets/map_layers_button.dart` → 1
5. `grep -c "FocusManager.instance.primaryFocus?.unfocus();" lib/features/home/home_screen.dart` → 2

## Don't touch

- `FocusScope.of(context).unfocus()` after picking an address (`report_flow_screen.dart:544`): it isn't a modal opener.
- The "Más opciones" popup menu in Explorar (`home_screen.dart:286`): `PopupMenuButton` opens itself and has no hook before opening.
- Dialogs on pages without text fields (Perfil's "Borrar mis datos", Mis reportes' delete confirmations).
- No new dependencies.
- No refactors, renames, or cleanups beyond the fix.
- Don't commit; the developer reviews and commits.

## STOP if

- The code at any location in "Where" doesn't match the quoted excerpt. Exception: another plan in `docs/improvements/design/plans/` may already have changed these openers (a different sheet function or route instead of `showModalBottomSheet`, a haptic call). That's expected; put the unfocus line first in whatever opener is there now.
- The fix seems to require touching something in "Don't touch".
- A check fails twice.

## When you're done

Tell the developer: opening the report help, the map layers, the filters or a map pin summary now closes the keyboard first, so it doesn't jump back when the sheet or dialog closes. To see it, type in "Buscar dirección" in Reportar, tap the help icon and close the dialog.

# Citizen app UI notes

Scope: `app/` (Flutter, Spanish Guatemala). Restyle of the existing flows; no behavior, API or dependency changes.

## Principles taken from public reference material

Sources: the public App Store listing of SeeClickFix and its public description of features. The two Google Play pages
and the developer documentation (`dev.seeclickfix.com`, HTTP 403) could not be read, so no screenshot captions or API
fields were used. Only ideas, in our own words; no text, icon, asset or color was copied, nothing was decompiled.

- A reporting app has few top-level places. Bottom navigation with three destinations is enough (map, list, my items).
- Starting a report is the one primary action and is always reachable, not hidden in a menu.
- A report is photo first, then place, then category, then optional details; each step is short and answers one question.
- Looking for an existing report before filing a new one reduces duplicates; show nearby reports on a map.
- Public requests are scannable cards: a picture, what it is, where it stands, how old it is.
- Anonymous use is possible; an account is not a precondition for helping.
- Reviews of the reference app complain about required fields off screen and unreadable errors: keep required
  input visible and errors specific, with a fix (already the wording in `strings.dart`).

## Screen map

```
First run only: Onboarding (3 slides: what Aldia is / live photo rule / privacy; "Omitir" always visible)
Home (shell) ── AppBar: Aldia, filters (map and list only)
 ├─ Mapa        clusters or pins (icon + state text), tap opens summary sheet
 ├─ Lista       compact report cards, pull to refresh, empty state, "quitar filtros"
 ├─ Mis reportes  por enviar, borradores, enviados; empty state with "Hacer mi primer reporte"
 ├─ Banner "Continuar borrador" (map and list tabs)
 └─ Reportar (extended button, centered above the bar, on every tab)
      Wizard: Foto > Ubicación > Categoría > Duplicados > Detalles > Revisar > Resultado
Detail: photo, state chips, timeline, similar reports, checks
```

## Decisions

- Navigation: `NavigationBar` (Mapa / Lista / Mis reportes); tabs are built on first visit and kept alive
  (`IndexedStack`) so the map camera and list scroll survive tab changes.
- Report card (`widgets/report_tile.dart`): 72 dp rounded thumbnail, category, `StateChip` (icon + text, tonal fill),
  age. Thumbnail falls back to the category icon.
- Category step: full-width 64 dp rows with icon, label and check; selected row has a thicker border and tonal fill.
- Wizard progress: one "Paso x de 6" line plus a progress bar instead of the full list of step names.
- Empty states (`widgets/empty_state.dart`): icon, one sentence, optional help and one action.
- Onboarding: three slides, skippable, no permission request, shown once (`shared_preferences`, key `onboarding_seen`).
  The app shell only receives `showOnboarding` and `onOnboardingDone`, so tests do not touch storage.
- Tokens (`lib/core/theme.dart`): brand colors unchanged (`documentation/design-tokens.md`); new `AldiaSpace` scale
  (4, 8, 12, 16, 24, 32), 48 dp target, 88 dp bottom clearance for the report button.
- Dark mode: `buildDarkTheme()` from the same seed through `ColorScheme`; `ThemeMode.system`. Widgets use scheme
  roles (`primary`, `errorContainer`, `surfaceContainerLowest`...) instead of fixed colors. The portal tokens file
  is unchanged; dark mode is app-only for now.
- Motion: page and sheet transitions and the navigation indicator are skipped when the system asks to reduce
  motion; onboarding uses `jumpToPage` in that case.
- Low-end Android: no new packages, no shadows or blur, no animation beyond the Material defaults; lazy tabs.
- Text scale 2.0: cards wrap, the draft banner scrolls inside a 30 % height cap, the empty state scrolls.

## Skill files read for this work

Read only (no installer or network script run): `impeccable/reference/new-work.md`, `craft-floor.md`, `polish.md`,
`audit.md` (web audit; its native counterpart was not read), `emil/mobile-native/SKILL.md` (web-specific, used only
for the "test on real hardware" rule) and `anthropics-skills/hks-frontend-design/SKILL.md`. Applied: inherit the
established identity instead of inventing a new one, check empty/loading/error states, spacing and type scale, tonal
contrast, copy that names the action and the recovery. The onboarding reference (`onboard.md`) was not opened;
the slide count and skip rule come from the task brief.

## Not verified

- Contrast ratios were not measured; dark colors come from `ColorScheme.fromSeed`.
- No device or emulator run, no screenshots. Tests are golden-free widget tests.
- Store pages and API docs listed above were unreachable.

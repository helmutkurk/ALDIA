# Citizen app UI notes

Scope: `app/`, Spanish (Guatemala). **Updated 2026-11-21** for Phase 3 (implementation of the approved design).
Only reference principles are used; no SeeClickFix/FixMyStreet assets, text, colors or source code were copied.

Where things are:
- Decisions: [`../decisions/ux-2026-11-21.md`](../decisions/ux-2026-11-21.md) (login at send, nearby step only on
  matches, citizen wording in public, palette, Explorar map, name **AlDía**).
- UX specs and test kit: [`../../app/docs/ux/`](../../app/docs/ux/). Low-fi wireframes and clickable prototype: Figma
  file "Aldia - prueba MCP", page "Wireframes low-fi".
- Phase 3 progress, next steps and open to-dos: [`../../app/docs/ux/implementation-status.md`](../../app/docs/ux/implementation-status.md).
- Tokens: [`../design-tokens.md`](../design-tokens.md), implemented in `lib/core/theme.dart` (`AldiaColors`,
  `AldiaRadius`, `AldiaSpace`, light and dark `ColorScheme`), tested in `test/core/theme_test.dart`.

## Current palette and shapes (since PR #24)

Guatemala sky-blue palette: primary `#2A6FA8` (pressed and links `#235E8F`), brand `#4997D0` for non-text marks,
coral accent `#FF7A59` with dark text for the key call to action and badges, white page, light-sky cards `#EAF4FB`.
Status dots and pins: open amber `#B26A00`, in work violet `#7E57C2`, resolved green `#17735A`, closed gray, rejected
red, pending hollow; always with the state word. Pill buttons (52 dp) and chips, cards 20 dp, sheets and dialogs 28 dp.
Transitional: the shell top bar (`AldiaColors.bar`) is blue `#235E8F` until Inicio and the other tabs move to light
surfaces. The portal still uses the previous teal palette.

## Current screen map (develop, 2026-11-21)

```
First run: skippable onboarding (3 slides), then "Entra a AlDía" (login at start; see implementation-status: to change)
Shell: Inicio | Avisos | (+) Reportar (coral pill) | Mis reportes | Perfil
 Inicio: blue bar landing, resolved counter, Explorar mi ciudad, Reportar un problema, draft banner
 Explorar (PR #26): full-screen map, no app bar; floating back, Mapa | Lista switch, filter button with count
  Mapa: clusters or pins (category icon on state color + state word), legend, zoom, my location, layers,
        loading / empty / error banners
  Lista: same header; large-photo cards (16:9 photo, state dot + word, category, coordinates, note, date, reference)
  Filtros: bottom sheet with search, category chips, state-group chips (sent as state_group)
 Avisos: locally observed state changes, refresh, offline stored inbox (no push)
 Mis reportes: outbox, saved drafts, sent/followed reports
 Perfil: masked phone or test account, sign out / verify, language, version, delete local data
Wizard: Ubicación > Categoría > Foto > Detalles > Revisar y enviar > Resultado
 (no nearby step and no sign-in at send since PR #18; decisions say to restore both: Phase 3 steps 5 and 6)
Detail: photo, state chips, explanation, official message, timeline, nearby reports, checks
Shared widgets: AldiaBanner (info/warning/error), EmptyState, ReportTile, StatusDot/StatusLabel, StatusMapPin
```

## History: seven tasks of 2026-11-20 (partly superseded)

The sections below describe the SeeClickFix-parity work of 2026-11-20. Superseded since then: the teal/graphite
palette (now the sky-blue tokens), the MAPA/LISTA tabs and app-bar search (now the full-screen map and filter sheet),
and the nearby-duplicates step (removed in PR #18, to come back only when there are matches).

### Seven tasks implemented in order

1. **Wizard and summary.** Location first, category, nearby suggestions, mandatory live photo, optional note, review/send.
   Every editing step repeats a camera icon, place (address when selected, coordinates otherwise) and chosen category.
   Progress and focusable semantic headings remain. Old drafts restore by step name and retain their idempotency key;
   incomplete old photo-first drafts return to the first missing prerequisite.
2. **Location.** Explicit address search, GPS, outlined graphite pin, zoom, layer visibility and coordinate inputs. The full-width
   **CONFIRMAR UBICACIÓN** control is in the bottom safe area. GPS failure explains manual recovery; accuracy warnings
   remain visible. The chosen address is saved only in the local draft.
   `GeocoderService` is injectable; tests use a fake. Nominatim requires Search/Enter, debounces 450 ms, serializes at
   1 request/second, caches results, identifies Aldia, requests Spanish and restricts `countrycodes=gt,co,mx`.
   Attribution is visible. No autocomplete: the [public service policy](https://operations.osmfoundation.org/policies/nominatim/)
   forbids it. This is single-device demo geocoding; a multi-user rollout needs a centrally limited, remotely switchable
   proxy/provider. A failed search leaves manual placement available.
3. **Categories.** Search plus group headers from `GET /api/categories`, with contract defaults while offline.
   Selectable rows wrap, expose selection semantics and retain 64 dp minimum height.
4. **Nearby.** Existing nearby endpoint; photo cards with citizen state and local heart, plus **Seguir este reporte**
   to finish without a new upload. Empty/offline suggestions show a non-blocking explanation instead of hiding the step.
5. **Photo and review.** Circular camera target, required live capture, preview and retake. No gallery or skip link.
   Note, review edits, upload-size estimate, public-photo warning and verifier recovery wording remain.
   `DEV_FAKE_CAMERA=true` draws a labeled 640×480 synthetic PNG only in non-mobile debug; release and mobile never fake.
6. **Landing and navigation.** Five destinations; the central circled plus opens the wizard without replacing the
   selected tab. Home offers the two large actions and a count from `/api/stats` (failure shows an unavailable marker).
   The counter reflects the API's default period, so the UI makes no all-time claim. Explore has MAPA/LISTA tabs.
   Visited shell tabs retain state, map camera and list position. Draft banner remains available from Inicio/Explorar.
7. **Cards, inbox and profile.** Large-photo cards include a status word beside its state icon, category, coordinates, note,
   date/reference and independent semantic follow/share targets. No address is invented: reports have no street field.
   Hearts, state baselines, up to 100 inbox items and visibility preference persist through `shared_preferences`.
   Refreshing personal/followed reports or opening their detail records a changed state once; first observation stays quiet.
   Android/iOS share through native sheets (WhatsApp if installed); Linux opens the WhatsApp URL, with clipboard fallback.
   `PUBLIC_PORTAL_URL` supplies public links. Profile clearly labels phone access as pending and name visibility as local.
   Confirmed deletion clears drafts/photos, outbox, personal ids, follows/notices/preferences; server reports remain public.

## Preserved behavior and accessibility

- Draft autosave, outbox persistence/retry and Idempotency-Key are unchanged; the local inbox cannot make an accepted
  upload retry. The existing 11-state citizen wording and honest stub-verification wording are retained.
- Semantic headings, state text alongside color, distinct card/action targets, 48 dp controls and scrollable 200% text
  layouts. Bottom confirmation stays reachable while the map/form scrolls. Reduced motion disables routes/sheets,
  navigation indicators and Explore tab animation. No new packages, fonts or copied assets.
- Light/dark `ColorScheme` and Aldia tokens. Cards wrap text instead of truncating descriptions. Public map pin labels
  retain the existing compact label treatment, with the complete state in semantics and in cards.
- Phone-code login and push still need backend integration. The existing manual-review action saves locally; it does
  not claim to submit a server review.

## Validation and limits

- Calm-palette update (2026-11-20): format, analyzer clean, **106/106 tests passed**, `flutter build linux --debug` built.
  Explorar gained a search field (filters the list by category, state word and note), a locate action that centers the map,
  and an overflow menu (refresh, clear filters). Not exercised: physical devices, real tiles, live camera, screenshots
  against the reference (no visual diff was made).

### Previous validation (neutral palette, 2026-11-19)

- Neutral-palette checks: format completed; analyzer clean; **104/104 tests passed**, including new WCAG token-pair
  and light/dark status-word/icon tests. The map regression checks that different states retain the same outlined
  graphite fill. Existing onboarding, navigation, drafts, outbox, report flow and 200% text tests remain green.
  The requested bare `mise exec -- dart format lib test`, `mise exec -- flutter analyze` and `mise exec -- flutter test`
  hit the installed SDK's read-only cache. Successful runs used the same Flutter/Dart versions through
  `mise exec -- env PATH=/tmp/aldia-flutter-sdk/bin:$PATH PUB_CACHE=/tmp/aldia-pub-cache` followed by each command,
  without `--no-pub`. No dependencies or lockfiles changed.
- Palette render checks use Flutter widget rendering with fake reports, offline tiles and a photo error placeholder,
  at 375×812 in light/dark mode (onboarding, home, map and list) and 812×375 (list). These are not physical-device
  checks; real map tiles, live photos, native sharing and API submission were not exercised by this palette task.

### Earlier screen-flow validation (before the neutral palette)

- Existing wizard/controller/outbox/draft/navigation/accessibility tests were updated; focused geocoder rate/cache,
  explicit-search, local inbox persistence and synthetic-camera checks were added. Tests use offline tiles and fakes.
- Linux platform generated with Flutter; unrelated generated metadata, lockfile and analyzer changes were restored.
- Final checks: `dart format lib test` completed; `flutter analyze --no-pub` clean; `flutter test --no-pub` **98/98 passed**;
  `flutter build linux --debug --no-pub` passed with the local API URL and `DEV_FAKE_CAMERA=true`.
  Commands ran through `mise exec -- env PATH=/tmp/aldia-flutter-sdk/bin:$PATH PUB_CACHE=/tmp/aldia-pub-cache`
  because the installed SDK/cache is read-only in this sandbox.
- `flutter run -d linux` built and attached successfully; the Aldia landing and five-tab bar were visually observed.
  Temporary XDG config/data/documents directories keep demo storage inside `/tmp`. GTK/dconf and Mesa printed sandbox
  warnings; rendering still worked. An unavailable API exposed a lazy-list unhandled error, now fixed and hot-restarted.
  `http://localhost:8000/api/health` was unreachable during the desktop check, so real API submission could not be verified.
- No physical Android/iOS verification or native share-sheet compilation on this Linux machine. Public Nominatim/OSM
  and actual WhatsApp handoff are not exercised by unit/widget tests.

## Design guidance used

`hks-disciplina-de-trabajo`, `hks-flujo-codigo`, `hks-flutter` (responsive layout guidance) and `hks-diseno-interfaz`
(`impeccable/reference/new-work.md`, `craft-floor.md`) informed the implementation. The user's specified screen structure
and existing Aldia identity determined the design. No new design direction, assets or package installation was needed.
For the neutral-palette update, `hks-diseno-interfaz` used UI UX Pro Max's contrast/color-only guidance and native-app
checklist; `hks-flutter` used widget-test guidance. Helmut's supplied tokens determined the colors.

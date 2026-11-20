# Citizen app UI notes

Scope: `app/`, Spanish (Guatemala). Updated 2026-11-20: seven tasks of `app-reference-seeclickfix.md` plus the calm palette of `../design-tokens.md`.
Only reference principles are used; no SeeClickFix/FixMyStreet assets, text, colors or source code were copied.
Colors and spacing/target tokens live in `lib/core/theme.dart`.

## Calm SeeClickFix-style palette (2026-11-20)

Binding tokens: `../design-tokens.md`, implemented in `lib/core/theme.dart` (`AldiaColors`, light and dark `ColorScheme`).
This replaces the neutral graphite palette of 2026-11-19.

- `bar` `#3A3F44` (dark `#23292E`): top bar of the shell and Explorar, the MAPA/LISTA tab strip and the Inicio landing
  background; white text (10.6:1). Other sheets (wizard) use the white `surface` header with title, help and close icons.
- `primary` `#0F7A99`: full-width buttons (CONFIRMAR UBICACION, SIGUIENTE, ENVIAR), pressed `#0B6079`. Dark mode uses
  `#4FB8D6` with dark text. Text buttons and links use `#0B6079` (the base teal is 4.48:1 on the page gray, so it is not
  used for text).
- `accent` `#E8731A`: only the tab underline (never text). Page `#F3F4F6`, cards `#FFFFFF`, border `#D9DEE3`,
  text `#1F2933`, muted `#52606D`.
- Status colors paint the dot or pin only: open orange, in work/scheduled green, resolved blue, closed gray, rejected red,
  pending verification a hollow dot. The word always sits beside the dot in the normal text color (`StatusDot`,
  `StatusLabel`; chips keep icon + word). The eleven-state citizen wording is unchanged.
- `StatusMapPin`: status-colored disc, white 3 dp outline, white center with the state letter in text color (14:1).
  `NeutralMapPin` (primary fill) remains for clusters and the location-selection pin.
- Spacing scale `AldiaSpace` (4/8/12/16/24/32, 48 dp targets). Pressed and ripple states come from the theme (ink ripple,
  darker pressed buttons); empty and error states use `EmptyState`.
- `test/core/theme_test.dart` checks every text/background pair at 4.5:1 in light and dark (buttons, containers, snackbar,
  top bar and tab label on `bar`, pin letter, text buttons and body/secondary text on every surface) and every status
  dot at 3:1 against the surface (non-text).

## Screen map

```
First run: skippable onboarding (3 slides)
Shell: Inicio | Avisos | (+) Reportar | Mis reportes | Perfil
 Inicio: dark `bar` landing, Aldia mark, big resolved counter, Explorar mi ciudad, Reportar un problema
 Explorar: dark bar with search, locate, filter and menu icons; MAPA / LISTA with accent underline
 MAPA: viewport clusters/pins, summary sheet, zoom, locate, overlay/layer control
 LISTA: large-photo cards, status dot + word, location, note, date/id, heart/share
 Avisos: locally observed state changes, refresh, offline stored inbox
 Mis reportes: outbox, saved drafts, sent/followed reports (existing behavior)
 Perfil: phone placeholder, name-visibility preference, language/version, local data deletion
Wizard: Ubicación > Categoría > Duplicados > Foto en vivo > Detalles > Revisar/enviar > Resultado
Detail: photo, citizen state + verifier verdict, public timeline, nearby reports, checks
```

## Seven tasks implemented in order

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

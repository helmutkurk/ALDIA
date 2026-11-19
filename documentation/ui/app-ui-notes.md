# Citizen app UI notes

Scope: `app/`, Spanish (Guatemala). Updated 2026-11-19 for the seven binding tasks in `app-reference-seeclickfix.md`.
Only reference principles are used; no SeeClickFix/FixMyStreet assets, text, colors or source code were copied.
Aldia retains the teal palette and spacing/target tokens in `lib/core/theme.dart`.

## Screen map

```
First run: skippable onboarding (3 slides)
Shell: Inicio | Avisos | (+) Reportar | Mis reportes | Perfil
 Inicio: branded landing, resolved count, Explorar mi ciudad, Reportar un problema
 Explorar: dark teal bar, filters, MAPA / LISTA with accent underline
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
2. **Location.** Explicit address search, GPS, accent pin, zoom, layer visibility and coordinate inputs. The full-width
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
7. **Cards, inbox and profile.** Large-photo cards include a status word beside its dot, category, coordinates, note,
   date/reference and independent semantic follow/share targets. No address is invented: reports have no street field.
   Hearts, state baselines, up to 100 inbox items and visibility preference persist through `shared_preferences`.
   Refreshing personal reports or opening their detail records a changed state once; first observation stays quiet.
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

- Existing wizard/controller/outbox/draft/navigation/accessibility tests were updated; focused geocoder rate/cache,
  explicit-search, local inbox persistence and synthetic-camera checks were added. Tests use offline tiles and fakes.
- Linux platform generated with Flutter; unrelated generated metadata, lockfile and analyzer changes were restored.
- Final validation results and observed desktop limits are recorded below after running the checks.
- No physical Android/iOS verification or native share-sheet compilation on this Linux machine. Contrast ratios have
  not been measured. Public Nominatim/OSM and actual WhatsApp handoff are not exercised by unit/widget tests.

## Design guidance used

`hks-disciplina-de-trabajo`, `hks-flujo-codigo`, `hks-flutter` (responsive layout guidance) and `hks-diseno-interfaz`
(`impeccable/reference/new-work.md`, `craft-floor.md`) informed the implementation. The user's specified screen structure
and existing Aldia identity determined the design. No new design direction, assets or package installation was needed.

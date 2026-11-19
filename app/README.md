# app

Citizen app in Flutter / Dart (Android and iOS), Spanish (Guatemala). Product reference: SeeClickFix. It sends
photo reports of street problems to the Aldia API; the backend verifies each photo.
Contract: `../documentation/api-contract.md`. Setup for Android Studio and Xcode: `../documentation/dev-setup.md`.

## Flow

0. **First run**: three skippable slides (what Aldia is, live-photo rule, privacy); remembered in
   `shared_preferences` (`onboarding_seen`).
1. **Home** shell with bottom navigation: **Mapa**, **Lista**, **Mis reportes**, and an extended "Reportar" button on
   every tab. The map asks `GET /api/reports/clusters` for the visible viewport and falls
   back to plain reports (also when a filter is active, since clusters have no filters). Pins show the state as icon plus
   text; tapping one opens a summary sheet. Filters by state and category (app bar action, map and list only).
   "Continuar borrador" banner when a draft exists. Reports are compact cards: thumbnail, category, state chip, age.
2. **Report** wizard: photo (live camera), place (GPS, accuracy warning, manual pin), category, duplicates
   (`GET /api/reports/nearby`, skipped when empty or offline), details, review and send, result with one message per
   failed verifier check. Every step saves a draft; sending offline queues the report ("Esperando red").
3. **Mis reportes**: outbox ("Por enviar", retry now, delete with one confirmation), drafts, then sent reports.
   The empty state invites the first report.
4. **Detail**: photo, state chips (icon plus text), timeline from `events` (public notes only), a hint when
   `duplicate_of` is set, similar nearby reports, verifier checks.

Citizen wording for the 11 contract states lives in one table, `lib/core/citizen_states.dart`; a missing `state`
(v0.1 server) is derived from `status` and `resolution`.

Outbox and drafts: JSON files plus photos in app-private documents (`path_provider`). The outbox retries with
exponential backoff when connectivity returns and on app resume; each report carries one persisted `Idempotency-Key`.

Look: light and dark `ColorScheme` (system), spacing scale `AldiaSpace`, notes in `../documentation/ui/app-ui-notes.md`.

Accessibility: 48 dp targets, semantic labels and headings, state never by color alone, text scale 200 % tested
(`test/widgets/large_text_test.dart`), page and sheet transitions skipped when the system reduces motion.

## Pending: login por teléfono y push

Both need backend work (phone-code auth, push tokens). `AuthService` and `NotificationsService`
(`lib/services/identity_services.dart`) are interfaces with no-op implementations; nothing calls a server yet.
Also pending: "Enviar para revisión manual" is only a UI state (the report is saved on the device; no endpoint),
and the follow-up "was it fixed?" question.

## Run

```bash
mise exec -- flutter pub get
mise exec -- flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api   # Android emulator
mise exec -- flutter run --dart-define=API_BASE_URL=http://localhost:8000/api  # iOS simulator
```

Build-time options (`--dart-define`): `API_BASE_URL`, `TILE_URL` (map tiles; the public OpenStreetMap server is for
light use only, use a provider or your own tiles in production).

## Checks

```bash
mise exec -- flutter analyze
mise exec -- flutter test
```

## Layout

```
lib/
  main.dart            composition root (real services, outbox sender)
  app.dart             MaterialApp, providers, outbox start and retry on resume
  core/                config, theme, categories, citizen_states (state wording table), strings (Spanish)
  data/                report model, ApiClient, ClustersApi, ReportRepository, MyReportsStore
  services/            location, live camera, connectivity, Auth/Notifications (no-op)
  features/            home (shell), onboarding, report (wizard), detail, mine, drafts, outbox
  widgets/             state chips, checks list, report card, empty state, reduced-motion route
test/                  model, API, wizard, drafts, outbox, home, shell and onboarding, detail, mine and large-text tests (offline)
android/, ios/         platform projects (permissions: camera, location, internet)
.idea/runConfigurations/  shared Android Studio run configurations
```

## Notes

- Release builds accept only live camera photos; debug on the iOS simulator falls back to the gallery.
- Debug builds allow `http` to the local API; release builds keep cleartext traffic off (use HTTPS).
- No accounts in v0: report ids sent from this device are kept locally for "Mis reportes".
- Application id: `org.aldia.aldia_app` (change before publishing to a store).
